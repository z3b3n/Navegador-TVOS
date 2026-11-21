# Platanet para Apple TV 4K (tvOS) · v2.1

Navegador web avanzado para **Apple TV 4K (tvOS 15+)** diseñado para acercar la experiencia de **Safari** al televisor: barra superior automática al llegar arriba (y ocultación automática tras inactividad), zoom nativo centrado (`140%` por defecto para TV 55"), Página de Inicio con gestión completa de accesos directos, pestañas múltiples, **WebApps en pantalla completa**, soporte de **teclado Bluetooth**, **control remoto desde iPhone/PC con ratón, trackpad y pellizco**, reproductor de vídeo nativo y bloqueador de anuncios.

---

## Novedades principales (v2.1)

* **Interfaz estilo Safari inteligente y despejada:**
  * Sin barra fija estorbando durante la navegación: al llevar el puntero al borde superior (estés en la parte que estés de la página, sin tener que subir el scroll hasta arriba) se despliega al instante la barra grande de Safari (`◀`, `▶`, `⌂ Inicio`, búsqueda/URL con dominio SSL, `A-` / `%` / `A+`, `↻/✕`, `★`, `📺 Vídeo`, `↕ Scroll` / `🎯 Cursor`, `❏ Pestañas`, `⋯ Menú`, `Listo`), y desaparece automáticamente tras ~6,5 s sin usarla (o pulsando `↓`, `Menú` o `Listo`).
  * **Zoom nativo siempre centrado (75% – 250%, `140%` por defecto para TV 55"):** escala todo el viewport manteniendo cualquier página centrada sin descuadres laterales.
  * **Scroll progresivo y suave:** al acercar el puntero al borde inferior/superior la página avanza progresivamente con suavidad a 60 fps para parar en el punto exacto sin saltos bruscos.
  * **Página de Inicio (`⌂`):** añade accesos directos de la página actual o por URL, edítalos, reordénalos o elimínalos fácilmente desde **+ Añadir acceso** y **Editar accesos**.
  * **Arranque directo en Google** (o en tu **WebApp automática** si fijas una) + barra de progreso fina azul.
* **Control de cursor y scroll:**
  * **Play/Pausa (toque corto)** alterna `Modo Cursor ↔ Modo Scroll` de forma fiable.
  * **Mantener pulsado Seleccionar / OK (≥ 0,6 s)** abre el menú rápido del mando desde cualquier punto de la página.
  * **Pulsación larga en Play/Pausa o Menú (≥ 0,45 s)** abre o cierra la barra Safari **en cualquier momento**, aunque tengas historial abierto.
  * **Cursor adaptativo con `:hover` en tiempo real**, soporte nativo de `<select>` desplegables, `<iframe>`s / Shadow DOM y clic estabilizado al soltar.
* **WebApps (Modo App en pantalla completa):**
  * Convierte cualquier web en una **WebApp** desde `⋯ → Guardar como WebApp` (sin barras, con su propio Zoom, User-Agent y AdBlock, y opción de **auto-abrir al arrancar Platanet**).
* **Pestañas y Motor WebKit robusto:**
  * **Gestor de pestañas (`❏`)** con soporte real de `target="_blank"` y pop-ups OAuth (Google, Microsoft, GitHub) conservando `window.opener`.
  * Observación KVO en tiempo real de URL, título y progreso para **SPAs modernas**, diálogos JS, página de error con *Reintentar*, selector de **User-Agent (Mac / iPad / iPhone)**, limpieza de caché/cookies y regla de bloqueo nativo (`WKContentRuleList`).
  * **Reproductor de vídeo TV (`AVPlayerViewController`)** para reproducir flujos `<video>` MP4 / HLS a pantalla completa con el Siri Remote.
* **Teclado Bluetooth y Ratón / Trackpad Remoto (PWA + WebSocket):**
  * **Teclado Bluetooth:** escritura directa en cualquier campo web enfocado + atajos Safari (`⌘L`, `⌘T`, `⌘W`, `⌘R`, `⌘[`, `⌘]`, `⌘+`/`⌘-`/`⌘0`, `Esc`, `Espacio`, `RePág`/`AvPág`).
  * **Ratón, Trackpad y Gestos desde iPhone/PC:** abre `⋯ → Control Remoto QR` y escanea el QR desde tu **iPhone, iPad, Mac o PC** (con reconexión automática, Wake Lock, teclado en directo, pellizco de 2 dedos para zoom, y exportación/importación de marcadores HTML/JSON y contraseñas CSV). *(También incluye soporte de `GCMouse` para dispositivos HID compatibles.)*

---

## Controles

### Siri Remote / Mando de TV compatible / Mando iPhone
* **Subir el puntero al borde superior (desde cualquier parte de la web):** Despliega al instante la barra completa de Safari sin mover ni subir la página; desaparece sola tras ~6,5 s sin usarla (o al pulsar `↓`, `Menú` o `Listo`).
* **Mantener pulsado Seleccionar / OK (≥ 0,6 s):** Abre el **Menú rápido del mando** desde cualquier punto de la página (Buscar/URL, Barra completa, Escala/Zoom, Cursor/Scroll, Inicio, Pestañas, Control Remoto iPhone).
* **Deslizar en el touchpad o cruceta (D-Pad):** Mueve el cursor virtual (en *Modo Cursor*, bajando suavemente al acercarlo al borde inferior) o hace scroll libre arriba/abajo (en *Modo Scroll*, accesible con **Play/Pausa** o el botón **`↕ Scroll`** de la barra).
* **Play / Pausa (toque corto):** Alterna entre **Modo Cursor** y **Modo Scroll**.
* **Menú (toque corto):** Atrás en el historial (o cierra la pestaña secundaria); en la pantalla raíz sin historial sale al menú principal de Apple TV.
* **Play / Pausa (pulsación larga ≥ 0,45 s):** Abre o cierra manualmente la **barra Safari** desde cualquier página o WebApp.

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

> **Nota técnica:** Apple no incluye `WebKit` en el SDK público de tvOS para la App Store, por lo que Platanet carga `WebKit` dinámicamente en tiempo de ejecución para funcionar mediante sideloading (`.ipa`). Asimismo, tvOS restringe el emparejamiento de ratones Bluetooth genéricos en Ajustes del sistema, razón por la cual Platanet incorpora su propia WebApp local de ratón/trackpad por Wi-Fi además del hook `GCMouse`.
