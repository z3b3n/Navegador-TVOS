import Foundation
import Network
import Darwin

final class LocalExportServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 8080

    func start(onReady: @escaping (String?) -> Void) {
        stop()
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: 8080)!)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
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
                    DispatchQueue.main.async { onReady(nil) }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            onReady(nil)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.components(separatedBy: " ")
            let path = parts.count >= 2 ? parts[1] : "/"

            let response: (status: String, contentType: String, filename: String?, body: String)
            switch path {
            case "/marcadores.html":
                response = ("200 OK", "text/html; charset=utf-8", "marcadores.html", BrowserStore.shared.exportBookmarksHTML())
            case "/marcadores.json":
                response = ("200 OK", "application/json; charset=utf-8", "marcadores.json", BrowserStore.shared.exportBookmarksJSON())
            case "/contrasenas.csv":
                response = ("200 OK", "text/csv; charset=utf-8", "contrasenas.csv", BrowserStore.shared.exportCredentialsCSV())
            default:
                response = ("200 OK", "text/html; charset=utf-8", nil, self.indexHTML())
            }

            var headers = "HTTP/1.1 \(response.status)\r\n"
            headers += "Content-Type: \(response.contentType)\r\n"
            if let filename = response.filename {
                headers += "Content-Disposition: attachment; filename=\"\(filename)\"\r\n"
            }
            let bodyData = response.body.data(using: .utf8) ?? Data()
            headers += "Content-Length: \(bodyData.count)\r\n"
            headers += "Connection: close\r\n\r\n"

            var payload = headers.data(using: .utf8) ?? Data()
            payload.append(bodyData)

            connection.send(content: payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func indexHTML() -> String {
        let bmCount = BrowserStore.shared.bookmarks.count
        let pwCount = BrowserStore.shared.credentials.count
        return """
        <!DOCTYPE html>
        <html lang="es">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>TVBrowser Export</title>
            <style>
                body { font-family: -apple-system, sans-serif; background: #0f172a; color: #f8fafc; padding: 32px; max-width: 560px; margin: auto; }
                h1 { font-size: 26px; margin-bottom: 8px; }
                p { color: #94a3b8; line-height: 1.5; }
                .card { background: #1e293b; border-radius: 16px; padding: 20px; margin-top: 20px; }
                a.btn { display: block; text-decoration: none; background: #2563eb; color: #fff; font-weight: 600; padding: 14px 18px; border-radius: 12px; margin-top: 12px; text-align: center; }
                a.btn.sec { background: #334155; }
            </style>
        </head>
        <body>
            <h1>TVBrowser · Exportación</h1>
            <p>Descarga tus marcadores y contraseñas guardadas desde tu Apple TV 4K.</p>
            <div class="card">
                <strong>Marcadores (\(bmCount))</strong>
                <a class="btn" href="/marcadores.html">Descargar marcadores.html (Chrome / Safari)</a>
                <a class="btn sec" href="/marcadores.json">Descargar marcadores.json</a>
            </div>
            <div class="card">
                <strong>Contraseñas guardadas (\(pwCount))</strong>
                <a class="btn" href="/contrasenas.csv">Descargar contrasenas.csv</a>
            </div>
        </body>
        </html>
        """
    }

    static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }
}
