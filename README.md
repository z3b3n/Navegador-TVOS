# TVBrowser para Apple TV 4K (tvOS)

Navegador web para Apple TV 4K con cursor virtual, soporte para Siri Remote y mandos de consola/Bluetooth, barra de direcciones, marcadores, historial y bloqueador básico de anuncios y pop-ups.

## Controles

### Siri Remote / Mando Apple TV / Mando IR
- **Deslizar en el touchpad o usar la cruceta (D-Pad):** Mueve el cursor virtual (en modo *Cursor*) o hace scroll (en modo *Scroll*).
- **Botón central (Seleccionar):** Hace clic en el elemento bajo el cursor. Si es un campo de texto, abre el teclado nativo de tvOS (compatible con dictado y teclado del iPhone).
- **Play / Pausa:** Alterna entre **Modo Cursor** y **Modo Scroll**.
- **Menú / Atrás:** Vuelve a la página anterior. Si estás en la primera página o quieres abrir la barra superior, pulsa **Menú** para mostrar/ocultar la barra de herramientas.

### Mandos de consola (Xbox / PlayStation / MFi / Bluetooth)
- **Stick izquierdo:** Mueve el cursor virtual.
- **Stick derecho:** Scroll suave de la página.
- **A / Cruz (✕):** Clic.
- **B / Círculo (◯):** Atrás.
- **X / Cuadrado (□):** Mostrar / ocultar barra de herramientas.
- **Y / Triángulo (△):** Cambiar entre modo Cursor y modo Scroll.
- **L1/LB y R1/RB:** Atrás / Adelante en el historial.

## Cómo generar el archivo `.ipa` gratis (sin Mac)

1. Crea un repositorio en **GitHub** y sube esta carpeta (`tvos-browser`).
2. Ve a la pestaña **Actions** de tu repositorio en GitHub.
3. Ejecuta el workflow **Build tvOS IPA** (se lanza automáticamente al hacer `push`, o manualmente con *Run workflow*).
4. Al terminar (~2 minutos), descarga el artefacto **`TVBrowser-tvOS-IPA`**, que contiene **`TVBrowser-tvOS.ipa`**.

## Cómo instalar el `.ipa` en tu Apple TV 4K

1. Descarga **[Sideloadly](https://sideloadly.io/)** en tu PC (Windows o Mac).
2. Empareja tu Apple TV 4K (en *Ajustes → Mandos y dispositivos → App Remote y dispositivos* o por Wi-Fi/Xcode si ya está emparejado).
3. Arrastra `TVBrowser-tvOS.ipa` a Sideloadly, introduce tu Apple ID y pulsa **Start**.

> **Nota técnica:** Apple no incluye `WebKit` en el SDK público de tvOS para la App Store, por lo que este navegador carga `WebKit` / `UIWebView` dinámicamente en tiempo de ejecución para funcionar mediante sideloading (`.ipa`).
