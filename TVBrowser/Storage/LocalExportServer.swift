import Foundation
import Network
import Darwin

enum RemoteControlCommand {
    case moveCursor(dx: CGFloat, dy: CGFloat)
    case scroll(dx: CGFloat, dy: CGFloat)
    case click
    case back
    case typeText(String)
    case key(String)
    case openURL(String)
    case setZoom(Double)
    case action(String)
}

final class LocalExportServer {
    var onRemoteCommand: ((RemoteControlCommand) -> Void)?
    var onClientCountChanged: ((Int) -> Void)?
    var currentZoomProvider: (() -> Double)?

    private var listener: NWListener?
    private(set) var port: UInt16 = 8080
    private var didFallbackToEphemeralPort = false

    private let stateQueue = DispatchQueue(label: "com.local.tvbrowser.remoteserver.state")
    private var webSockets: [ObjectIdentifier: WebSocketClient] = [:]

    func start(onReady: @escaping (String?) -> Void) {
        stop()
        didFallbackToEphemeralPort = false
        startListener(port: NWEndpoint.Port(rawValue: 8080)!, onReady: onReady)
    }

    private func startListener(port desiredPort: NWEndpoint.Port?, onReady: @escaping (String?) -> Void) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcp.enableKeepalive = true
                tcp.keepaliveIdle = 10
                tcp.keepaliveInterval = 5
                tcp.keepaliveCount = 3
            }

            let listener: NWListener
            if let desiredPort = desiredPort {
                listener = try NWListener(using: params, on: desiredPort)
            } else {
                listener = try NWListener(using: params)
            }
            self.listener = listener

            var readyDelivered = false
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self = self, let listener = listener else { return }
                switch state {
                case .ready:
                    readyDelivered = true
                    if let assignedPort = listener.port?.rawValue {
                        self.port = assignedPort
                    }
                    let ip = Self.localIPAddress()
                    DispatchQueue.main.async {
                        if let ip = ip {
                            onReady("http://\(ip):\(self.port)")
                        } else {
                            onReady(nil)
                        }
                    }
                case .failed:
                    if !readyDelivered && !self.didFallbackToEphemeralPort && desiredPort != nil {
                        self.didFallbackToEphemeralPort = true
                        listener.cancel()
                        self.startListener(port: nil, onReady: onReady)
                        return
                    }
                    DispatchQueue.main.async { onReady(nil) }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            if !didFallbackToEphemeralPort && desiredPort != nil {
                didFallbackToEphemeralPort = true
                startListener(port: nil, onReady: onReady)
            } else {
                DispatchQueue.main.async { onReady(nil) }
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        stateQueue.async {
            for (_, client) in self.webSockets {
                client.connection.cancel()
            }
            self.webSockets.removeAll()
            DispatchQueue.main.async { [weak self] in
                self?.onClientCountChanged?(0)
            }
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        readHTTPRequest(connection: connection, buffer: Data())
    }

    private func readHTTPRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            var accum = buffer
            if let data = data {
                accum.append(data)
            }

            let separator = Data("\r\n\r\n".utf8)
            guard let headerEndRange = accum.range(of: separator) else {
                if isComplete || accum.count > 131072 {
                    connection.cancel()
                    return
                }
                self.readHTTPRequest(connection: connection, buffer: accum)
                return
            }

            let headerData = accum.subdata(in: 0..<headerEndRange.lowerBound)
            let bodyStart = headerEndRange.upperBound
            guard let headerString = String(data: headerData, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let lines = headerString.components(separatedBy: "\r\n")
            let requestLine = lines.first ?? ""
            let parts = requestLine.components(separatedBy: " ")
            let method = parts.count >= 1 ? parts[0].uppercased() : "GET"
            let rawPath = parts.count >= 2 ? parts[1] : "/"
            let path = rawPath.components(separatedBy: "?").first ?? "/"

            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                if let colon = line.firstIndex(of: ":") {
                    let k = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let v = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    headers[k] = v
                }
            }

            let contentLength = Int(headers["content-length"] ?? "0") ?? 0
            let currentBodyCount = accum.count - bodyStart
            if contentLength > 0 && currentBodyCount < contentLength && !isComplete && accum.count < 4_194_304 {
                self.readHTTPRequest(connection: connection, buffer: accum)
                return
            }

            let bodyData = currentBodyCount > 0 ? accum.subdata(in: bodyStart..<min(accum.count, bodyStart + max(0, contentLength))) : Data()

            if path == "/ws" && (headers["upgrade"]?.lowercased() == "websocket"),
               let wsKey = headers["sec-websocket-key"] {
                self.upgradeToWebSocket(connection: connection, key: wsKey, initialTrailingBytes: accum.subdata(in: bodyStart..<accum.count))
                return
            }

            self.routeHTTP(connection: connection, method: method, path: path, bodyData: bodyData)
        }
    }

    private func routeHTTP(connection: NWConnection, method: String, path: String, bodyData: Data) {
        if method == "POST" && path == "/import" {
            let html = String(data: bodyData, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                let added = BrowserStore.shared.importBookmarksHTML(html)
                let json = "{\"added\":\(added)}"
                self.sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", filename: nil, body: json)
            }
            return
        }

        if method == "POST" && path == "/cmd" {
            self.dispatchJSONCommand(bodyData)
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", filename: nil, body: "{\"ok\":true}")
            return
        }

        switch path {
        case "/marcadores.html":
            DispatchQueue.main.async {
                let body = BrowserStore.shared.exportBookmarksHTML()
                self.sendHTTPResponse(connection: connection, status: "200 OK", contentType: "text/html; charset=utf-8", filename: "marcadores.html", body: body)
            }
        case "/marcadores.json":
            DispatchQueue.main.async {
                let body = BrowserStore.shared.exportBookmarksJSON()
                self.sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", filename: "marcadores.json", body: body)
            }
        case "/contrasenas.csv":
            DispatchQueue.main.async {
                let body = BrowserStore.shared.exportCredentialsCSV()
                self.sendHTTPResponse(connection: connection, status: "200 OK", contentType: "text/csv; charset=utf-8", filename: "contrasenas.csv", body: body)
            }
        case "/manifest.json":
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/manifest+json; charset=utf-8", filename: nil, body: manifestJSON())
        case "/ping":
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", filename: nil, body: "{\"ok\":true}")
        default:
            DispatchQueue.main.async {
                let bmCount = BrowserStore.shared.bookmarks.count
                let pwCount = BrowserStore.shared.credentials.count
                let zoomPct = Int(round((self.currentZoomProvider?() ?? BrowserStore.shared.pageZoom) * 100))
                let html = self.remoteWebAppHTML(bookmarksCount: bmCount, passwordsCount: pwCount, currentZoomPct: zoomPct)
                self.sendHTTPResponse(connection: connection, status: "200 OK", contentType: "text/html; charset=utf-8", filename: nil, body: html)
            }
        }
    }

    private func sendHTTPResponse(connection: NWConnection, status: String, contentType: String, filename: String?, body: String) {
        var headers = "HTTP/1.1 \(status)\r\n"
        headers += "Content-Type: \(contentType)\r\n"
        headers += "Cache-Control: no-store\r\n"
        if let filename = filename {
            headers += "Content-Disposition: attachment; filename=\"\(filename)\"\r\n"
        }
        let bodyData = body.data(using: .utf8) ?? Data()
        headers += "Content-Length: \(bodyData.count)\r\n"
        headers += "Connection: close\r\n\r\n"

        var payload = headers.data(using: .utf8) ?? Data()
        payload.append(bodyData)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - RFC 6455 WebSocket Server

    private final class WebSocketClient {
        let connection: NWConnection
        var buffer = Data()

        init(connection: NWConnection, initialBytes: Data) {
            self.connection = connection
            self.buffer = initialBytes
        }
    }

    private func upgradeToWebSocket(connection: NWConnection, key: String, initialTrailingBytes: Data) {
        let accept = webSocketAcceptKey(for: key)
        let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
        let client = WebSocketClient(connection: connection, initialBytes: initialTrailingBytes)
        let clientId = ObjectIdentifier(client)

        stateQueue.async {
            self.webSockets[clientId] = client
            let count = self.webSockets.count
            DispatchQueue.main.async { [weak self] in
                self?.onClientCountChanged?(count)
            }
        }

        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.removeWebSocketClient(id: clientId)
                return
            }
            self?.processBufferedFrames(for: client, id: clientId)
            self?.receiveWebSocketLoop(for: client, id: clientId)
        })
    }

    private func removeWebSocketClient(id: ObjectIdentifier) {
        stateQueue.async {
            if let client = self.webSockets.removeValue(forKey: id) {
                client.connection.cancel()
            }
            let count = self.webSockets.count
            DispatchQueue.main.async { [weak self] in
                self?.onClientCountChanged?(count)
            }
        }
    }

    private func receiveWebSocketLoop(for client: WebSocketClient, id: ObjectIdentifier) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if error != nil {
                self.removeWebSocketClient(id: id)
                return
            }
            if let data = data, !data.isEmpty {
                client.buffer.append(data)
                self.processBufferedFrames(for: client, id: id)
            }
            if isComplete {
                self.removeWebSocketClient(id: id)
                return
            }
            self.receiveWebSocketLoop(for: client, id: id)
        }
    }

    private func processBufferedFrames(for client: WebSocketClient, id: ObjectIdentifier) {
        while client.buffer.count >= 2 {
            let b0 = client.buffer[client.buffer.startIndex]
            let b1 = client.buffer[client.buffer.startIndex + 1]
            let opcode = b0 & 0x0F
            let masked = (b1 & 0x80) != 0
            var payloadLen = UInt64(b1 & 0x7F)
            var offset = 2

            if payloadLen == 126 {
                guard client.buffer.count >= 4 else { return }
                let hi = UInt64(client.buffer[client.buffer.startIndex + 2])
                let lo = UInt64(client.buffer[client.buffer.startIndex + 3])
                payloadLen = (hi << 8) | lo
                offset = 4
            } else if payloadLen == 127 {
                guard client.buffer.count >= 10 else { return }
                var len: UInt64 = 0
                for i in 0..<8 {
                    len = (len << 8) | UInt64(client.buffer[client.buffer.startIndex + 2 + i])
                }
                payloadLen = len
                offset = 10
            }

            if payloadLen > 1_048_576 {
                removeWebSocketClient(id: id)
                return
            }

            let maskLen = masked ? 4 : 0
            let totalLen = offset + maskLen + Int(payloadLen)
            guard client.buffer.count >= totalLen else { return }

            var payload = Data(count: Int(payloadLen))
            if masked {
                let maskStart = client.buffer.startIndex + offset
                let dataStart = maskStart + 4
                for i in 0..<Int(payloadLen) {
                    payload[i] = client.buffer[dataStart + i] ^ client.buffer[maskStart + (i % 4)]
                }
            } else {
                let dataStart = client.buffer.startIndex + offset
                payload = client.buffer.subdata(in: dataStart..<(dataStart + Int(payloadLen)))
            }

            client.buffer.removeFirst(totalLen)

            switch opcode {
            case 0x8: // Close
                removeWebSocketClient(id: id)
                return
            case 0x9: // Ping -> Pong
                var pong = Data([0x8A, UInt8(min(payload.count, 125))])
                pong.append(payload.prefix(125))
                client.connection.send(content: pong, completion: .contentProcessed { _ in })
            case 0x1, 0x0: // Text / Continuation
                if let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                   (obj["type"] as? String) == "ping" {
                    sendWebSocketText("{\"type\":\"pong\"}", to: client)
                } else {
                    dispatchJSONCommand(payload)
                }
            default:
                break
            }
        }
    }

    private func sendWebSocketText(_ text: String, to client: WebSocketClient) {
        let data = Data(text.utf8)
        guard data.count < 126 else { return }
        var frame = Data([0x81, UInt8(data.count)])
        frame.append(data)
        client.connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func dispatchJSONCommand(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            return
        }

        let command: RemoteControlCommand?
        switch type {
        case "move":
            let dx = (obj["dx"] as? NSNumber)?.doubleValue ?? 0
            let dy = (obj["dy"] as? NSNumber)?.doubleValue ?? 0
            command = .moveCursor(dx: CGFloat(dx), dy: CGFloat(dy))
        case "scroll":
            let dx = (obj["dx"] as? NSNumber)?.doubleValue ?? 0
            let dy = (obj["dy"] as? NSNumber)?.doubleValue ?? 0
            command = .scroll(dx: CGFloat(dx), dy: CGFloat(dy))
        case "click":
            command = .click
        case "rightClick":
            command = .back
        case "text":
            let value = obj["value"] as? String ?? ""
            command = value.isEmpty ? nil : .typeText(value)
        case "key":
            let code = obj["code"] as? String ?? ""
            command = code.isEmpty ? nil : .key(code)
        case "url":
            let value = obj["value"] as? String ?? ""
            command = value.isEmpty ? nil : .openURL(value)
        case "zoom":
            if let value = (obj["value"] as? NSNumber)?.doubleValue {
                command = .setZoom(value)
            } else {
                command = nil
            }
        case "action":
            let name = obj["name"] as? String ?? ""
            command = name.isEmpty ? nil : .action(name)
        default:
            command = nil
        }

        if let command = command {
            DispatchQueue.main.async { [weak self] in
                self?.onRemoteCommand?(command)
            }
        }
    }

    private func webSocketAcceptKey(for clientKey: String) -> String {
        let combined = clientKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let data = Data(combined.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest).base64EncodedString()
    }

    // MARK: - Remote PWA HTML & Manifest

    private func manifestJSON() -> String {
        """
        {
          "name": "Platanet Mando",
          "short_name": "Platanet",
          "start_url": "/",
          "display": "standalone",
          "background_color": "#0b1120",
          "theme_color": "#0b1120"
        }
        """
    }

    private func remoteWebAppHTML(bookmarksCount: Int, passwordsCount: Int, currentZoomPct: Int) -> String {
        """
        <!DOCTYPE html>
        <html lang="es">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
            <meta name="apple-mobile-web-app-capable" content="yes">
            <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
            <link rel="manifest" href="/manifest.json">
            <title>Platanet · Mando, Ratón y Teclado</title>
            <style>
                :root { color-scheme: dark; }
                * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
                body {
                    margin: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    background: #0b1120; color: #f8fafc; padding: 14px; max-width: 680px; margin-inline: auto;
                }
                header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; }
                h1 { font-size: 18px; margin: 0; }
                .badge { font-size: 12px; padding: 4px 10px; border-radius: 999px; background: #1e293b; color: #94a3b8; }
                .badge.ok { background: #064e3b; color: #6ee7b7; }
                .row { display: flex; gap: 8px; margin-bottom: 10px; }
                input[type=text] {
                    flex: 1; background: #1e293b; border: 1px solid #334155; color: #fff;
                    padding: 12px 14px; border-radius: 12px; font-size: 16px; outline: none;
                }
                button {
                    background: #2563eb; color: #fff; border: 0; border-radius: 12px;
                    padding: 11px 14px; font-size: 14px; font-weight: 600; cursor: pointer;
                }
                button.sec { background: #1e293b; border: 1px solid #334155; color: #e2e8f0; }
                button:active { transform: scale(0.97); }
                #pad {
                    height: 280px; background: radial-gradient(circle at center, #1e293b, #0f172a);
                    border: 1.5px solid #334155; border-radius: 20px; touch-action: none;
                    display: flex; flex-direction: column; align-items: center; justify-content: center;
                    user-select: none; margin-bottom: 10px; text-align: center; padding: 16px;
                }
                #pad span { color: #94a3b8; font-size: 14px; line-height: 1.4; pointer-events: none; }
                .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin-bottom: 12px; }
                .card { background: #131c31; border: 1px solid #1e293b; border-radius: 16px; padding: 14px; margin-top: 12px; }
                .card h2 { font-size: 15px; margin: 0 0 8px; color: #cbd5e1; }
                a.dl {
                    display: block; text-decoration: none; background: #1e293b; color: #e2e8f0;
                    padding: 11px 14px; border-radius: 10px; margin-top: 8px; text-align: center; font-weight: 600; font-size: 14px;
                }
                .hint { font-size: 12px; color: #94a3b8; margin-top: 6px; }
            </style>
        </head>
        <body>
            <header>
                <h1>Platanet · Control Remoto</h1>
                <button id="status" class="badge" style="border:0;cursor:pointer;" onclick="forceReconnectWS()">Conectando...</button>
            </header>

            <div class="row">
                <input id="urlInput" type="text" placeholder="Buscar en Google o pegar URL..." enterkeyhint="go">
                <button onclick="sendURL()">Ir</button>
            </div>

            <div id="pad">
                <span><strong>Trackpad / Ratón en directo</strong><br>
                1 dedo: mover cursor · Toque: clic<br>
                2 dedos: scroll · Pellizcar (2 dedos): ampliar/reducir escala</span>
            </div>

            <div class="row">
                <button class="sec" style="flex:1" onclick="send({type:'click'})">Clic</button>
                <button class="sec" style="flex:1" onclick="send({type:'rightClick'})">Atrás</button>
                <button id="lockBtn" class="sec" style="flex:1" onclick="enablePointerLock()">Ratón PC</button>
            </div>

            <div class="row">
                <input id="kbInput" type="text" placeholder="Teclado en directo (escribe aquí para escribir en la tele)..." autocomplete="off" autocorrect="off" autocapitalize="off">
                <button class="sec" onclick="send({type:'key',code:'Backspace'})">⌫</button>
                <button onclick="send({type:'key',code:'Enter'})">↵</button>
            </div>

            <div class="grid">
                <button class="sec" onclick="act('back')">◀ Atrás</button>
                <button class="sec" onclick="act('forward')">▶ Adel.</button>
                <button class="sec" onclick="act('reload')">↻ Recargar</button>
                <button class="sec" onclick="act('home')">⌂ Inicio</button>
                <button class="sec" onclick="act('mode')">Cursor/Scroll</button>
                <button class="sec" onclick="act('toolbar')">Barra</button>
                <button class="sec" onclick="act('tabs')">Pestañas</button>
                <button class="sec" onclick="act('video')">📺 Vídeo</button>
                <button class="sec" onclick="send({type:'scroll',dx:0,dy:-450})">▲ Subir</button>
                <button class="sec" onclick="send({type:'scroll',dx:0,dy:450})">▼ Bajar</button>
                <button class="sec" onclick="send({type:'scroll',dx:0,dy:-2200})">⤒ Arriba</button>
                <button class="sec" onclick="send({type:'scroll',dx:0,dy:2200})">⤓ Abajo</button>
            </div>

            <div class="card" style="margin-bottom:12px;">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
                    <h2 style="margin:0;">Escala / Zoom de pantalla</h2>
                    <span id="zoomBadge" class="badge ok">\(currentZoomPct)%</span>
                </div>
                <div class="row" style="align-items:center;">
                    <button class="sec" onclick="stepZoom(-15)">A-</button>
                    <input id="zoomSlider" type="range" min="75" max="250" step="5" value="\(currentZoomPct)" style="flex:1;accent-color:#3b82f6;">
                    <button class="sec" onclick="stepZoom(15)">A+</button>
                </div>
                <div style="display:grid;grid-template-columns:repeat(6, 1fr);gap:6px;">
                    <button class="sec" style="padding:8px 4px;font-size:12px;" onclick="applyZoomPct(100)">100%</button>
                    <button class="sec" style="padding:8px 4px;font-size:12px;" onclick="applyZoomPct(125)">125%</button>
                    <button class="sec" style="padding:8px 4px;font-size:12px;" onclick="applyZoomPct(140)">140%</button>
                    <button class="sec" style="padding:8px 4px;font-size:12px;" onclick="applyZoomPct(160)">160%</button>
                    <button class="sec" style="padding:8px 4px;font-size:12px;" onclick="applyZoomPct(185)">185%</button>
                    <button class="sec" style="padding:8px 4px;font-size:12px;" onclick="applyZoomPct(210)">210%</button>
                </div>
            </div>

            <div class="card">
                <h2>Marcadores (\(bookmarksCount)) y Contraseñas (\(passwordsCount))</h2>
                <a class="dl" href="/marcadores.html">Descargar marcadores.html (Safari / Chrome)</a>
                <a class="dl" href="/marcadores.json">Descargar marcadores.json</a>
                <a class="dl" href="/contrasenas.csv">Descargar contrasenas.csv</a>
                <div style="margin-top:12px;">
                    <input id="importFile" type="file" accept=".html,.htm" style="width:100%;font-size:13px;">
                    <button style="width:100%;margin-top:8px;" onclick="importBookmarks()">Importar marcadores (.html) al Apple TV</button>
                    <div id="importResult" class="hint"></div>
                </div>
            </div>

            <script>
                let ws = null;
                let wsAlive = false;
                let reconnectTimer = null;
                let heartbeatTimer = null;
                let pongDeadlineTimer = null;
                let wakeLock = null;
                let lastTouches = [];
                let tapStart = 0;
                let tapMoved = false;
                let pinchStartDist = 0;
                let pinchStartZoom = 1.0;
                let pinchActive = false;
                let lastPinchSentAt = 0;
                let lastPinchPct = 0;
                let lastMouse = null;
                let moveBuf = { dx: 0, dy: 0 };
                let rafScheduled = false;

                async function requestWakeLock() {
                    try {
                        if ('wakeLock' in navigator && !wakeLock && document.visibilityState === 'visible') {
                            wakeLock = await navigator.wakeLock.request('screen');
                            wakeLock.addEventListener('release', () => { wakeLock = null; });
                        }
                    } catch (e) {}
                }

                function stopHeartbeat() {
                    if (heartbeatTimer) { clearInterval(heartbeatTimer); heartbeatTimer = null; }
                    if (pongDeadlineTimer) { clearTimeout(pongDeadlineTimer); pongDeadlineTimer = null; }
                }

                function startHeartbeat() {
                    stopHeartbeat();
                    heartbeatTimer = setInterval(() => {
                        if (document.visibilityState !== 'visible') return;
                        if (!ws || ws.readyState !== 1) {
                            forceReconnectWS();
                            return;
                        }
                        try {
                            ws.send('{"type":"ping"}');
                            if (pongDeadlineTimer) clearTimeout(pongDeadlineTimer);
                            pongDeadlineTimer = setTimeout(() => {
                                wsAlive = false;
                                forceReconnectWS();
                            }, 2500);
                        } catch (e) {
                            wsAlive = false;
                            forceReconnectWS();
                        }
                    }, 4000);
                }

                function forceReconnectWS() {
                    if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
                    stopHeartbeat();
                    wsAlive = false;
                    if (ws) {
                        const old = ws;
                        ws = null;
                        old.onopen = null; old.onclose = null; old.onmessage = null; old.onerror = null;
                        try { old.close(); } catch (e) {}
                    }
                    connectWS();
                }

                function connectWS() {
                    if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
                    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
                    const badge = document.getElementById('status');
                    badge.textContent = 'Conectando...';
                    badge.className = 'badge';

                    const sock = new WebSocket(proto + '//' + location.host + '/ws');
                    ws = sock;
                    sock.onopen = () => {
                        if (ws !== sock) return;
                        wsAlive = true;
                        badge.textContent = 'Conectado';
                        badge.className = 'badge ok';
                        startHeartbeat();
                    };
                    sock.onmessage = (ev) => {
                        if (ws !== sock) return;
                        wsAlive = true;
                        if (pongDeadlineTimer) { clearTimeout(pongDeadlineTimer); pongDeadlineTimer = null; }
                        try {
                            const msg = JSON.parse(ev.data);
                            if (msg && msg.type === 'pong') {
                                badge.textContent = 'Conectado';
                                badge.className = 'badge ok';
                            }
                        } catch (e) {}
                    };
                    sock.onerror = () => {
                        if (ws !== sock) return;
                        wsAlive = false;
                    };
                    sock.onclose = () => {
                        if (ws !== sock) return;
                        wsAlive = false;
                        stopHeartbeat();
                        badge.textContent = 'Reconectando...';
                        badge.className = 'badge';
                        if (!reconnectTimer) {
                            reconnectTimer = setTimeout(connectWS, 700);
                        }
                    };
                }
                connectWS();

                function handleResume() {
                    if (document.visibilityState === 'hidden') return;
                    requestWakeLock();
                    if (!ws || ws.readyState !== 1 || !wsAlive) {
                        forceReconnectWS();
                    } else {
                        try {
                            ws.send('{"type":"ping"}');
                            if (pongDeadlineTimer) clearTimeout(pongDeadlineTimer);
                            pongDeadlineTimer = setTimeout(() => {
                                wsAlive = false;
                                forceReconnectWS();
                            }, 1200);
                        } catch (e) {
                            forceReconnectWS();
                        }
                    }
                }
                document.addEventListener('visibilitychange', handleResume);
                window.addEventListener('pageshow', handleResume);
                window.addEventListener('focus', handleResume);
                window.addEventListener('online', handleResume);

                function send(obj) {
                    if (ws && ws.readyState === 1 && wsAlive) {
                        try {
                            ws.send(JSON.stringify(obj));
                            return;
                        } catch (e) {
                            wsAlive = false;
                            forceReconnectWS();
                        }
                    }
                    fetch('/cmd', { method: 'POST', body: JSON.stringify(obj), keepalive: true })
                        .then(() => { if (!ws || ws.readyState !== 1) forceReconnectWS(); })
                        .catch(() => {});
                }
                function act(name) { send({ type: 'action', name }); }

                const zoomSlider = document.getElementById('zoomSlider');
                const zoomBadge = document.getElementById('zoomBadge');
                function applyZoomPct(pct) {
                    const clamped = Math.max(75, Math.min(250, Math.round(pct)));
                    zoomSlider.value = clamped;
                    zoomBadge.textContent = clamped + '%';
                    send({ type: 'zoom', value: clamped / 100.0 });
                }
                function stepZoom(delta) {
                    applyZoomPct((parseInt(zoomSlider.value, 10) || 100) + delta);
                }
                zoomSlider.addEventListener('input', () => {
                    const val = parseInt(zoomSlider.value, 10) || 100;
                    zoomBadge.textContent = val + '%';
                    send({ type: 'zoom', value: val / 100.0 });
                });

                function queueMove(dx, dy) {
                    moveBuf.dx += dx; moveBuf.dy += dy;
                    if (!rafScheduled) {
                        rafScheduled = true;
                        requestAnimationFrame(() => {
                            rafScheduled = false;
                            if (Math.abs(moveBuf.dx) > 0.2 || Math.abs(moveBuf.dy) > 0.2) {
                                send({ type: 'move', dx: moveBuf.dx, dy: moveBuf.dy });
                                moveBuf.dx = 0; moveBuf.dy = 0;
                            }
                        });
                    }
                }

                const pad = document.getElementById('pad');
                function touchDist(a, b) {
                    return Math.hypot(b.clientX - a.clientX, b.clientY - a.clientY);
                }

                pad.addEventListener('gesturestart', e => e.preventDefault(), { passive: false });
                pad.addEventListener('gesturechange', e => e.preventDefault(), { passive: false });
                pad.addEventListener('gestureend', e => e.preventDefault(), { passive: false });

                pad.addEventListener('touchstart', e => {
                    e.preventDefault();
                    lastTouches = Array.from(e.touches).map(t => ({ x: t.clientX, y: t.clientY }));
                    if (e.touches.length === 1) {
                        tapStart = Date.now();
                        tapMoved = false;
                        pinchActive = false;
                        pinchStartDist = 0;
                    } else if (e.touches.length >= 2) {
                        tapMoved = true;
                        pinchStartDist = touchDist(e.touches[0], e.touches[1]);
                        pinchStartZoom = (parseInt(zoomSlider.value, 10) || 100) / 100.0;
                        pinchActive = false;
                        lastPinchPct = parseInt(zoomSlider.value, 10) || 100;
                    }
                }, { passive: false });

                pad.addEventListener('touchmove', e => {
                    e.preventDefault();
                    const cur = Array.from(e.touches);
                    if (cur.length === 1 && lastTouches.length === 1 && !pinchActive) {
                        const dx = (cur[0].clientX - lastTouches[0].x) * 2.2;
                        const dy = (cur[0].clientY - lastTouches[0].y) * 2.2;
                        if (Math.hypot(dx, dy) > 3) tapMoved = true;
                        queueMove(dx, dy);
                    } else if (cur.length >= 2 && lastTouches.length >= 2) {
                        tapMoved = true;
                        const curDist = touchDist(cur[0], cur[1]);
                        if (pinchStartDist <= 0) {
                            pinchStartDist = curDist;
                            pinchStartZoom = (parseInt(zoomSlider.value, 10) || 100) / 100.0;
                        }
                        if (!pinchActive && Math.abs(curDist - pinchStartDist) > 16) {
                            pinchActive = true;
                        }
                        if (pinchActive) {
                            const scale = curDist / Math.max(24, pinchStartDist);
                            const nextPct = Math.max(75, Math.min(250, Math.round((pinchStartZoom * scale * 100) / 5) * 5));
                            const now = Date.now();
                            if (nextPct !== lastPinchPct && (now - lastPinchSentAt >= 55 || Math.abs(nextPct - lastPinchPct) >= 5)) {
                                lastPinchSentAt = now;
                                lastPinchPct = nextPct;
                                applyZoomPct(nextPct);
                            }
                        } else {
                            const dy = ((cur[0].clientY - lastTouches[0].y) + (cur[1].clientY - lastTouches[1].y)) * 0.5;
                            const dx = ((cur[0].clientX - lastTouches[0].x) + (cur[1].clientX - lastTouches[1].x)) * 0.5;
                            send({ type: 'scroll', dx: -dx * 2.4, dy: -dy * 2.4 });
                        }
                    }
                    lastTouches = cur.map(t => ({ x: t.clientX, y: t.clientY }));
                }, { passive: false });

                pad.addEventListener('touchend', e => {
                    e.preventDefault();
                    if (!tapMoved && Date.now() - tapStart < 280 && e.touches.length === 0) {
                        send({ type: 'click' });
                    }
                    if (e.touches.length < 2) {
                        pinchActive = false;
                        pinchStartDist = 0;
                    }
                    lastTouches = Array.from(e.touches).map(t => ({ x: t.clientX, y: t.clientY }));
                }, { passive: false });

                function enablePointerLock() {
                    if (pad.requestPointerLock) { pad.requestPointerLock(); }
                }

                pad.addEventListener('mousemove', e => {
                    if (document.pointerLockElement === pad) {
                        queueMove(e.movementX * 1.4, e.movementY * 1.4);
                    } else if (e.buttons === 1) {
                        if (lastMouse) {
                            queueMove((e.clientX - lastMouse.x) * 1.8, (e.clientY - lastMouse.y) * 1.8);
                            tapMoved = true;
                        }
                        lastMouse = { x: e.clientX, y: e.clientY };
                    }
                });
                pad.addEventListener('mousedown', e => {
                    if (document.pointerLockElement === pad) {
                        if (e.button === 0) send({ type: 'click' });
                        else if (e.button === 2) send({ type: 'rightClick' });
                    } else {
                        lastMouse = { x: e.clientX, y: e.clientY };
                        tapMoved = false;
                    }
                });
                pad.addEventListener('mouseup', () => {
                    if (document.pointerLockElement !== pad && !tapMoved) send({ type: 'click' });
                    lastMouse = null;
                });
                pad.addEventListener('contextmenu', e => e.preventDefault());
                pad.addEventListener('wheel', e => {
                    e.preventDefault();
                    if (e.ctrlKey) {
                        const curPct = parseInt(zoomSlider.value, 10) || 100;
                        applyZoomPct(curPct - e.deltaY * 1.2);
                    } else {
                        send({ type: 'scroll', dx: e.deltaX, dy: e.deltaY });
                    }
                }, { passive: false });

                const urlInput = document.getElementById('urlInput');
                urlInput.addEventListener('keydown', e => { if (e.key === 'Enter') sendURL(); });
                function sendURL() {
                    const v = urlInput.value.trim();
                    if (!v) return;
                    send({ type: 'url', value: v });
                    urlInput.value = '';
                }

                const kbInput = document.getElementById('kbInput');
                let kbComposing = false;
                kbInput.addEventListener('focus', () => {
                    requestWakeLock();
                    if (!ws || ws.readyState !== 1 || !wsAlive) forceReconnectWS();
                });
                kbInput.addEventListener('compositionstart', () => { kbComposing = true; });
                kbInput.addEventListener('compositionend', () => {
                    kbComposing = false;
                    const v = kbInput.value;
                    if (v) {
                        send({ type: 'text', value: v });
                        kbInput.value = '';
                    }
                });
                kbInput.addEventListener('input', e => {
                    if (e && e.inputType === 'deleteContentBackward' && kbInput.value === '') {
                        send({ type: 'key', code: 'Backspace' });
                        return;
                    }
                    if (kbComposing) return;
                    const v = kbInput.value;
                    if (v) {
                        send({ type: 'text', value: v });
                        kbInput.value = '';
                    }
                });
                kbInput.addEventListener('keydown', e => {
                    if (e.key === 'Backspace' && kbInput.value === '') {
                        send({ type: 'key', code: 'Backspace' });
                    } else if (e.key === 'Enter') {
                        e.preventDefault();
                        if (kbInput.value) {
                            send({ type: 'text', value: kbInput.value });
                            kbInput.value = '';
                        }
                        send({ type: 'key', code: 'Enter' });
                    } else if (e.key === 'Tab') {
                        e.preventDefault();
                        send({ type: 'key', code: 'Tab' });
                    } else if (e.key === 'Escape') {
                        send({ type: 'key', code: 'Escape' });
                    }
                });

                async function importBookmarks() {
                    const file = document.getElementById('importFile').files[0];
                    const resEl = document.getElementById('importResult');
                    if (!file) { resEl.textContent = 'Selecciona primero un archivo .html'; return; }
                    const text = await file.text();
                    const res = await fetch('/import', { method: 'POST', body: text });
                    const data = await res.json();
                    resEl.textContent = 'Marcadores importados: ' + (data.added || 0);
                }
            </script>
        </body>
        </html>
        """
    }

    static func localIPAddress() -> String? {
        var fallback: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let addr = interface.ifa_addr else { continue }
            if addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "lo0" { continue }
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                let ip = String(cString: hostname)
                if ip.hasPrefix("127.") || ip.hasPrefix("169.254.") { continue }
                if name == "en0" || name == "en1" {
                    return ip
                }
                if name.hasPrefix("en") && fallback == nil {
                    fallback = ip
                }
            }
        }
        return fallback
    }
}
