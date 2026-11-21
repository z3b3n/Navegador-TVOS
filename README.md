# TVBrowser para Apple TV 4K (tvOS) · Safari Edition (v2.0)

Navegador web avanzado para **Apple TV 4K (tvOS 15+)** diseñado para acercar la experiencia de **Safari** al televisor: barra compacta, Página de Inicio nativa, pestañas múltiples, **WebApps en pantalla completa**, soporte de **teclado Bluetooth**, **control remoto desde móvil/PC con ratón y trackpad en tiempo real**, reproductor de vídeo nativo y bloqueador de anuncios.

---

## Novedades principales (v2.0)

* **Interfaz estilo Safari sin estorbos:**
  * Barra superior compacta (`◀`, `▶`, `⌂ Inicio`, barra de búsqueda/URL con dominio SSL, `↻/✕`, `★`, `📺 Vídeo`, `❏ Pestañas`, `⋯ Opciones`) y barra de progreso fina azul.
  * **Arranque directo en Google** (o en tu **WebApp automática** si fijas una) + **Página de Inicio nativa (`⌂`)** navegable con la cruceta del mando con WebApps, Favoritos y Visitados recientemente.
  * Eliminada la barra fija inferior que tapaba subtítulos y reproductores (sustituida por avisos breves automáticos de 1,5 s y vista previa de enlace abajo a la izquierda).
* **Control de cursor y scroll reparado de raíz:**
  * **Play/Pausa (toque corto)** alterna `Modo Cursor ↔ Modo Scroll` de forma fiable (corregido el antiguo doble disparo).
  * **Pulsación larga en Play/Pausa o Menú (≥ 0,45 s)** abre o cierra la barra Safari **en cualquier momento**, aunque tengas historial abierto.
  * **Scroll con inercia suave** y soporte prioritario de **contenedores internos (`overflow: auto/scroll`)**.
  * **Cursor adaptativo con `:hover` en tiempo real** (cambia al pasar sobre enlaces o cajas de texto y muestra la URL destino).
  * **Soporte nativo de `<select>` desplegables** (menú nativo de tvOS), soporte recursivo dentro de **`<iframe>`s** del mismo origen y clic estabilizado al soltar.
* **WebApps (Modo App en pantalla completa):**
  * Convierte cualquier web en una **WebApp** desde `⋯ → Guardar como WebApp` (sin barras, con su propio Zoom, User-Agent y AdBlock, y opción de **auto-abrir al arrancar TVBrowser**).
* **Pestañas y Motor WebKit robusto:**
  * **Gestor de pestañas (`❏`)** con soporte real de `target="_blank"` y pop-ups OAuth (Google, Microsoft, GitHub) conservando `window.opener`.
  * Observación KVO en tiempo real de URL, título y progreso para **SPAs modernas** (YouTube, Google, GitHub, etc.), diálogos JS (`alert`, `confirm`, `prompt`), página de error con botón *Reintentar*, selector de **User-Agent (Mac / iPad / iPhone)**, limpieza de caché/cookies y regla de bloqueo nativo (`WKContentRuleList`).
  * **Reproductor de vídeo TV (`AVPlayerViewController`)** para reproducir flujos `<video>` MP4 / HLS a pantalla completa con el Siri Remote.
* **Teclado Bluetooth y Ratón / Trackpad Remoto (PWA + WebSocket):**
  * **Teclado Bluetooth:** escritura directa en cualquier campo web enfocado sin popup modal + atajos Safari (`⌘L`, `⌘T`, `⌘W`, `⌘R`, `⌘[`, `⌘]`, `⌘+`/`⌘-`/`⌘0`, `Esc`, `Espacio`, `RePág`/`AvPág`).
  * **Ratón y Trackpad Remoto en tu red Wi-Fi:** abre `⋯ → Control Remoto (Ratón/Teclado/QR)` y escanea el código QR desde tu **iPhone, iPad, Mac o PC** (instalable como WebApp PWA). Incluye trackpad táctil, **Modo Ratón PC (Pointer Lock)**, scroll con rueda o dos dedos, teclado en directo y exportación/importación de marcadores HTML/JSON y contraseñas CSV. *(También incluye soporte de `GCMouse` para dispositivos HID compatibles.)*

---

## Controles

### Siri Remote / Mando de TV compatible / Mando iPhone
* **Barra rápida superior siempre accesible (`◀` · `🔍 Buscar/URL` · `🎯 Cursor/Scroll` · `100%` · `☰ Menú`):** Mueve el puntero arriba del todo y pulsa **OK/Seleccionar** para abrir la barra de direcciones, cambiar de modo, ajustar la escala del televisor o abrir la barra completa de Safari sin memorizar atajos.
* **Mantener pulsado Seleccionar / OK (≥ 0,6 s):** Abre el **Menú rápido del mando** desde cualquier punto de la página (Buscar/URL, Barra completa, Escala/Zoom, Cursor/Scroll, Inicio, Pestañas, Control Remoto iPhone).
* **Deslizar en el touchpad o cruceta (D-Pad):** Mueve el cursor virtual (en *Modo Cursor*) o hace scroll con inercia (en *Modo Scroll*). Al llevar el puntero al borde inferior/superior de la pantalla hace scroll automático.
* **Play / Pausa (toque corto):** Alterna entre **Modo Cursor** y **Modo Scroll**.
* **Menú (toque corto):** Atrás en el historial; si no hay historial atrás, abre/cierra la barra superior.
* **Play / Pausa o Menú (pulsación larga ≥ 0,45 s):** Abre o cierra la **barra Safari** desde cualquier página o WebApp.

### Teclado Bluetooth físico
* **Escribir directamente** cuando un campo de texto web está enfocado (incluye `Backspace`, `Enter`, `Tab`, `Esc`).
* **Atajos estilo Safari:**
  * `⌘L` Buscar / URL · `⌘T` Nueva pestaña · `⌘W` Cerrar pestaña · `⌘R` Recargar
  * `⌘[` / `⌘]` Atrás / Adelante · `⌘+` / `⌘-` / `⌘0` Zoom · `Espacio` / `RePág` / `AvPág` Scroll

### Mandos de consola (Xbox / PlayStation / MFi / Bluetooth)
* **Stick izquierdo:** Cursor virtual · **Stick derecho:** Scroll suave
* **A / Cruz (`✕`):** Clic · **B / Círculo (`◯`):** Atrás
* **X / Cuadrado (`□`):** Mostrar / ocultar barra Safari · **Y / Triángulo (`△`):** Cambiar Cursor/Scroll
* **L1/LB y R1/RB:** Atrás / Adelante

### Ratón / Trackpad / Gestos desde iPhone o PC (PWA Local)
1. Abre `⋯ → Control Remoto QR` (o mantén **OK** → *Control Remoto desde iPhone*) en el Apple TV.
2. Escanea el QR o entra en `http://<IP-APPLE-TV>:8080` desde Safari en tu iPhone o tu ordenador.
3. Pulsa *"Seguir navegando (dejar activo)"* en la tele:
   * **1 dedo:** mover puntero · **Toque:** clic.
   * **2 dedos (deslizar):** scroll suave.
   * **2 dedos (pellizcar):** ampliar o reducir la escala en directo en la tele (también disponible mediante deslizador y presets `100%–210%`).
   * **Modo Ratón PC (Pointer Lock):** control directo con ratón y rueda desde ordenador.

---

## Cómo generar e instalar el `.ipa` (sin Mac)

1. Descarga el `.ipa` directamente desde la sección **[Releases](../../releases)** de este repositorio (o ejecuta el workflow **Build tvOS IPA** en la pestaña **Actions**).
2. Descarga **[Sideloadly](https://sideloadly.io/)** en tu PC (Windows o Mac).
3. Empareja tu Apple TV 4K (*Ajustes → Mandos y dispositivos → App Remote y dispositivos*).
4. Arrastra `TVBrowser-tvOS.ipa` a Sideloadly, introduce tu Apple ID y pulsa **Start**.

> **Nota técnica:** Apple no incluye `WebKit` en el SDK público de tvOS para la App Store, por lo que TVBrowser carga `WebKit` dinámicamente en tiempo de ejecución para funcionar mediante sideloading (`.ipa`). Asimismo, tvOS restringe el emparejamiento de ratones Bluetooth genéricos en Ajustes del sistema, razón por la cual TVBrowser incorpora su propia WebApp local de ratón/trackpad por Wi-Fi además del hook `GCMouse`.
