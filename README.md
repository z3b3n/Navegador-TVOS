# Platanet para Apple TV 4K (tvOS) · v2.3

Navegador web avanzado para **Apple TV 4K (tvOS 15+)** diseñado para pantalla grande de salón (TV 4K 55"): arranque directo en la **Página de Inicio (`⌂`)** con accesos directos y favicons, puntero estable y predecible con parada inmediata al soltar, HUD superior con **Play/Pausa** o **OK largo**, zoom centrado real (`140%` por defecto, `100%–220%`), navegación estricta con Menú/Focus Engine sin callejones, WebApps en pantalla completa, teclado Bluetooth y remoto iPhone PWA a prueba de bloqueos.

---

## Novedades principales (v2.3)

* **Arranque directo en Página de Inicio (`Platanet · Inicio`):**
  * Abre directamente tus accesos directos favoritos, WebApps y buscador con el mando desde el primer segundo (salvo si fijas una WebApp con inicio automático).
* **Barra superior práctica y sin bloqueos:**
  * Pulsa **Play/Pausa (toque corto)** o mantén **OK (0,50 s)** desde cualquier parte de una web para abrir/cerrar la barra (`◀`, `▶`, `⌂ Inicio`, búsqueda/URL SSL, `A-` / `%` / `A+`, `↻/✕`, `☆ +Inicio`, `📺 Vídeo`, `↕ Scroll`, `❏ Pestañas`, `⋯ Menú`, `Listo`) sin tener que subir el cursor hasta arriba ni bloquearlo.
  * Auto-ocultación tras **5 segundos** de inactividad (o al pulsar `↓`, deslizar abajo en el touchpad, `Menú`, `Play/Pausa` o `Listo`).
* **Puntero estable y predecible (parada inmediata al soltar):**
  * Cruceta con paso de precisión (`9 pt`) y crucero suave controlado (máx. `640 pt/s`, parada instantánea al soltar), más seguimiento lineal 1:1 en touchpad sin saltos erráticos.
  * Desplazamiento progresivo suave al mover el puntero en el borde superior/inferior sin atrapar jamás el cursor al cambiar de dirección.
  * **Play/Pausa mantenido (0,45 s)** o el botón **`↕ Scroll`** alternan entre *Modo Puntero* y *Modo Scroll* con badge visual discreto.
* **Zoom centrado real (`100%–220%`, `140%` por defecto) y coordenadas 1:1:**
  * Ancho entero alineado con `bounds` + `CGAffineTransform` centrado y recorte de overflow horizontal fantasma.
  * Mapeo geométrico exacto sobre `WKWebView` en `elementFromPoint`, `:hover` y clics (Shadow DOM, `iframe`s con escala/bordes y puente `postMessage` también en hover).
* **Navegación nativa estricta con `Menú` y Focus Engine blindado:**
  * `Menú` cierra modal/barra abierta → retrocede historial → cierra pestaña secundaria → sale limpiamente a Apple TV en la raíz sin historial.
  * Rescate automático de foco al deshabilitar botones o vaciar listas/secciones.
* **Página de Inicio (`⌂`) con favicons y edición completa:**
  * Tarjetas estilo Apple TV con favicon en caché y color de dominio; botón **`☆ +Inicio`** directo en la barra y reordenación (`⬅`, `➡`, `⬆`, editar, eliminar) desde Inicio.
* **WebApps (Modo App en pantalla completa):**
  * Convierte cualquier web en una **WebApp** desde `⋯ → Guardar como WebApp` (sin barras, con su propio Zoom, User-Agent y AdBlock, y opción de **auto-abrir al arrancar Platanet**).
* **Pestañas y Motor WebKit robusto:**
  * **Gestor de pestañas (`❏`)** con soporte real de `target="_blank"` y pop-ups OAuth conservando `window.opener`.
  * Observación KVO en tiempo real de URL, título y progreso para **SPAs modernas**, diálogos JS, página de error con *Reintentar*, selector de **User-Agent (Mac / iPad / iPhone)**, limpieza de caché/cookies y regla de bloqueo nativo (`WKContentRuleList`).
  * **Reproductor de vídeo TV (`AVPlayerViewController`)** para `<video>` MP4/HLS.
* **Teclado Bluetooth y Ratón / Trackpad Remoto (PWA + WebSocket):**
  * **Ratón, Trackpad y Gestos desde iPhone/PC:** sonda rápida al desbloquear de pantalla, **Wake Lock** reactivado en cada toque, sincronización de estado (`zoom` / `modo`) y **cola de reintento HTTP `/cmd` con backoff exponencial** si el WebSocket duerme tras bloquear el iPhone.

---

## Controles

### Siri Remote / Mando de TV compatible / Mando iPhone
* **Play / Pausa (toque corto) o mantener OK (0,5 s):** Abre o cierra al instante el **HUD superior** desde cualquier posición de la página; se oculta solo tras **5 s** sin usarlo (o pulsando `↓`, deslizando abajo, `Menú` o `Listo`).
* **Play / Pausa (pulsación larga 0,45 s) o botón `↕ Scroll` en barra:** Alterna entre **Modo Puntero** y **Modo Scroll**.
* **Touchpad o cruceta (D-Pad):** Mueve el puntero de forma estable y se detiene al instante al soltar; en los bordes superior/inferior desplaza suavemente la página solo mientras sigues avanzando hacia el borde.
* **Menú / Atrás (regla estricta):** Cierra barra/modal → retrocede en el historial → cierra pestaña secundaria → sale a Apple TV cuando estás en la raíz sin historial.

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
