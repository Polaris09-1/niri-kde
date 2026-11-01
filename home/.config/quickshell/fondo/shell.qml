import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Effects

// Fondo de escritorio:
//  - capa nítida ("fondo-nitido"): imagen, GIF o vídeo, con transiciones por shader
//    (reemplaza a swaybg; si este módulo no corre, wallpaper.sh vuelve a usar swaybg)
//  - capa difuminada ("fondo-difuminado"): va en el fondo de la vista general de niri
//
// IPC:
//   qs -c fondo ipc call fondo poner <ruta> <tipo> <x> <y>
//        tipo: circulo | ola | barrido | fundido | aleatoria | - (el de ajustes.json)
//        x y: punto de origen en píxeles de la pantalla (-1 -1 = centro)
//   qs -c fondo ipc call fondo info        (estado en JSON)
//   qs -c fondo ipc call fondo bloqueo si|no   (lo llama el módulo "bloqueo": pausa el vídeo)
//
// Rendimiento (2026-11-01): arrancar SIEMPRE con ~/.local/bin/fondo-arrancar.sh (VA-API en la
// Radeon); el vídeo se reproduce desde una copia ajustada a la pantalla (fondo-optimizar.sh).
Scope {
    id: root

    // ===== Ajustes del difuminado =====
    property real difuminado: 1.0     // 0 = nítido, 1 = máximo
    property real oscurecer: -0.25    // brillo: negativo oscurece
    property real tinte: 0.35         // cuánto se tiñe con tu color surface

    // ===== Ajustes de transición (los cambia la galería en fondo/ajustes.json) =====
    FileView {
        id: archivoAjustes
        path: Quickshell.env("HOME") + "/.config/quickshell/fondo/ajustes.json"
        watchChanges: true
        onFileChanged: reload()
        JsonAdapter {
            id: ajustes
            property string transicion: "circulo"   // circulo | ola | barrido | fundido | aleatoria
            property int duracion: 800              // ms
            property bool pausarTapado: true        // pausar vídeo/GIF si las ventanas tapan el escritorio
            property bool pausarConBateria: false   // pausar vídeo/GIF cuando no está enchufado
            property bool optimizarVideo: true      // reproducir una copia al tamaño de la pantalla
            property int fpsVideo: 30               // fps máximos de esa copia (24-30 va bien)
        }
    }

    // ===== Estado =====
    property string ruta: ""          // fondo puesto (o el que está entrando)
    property string rutaImagen: ""    // imagen fija (fotograma si es vídeo/GIF)
    property bool usarA: true         // qué lienzo es el actual
    property bool enTransicion: false
    property bool tapado: false       // las ventanas tapan (casi) todo el workspace visible
    property real cobertura: 0        // fracción de pantalla tapada (para "info")
    property bool bloqueado: false    // sesión bloqueada (avisa el módulo "bloqueo")
    property bool primeraVez: true
    property var pendiente: null      // { tipo, x, y } mientras carga el fondo nuevo

    readonly property var lienzoActual: usarA ? lienzoA : lienzoB
    readonly property var lienzoOtro: usarA ? lienzoB : lienzoA
    readonly property bool animado: lienzoActual.tipo === "video" || lienzoActual.tipo === "gif"
    readonly property bool conBateria: UPower.onBattery
    readonly property string motivoPausa: root.bloqueado ? "bloqueo"
        : (ajustes.pausarTapado && root.tapado) ? "tapado"
        : (ajustes.pausarConBateria && root.conBateria) ? "bateria" : ""
    readonly property bool pausado: root.motivoPausa !== ""

    readonly property var tipos: ({ fundido: 0, circulo: 1, ola: 2, barrido: 3 })

    // Colores de matugen. Este módulo NO se recarga solo cuando cambia un archivo
    // (Quickshell.watchFiles = false): si no, cada cambio de fondo reescribe Colors.qml,
    // Quickshell reinicia el módulo y cortaría la transición o reiniciaría el vídeo.
    // Por eso el color se lee del archivo directamente y se vigila aquí.
    // (Si editas este archivo, reinicia el módulo: pkill -f 'qs -c fondo'; setsid qs -c fondo &)
    QtObject {
        id: tema
        property color surface: "#191114"
    }
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/hola/Colors.qml"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var m = /surface\s*:\s*"(#[0-9a-fA-F]{6,8})"/.exec(text())
            if (m) tema.surface = m[1]
        }
    }
    Component.onCompleted: { Quickshell.watchFiles = false; preguntarBloqueo.running = true }
    Process {
        id: preguntarBloqueo
        command: ["qs", "-c", "bloqueo", "ipc", "call", "bloqueo", "estado"]
        stdout: StdioCollector {
            onStreamFinished: root.bloqueado = text.trim() === "seguro" || text.trim() === "bloqueando"
        }
    }

    function poner(nueva, tipo, x, y) {
        if (nueva === "") return
        if (nueva === root.ruta) return
        root.ruta = nueva

        if (root.primeraVez) {
            // Al arrancar: sin transición
            lienzoActual.ruta = nueva
            return
        }
        if (root.enTransicion) {
            animacion.complete()     // termina la anterior de golpe
        }
        root.pendiente = { tipo: tipo, x: x, y: y }
        lienzoOtro.ruta = nueva
        porSiAcaso.restart()
        if (lienzoOtro.listo) empezar()
    }

    function empezar() {
        if (!root.pendiente) return
        porSiAcaso.stop()
        var p = root.pendiente
        root.pendiente = null

        var t = (p.tipo === "" || p.tipo === "-") ? ajustes.transicion : p.tipo
        if (t === "aleatoria" || !(t in root.tipos)) {
            var nombres = ["circulo", "ola", "barrido", "fundido"]
            t = nombres[Math.floor(Math.random() * nombres.length)]
        }
        efecto.tipo = root.tipos[t]
        efecto.centro = Qt.point(p.x < 0 ? 0.5 : Math.min(1, p.x / nitida.width),
                                 p.y < 0 ? 0.5 : Math.min(1, p.y / nitida.height))
        fuenteDesde.sourceItem = lienzoActual
        fuenteHasta.sourceItem = lienzoOtro
        efecto.progreso = 0
        root.enTransicion = true
        animacion.duration = Math.max(150, ajustes.duracion)
        animacion.restart()
    }

    function terminar() {
        root.usarA = !root.usarA
        root.enTransicion = false
        lienzoOtro.ruta = ""          // libera el fondo viejo (y su decodificador de vídeo)
        fuenteDesde.sourceItem = null
        fuenteHasta.sourceItem = null
    }

    // Si el fondo nuevo nunca avisa de que está listo, transiciona igual
    Timer {
        id: porSiAcaso
        interval: 3000
        onTriggered: root.empezar()
    }

    IpcHandler {
        target: "fondo"
        function poner(ruta: string, tipo: string, x: int, y: int): void {
            root.poner(ruta, tipo, x, y)
        }
        // Para probar sin mirar la pantalla: guarda la capa nítida como imagen
        function captura(archivo: string): void {
            escenaNitida.grabToImage(r => r.saveToFile(archivo), Qt.size(960, 540))
        }
        function bloqueo(estado: string): string {
            root.bloqueado = estado === "si"
            return root.bloqueado ? "pausado" : "reanudado"
        }
        function info(): string {
            return JSON.stringify({
                ruta: root.ruta,
                imagen: root.rutaImagen,
                tipo: root.lienzoActual.tipo,
                video: root.lienzoActual.rutaVideo,
                estadoVideo: root.lienzoActual.estadoVideo,
                listo: root.lienzoActual.listo,
                enTransicion: root.enTransicion,
                tapado: root.tapado,
                cobertura: Math.round(root.cobertura * 100) / 100,
                bloqueado: root.bloqueado,
                conBateria: root.conBateria,
                pausado: root.pausado && root.animado,
                motivoPausa: root.animado ? root.motivoPausa : "",
                ajustesVideo: { pausarTapado: ajustes.pausarTapado, pausarConBateria: ajustes.pausarConBateria,
                                optimizar: ajustes.optimizarVideo, fps: ajustes.fpsVideo },
                transicion: ajustes.transicion,
                duracion: ajustes.duracion,
                superficie: tema.surface.toString()
            })
        }
    }

    // ===== Fondo actual: lo escribe wallpaper.sh =====
    FileView {
        id: archivo
        path: Quickshell.env("HOME") + "/.cache/wallpaper-actual"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var t = text().trim()
            if (root.primeraVez) root.poner(t, "-", -1, -1)
            else if (t !== root.ruta) cambioExterno.restart()
        }
    }
    // Si alguien cambia el archivo sin llamar por IPC, aplica igual (con la transición por defecto)
    Timer {
        id: cambioExterno
        interval: 1000
        onTriggered: {
            var t = archivo.text().trim()
            if (t !== root.ruta) root.poner(t, "-", -1, -1)
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/wallpaper-imagen"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.rutaImagen = text().trim()
    }

    // Cuando el primer fondo ya se ve, quita swaybg (si quedaba de respaldo)
    Process {
        id: quitarSwaybg
        command: ["pkill", "-x", "swaybg"]
    }
    Connections {
        target: root.lienzoActual
        function onListoChanged() {
            if (root.primeraVez && root.lienzoActual.listo) {
                root.primeraVez = false
                quitarSwaybg.running = true
            }
        }
    }

    // ===== ¿Hay una ventana que tapa el fondo? (solo importa con vídeo/GIF) =====
    Process {
        id: eventos
        command: ["niri", "msg", "--json", "event-stream"]
        running: true
        stdout: SplitParser {
            onRead: dato => { if (root.animado) revisar.restart() }
        }
        onRunningChanged: if (!running) reintentar.start()
    }
    Timer {
        id: reintentar
        interval: 3000
        onTriggered: eventos.running = true
    }
    Timer {
        id: revisar
        interval: 250
        onTriggered: {
            if (consulta.running) { revisar.restart(); return }
            consulta.running = true
        }
    }
    onAnimadoChanged: if (animado) revisar.restart()

    Process {
        id: consulta
        command: ["sh", "-c", "niri msg --json workspaces; niri msg --json windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var lineas = text.trim().split("\n")
                    var ws = JSON.parse(lineas[0])
                    var ventanas = JSON.parse(lineas[1])
                    var salida = nitida.screen ? nitida.screen.name : ""
                    var activos = ws.filter(w => w.is_active && (salida === "" || w.output === salida))
                    var ids = activos.map(w => w.id)
                    var enfocadas = activos.map(w => w.active_window_id)
                    var W = nitida.width, H = nitida.height
                    var area = W * H
                    var vis = ventanas.filter(v => ids.indexOf(v.workspace_id) >= 0 && v.layout)
                    // Flotantes a la vista: la más grande
                    var flotante = 0
                    vis.forEach(v => {
                        if (v.is_floating && v.layout.tile_pos_in_workspace_view !== null)
                            flotante = Math.max(flotante, v.layout.tile_size[0] * v.layout.tile_size[1])
                    })
                    // Mosaico (niri en scroll): por columna, ancho = el de su ventana más ancha y
                    // alto = suma de sus ventanas. Si las columnas juntas llenan el ancho, niri
                    // siempre muestra la pantalla llena; si no, solo tapan lo que miden.
                    var columnas = {}
                    vis.forEach(v => {
                        var pos = v.layout.pos_in_scrolling_layout
                        if (v.is_floating || !pos) return
                        var k = v.workspace_id + ":" + pos[0]
                        var c = columnas[k] || { w: 0, h: 0 }
                        c.w = Math.max(c.w, v.layout.tile_size[0])
                        c.h += v.layout.tile_size[1]
                        columnas[k] = c
                    })
                    var ancho = 0, alto = 0
                    Object.keys(columnas).forEach(k => {
                        ancho += columnas[k].w + 16          // + hueco entre columnas
                        alto = Math.max(alto, columnas[k].h)
                    })
                    var mosaico = Math.min(W, ancho) * Math.min(H, alto)
                    root.cobertura = Math.min(1, Math.max(mosaico, flotante) / Math.max(1, area))
                    // ≥ 85 %: pantalla completa, maximizada o columnas que llenan la pantalla
                    root.tapado = root.cobertura >= 0.85
                } catch (e) {
                    console.warn("fondo: no pude leer niri:", e)
                }
            }
        }
    }

    // ===================== Capa nítida =====================
    PanelWindow {
        id: nitida
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "fondo-nitido"
        color: tema.surface

        Item {
            id: escenaNitida
            anchors.fill: parent

        Lienzo {
            id: lienzoA
            anchors.fill: parent
            optimizar: ajustes.optimizarVideo
            fps: ajustes.fpsVideo
            z: root.usarA ? 1 : 0
            pausado: root.pausado && root.usarA && !root.enTransicion
            onListoChanged: if (listo && !root.usarA && root.pendiente) root.empezar()
        }
        Lienzo {
            id: lienzoB
            anchors.fill: parent
            optimizar: ajustes.optimizarVideo
            fps: ajustes.fpsVideo
            z: root.usarA ? 0 : 1
            pausado: root.pausado && !root.usarA && !root.enTransicion
            onListoChanged: if (listo && root.usarA && root.pendiente) root.empezar()
        }

        ShaderEffectSource {
            id: fuenteDesde
            hideSource: root.enTransicion
            visible: false
        }
        ShaderEffectSource {
            id: fuenteHasta
            hideSource: root.enTransicion
            visible: false
        }

        ShaderEffect {
            id: efecto
            anchors.fill: parent
            z: 2
            visible: root.enTransicion
            property variant desde: fuenteDesde
            property variant hasta: fuenteHasta
            property real progreso: 0
            property real tipo: 1
            property real aspecto: width / Math.max(1, height)
            property point centro: Qt.point(0.5, 0.5)
            fragmentShader: "transicion.frag.qsb"

            NumberAnimation {
                id: animacion
                target: efecto
                property: "progreso"
                from: 0
                to: 1
                easing.type: Easing.InOutCubic
                onFinished: root.terminar()
            }
        }
        }
    }

    // ===================== Capa difuminada (vista general) =====================
    PanelWindow {
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "fondo-difuminado"
        color: tema.surface

        // Imagen original (oculta; solo sirve de fuente para el efecto)
        Image {
            id: imagen
            anchors.fill: parent
            visible: false
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 640
            // Imagen fija; si aún no existe el archivo, la ruta del fondo si es una imagen
            source: {
                var r = root.rutaImagen !== "" ? root.rutaImagen
                      : (/\.(jpe?g|png|webp|bmp)$/i.test(root.ruta) ? root.ruta : "")
                return r !== "" ? "file://" + r : ""
            }
        }

        // Difuminado + oscurecido
        MultiEffect {
            anchors.fill: parent
            source: imagen
            blurEnabled: true
            blur: root.difuminado
            blurMax: 64
            brightness: root.oscurecer
        }

        // Tinte con tu color de matugen
        Rectangle {
            anchors.fill: parent
            color: tema.surface
            opacity: root.tinte
        }
    }
}
