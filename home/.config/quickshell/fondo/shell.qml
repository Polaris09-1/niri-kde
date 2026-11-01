import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
            property bool pausarTapado: true        // pausar vídeo/GIF si una ventana lo tapa
        }
    }

    // ===== Estado =====
    property string ruta: ""          // fondo puesto (o el que está entrando)
    property string rutaImagen: ""    // imagen fija (fotograma si es vídeo/GIF)
    property bool usarA: true         // qué lienzo es el actual
    property bool enTransicion: false
    property bool tapado: false       // una ventana grande tapa el workspace visible
    property bool primeraVez: true
    property var pendiente: null      // { tipo, x, y } mientras carga el fondo nuevo

    readonly property var lienzoActual: usarA ? lienzoA : lienzoB
    readonly property var lienzoOtro: usarA ? lienzoB : lienzoA
    readonly property bool animado: lienzoActual.tipo === "video" || lienzoActual.tipo === "gif"
    readonly property bool pausado: ajustes.pausarTapado && tapado

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
    Component.onCompleted: Quickshell.watchFiles = false

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
        function info(): string {
            return JSON.stringify({
                ruta: root.ruta,
                imagen: root.rutaImagen,
                tipo: root.lienzoActual.tipo,
                listo: root.lienzoActual.listo,
                enTransicion: root.enTransicion,
                tapado: root.tapado,
                pausado: root.pausado && root.animado,
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
                    var area = nitida.width * nitida.height
                    // Tapa el fondo: la ventana activa del workspace visible (en mosaico, niri la
                    // mantiene a la vista) o una flotante visible, si ocupa casi toda la pantalla
                    // (pantalla completa o maximizada).
                    root.tapado = ventanas.some(v => {
                        if (ids.indexOf(v.workspace_id) < 0 || !v.layout) return false
                        var aLaVista = v.is_floating ? v.layout.tile_pos_in_workspace_view !== null
                                                     : enfocadas.indexOf(v.id) >= 0
                        if (!aLaVista) return false
                        var t = v.layout.tile_size
                        return t[0] * t[1] >= 0.85 * area
                    })
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
            z: root.usarA ? 1 : 0
            pausado: root.pausado && root.usarA && !root.enTransicion
            onListoChanged: if (listo && !root.usarA && root.pendiente) root.empezar()
        }
        Lienzo {
            id: lienzoB
            anchors.fill: parent
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
