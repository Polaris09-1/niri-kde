import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick

// OSD (2026-11-01, punto 3 del plan 10/10): pastilla discreta abajo al centro (24 px, o sobre el dock)
// al cambiar volumen, micro, brillo o Bloq Mayús. Las teclas XF86 de niri llaman a su IPC
// (`qs -c osd ipc call osd volumen subir`…); si el módulo no corre, niri usa wpctl/brightnessctl.
// Bloq Mayús se lee del LED (/sys/class/leds/*::capslock) cada 200 ms: no hay evento para él.
ShellRoot {
    id: root

    // ===== Ajustes (versión discreta, 2026-11-01) =====
    property int mostrarMs: 1000          // cuánto se queda visible tras el último cambio
    property real pasoVolumen: 0.02       // igual que antes en niri (2 %)
    property int pasoBrillo: 10           // % por pulsación (igual que antes en niri)
    property int abajoNormal: 24          // px desde el borde inferior
    property int abajoConDock: 72         // si el dock está a la vista (su ola llega a ~67 px)
    property int ancho: 220               // ancho con barra (volumen y brillo)
    property int alto: 36
    property real opacidadFondo: 0.70     // el blur de niri hace el resto
    property string fuente: "JetBrainsMono Nerd Font"

    Colors { id: tema }

    // ===== Estado =====
    property var sink: Pipewire.defaultAudioSink
    property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source].filter(o => o) }

    readonly property bool hayAudio: !!(root.sink && root.sink.audio)
    readonly property int volumen: root.hayAudio ? Math.round(root.sink.audio.volume * 100) : 0
    readonly property bool silencio: root.hayAudio ? root.sink.audio.muted : false
    readonly property bool microMudo: (root.source && root.source.audio) ? root.source.audio.muted : false
    property int brillo: -1
    property bool mayus: false

    property string tipo: "volumen"       // volumen | micro | brillo | mayus
    property bool activo: false

    function ic(cp) { return String.fromCodePoint(cp) }
    function alfa(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // Antes de aparecer pregunta al dock si está a la vista (tarda ~40 ms), para no tener
    // que saltar después. Si el dock no corre, la respuesta falla y se queda abajo.
    property bool dockVisible: false
    property bool esperandoDock: false
    function mostrar(t) {
        root.tipo = t
        ocultar.restart()
        if (!pDock.running) pDock.running = true
        if (!root.activo) root.esperandoDock = true
        else ocultar.restart()
    }
    function aparecer() {
        if (!root.esperandoDock) return
        root.esperandoDock = false
        root.activo = true
        ocultar.restart()
    }
    Process {
        id: pDock
        command: ["qs", "-c", "dock", "ipc", "call", "dock", "estaVisible"]
        stdout: StdioCollector { id: respuestaDock; onStreamFinished: root.dockVisible = this.text.trim() === "si" }
        onExited: (codigo) => {
            root.dockVisible = codigo === 0 && respuestaDock.text.trim() === "si"
            root.aparecer()
        }
    }
    Timer { id: ocultar; interval: root.mostrarMs; onTriggered: root.activo = false }

    // ----- Volumen y micro (Pipewire) -----
    function cambiarVolumen(d) {
        if (!root.hayAudio) return "sin-audio"
        if (d > 0) root.sink.audio.muted = false
        var v = Math.round((root.sink.audio.volume + d) * 100) / 100
        root.sink.audio.volume = Math.max(0, Math.min(1, v))
        root.mostrar("volumen")
        return "ok"
    }
    function alternarSilencio() {
        if (!root.hayAudio) return "sin-audio"
        root.sink.audio.muted = !root.sink.audio.muted
        root.mostrar("volumen")
        return "ok"
    }
    function alternarMicro() {
        if (!(root.source && root.source.audio)) return "sin-micro"
        root.source.audio.muted = !root.source.audio.muted
        root.mostrar("micro")
        return "ok"
    }

    // ----- Brillo (brightnessctl; -m devuelve "nombre,clase,actual,NN%,max") -----
    property int brilloPendiente: 0
    function cambiarBrillo(d) {
        if (pBrillo.running) { root.brilloPendiente += d; root.mostrar("brillo"); return "ok" }
        pBrillo.command = ["brightnessctl", "--class=backlight", "-m", "set",
                           d >= 0 ? ("+" + d + "%") : ((-d) + "%-")]
        pBrillo.running = true
        root.mostrar("brillo")
        return "ok"
    }
    function leerBrillo(texto) {
        var campos = String(texto).trim().split("\n")[0].split(",")
        if (campos.length >= 4) {
            var n = parseInt(campos[3])
            if (!isNaN(n)) root.brillo = n
        }
    }
    Process {
        id: pBrillo
        stdout: StdioCollector { onStreamFinished: root.leerBrillo(this.text) }
        onExited: {
            if (root.brilloPendiente !== 0) {
                var d = root.brilloPendiente
                root.brilloPendiente = 0
                root.cambiarBrillo(d)
            }
        }
    }
    Process {
        id: pBrilloInicial
        running: true
        command: ["brightnessctl", "--class=backlight", "-m"]
        stdout: StdioCollector { onStreamFinished: root.leerBrillo(this.text) }
    }

    // ----- Bloq Mayús (LED del teclado, cada 200 ms) -----
    property var ledsMayus: []
    property bool mayusLeido: false
    Process {
        running: true
        command: ["sh", "-c", "for l in /sys/class/leds/*::capslock; do [ -e \"$l/brightness\" ] && echo \"$l/brightness\"; done"]
        stdout: StdioCollector { onStreamFinished: root.ledsMayus = this.text.split("\n").filter(l => l.length > 0) }
    }
    Variants {
        id: lectores
        model: root.ledsMayus
        delegate: FileView {
            required property var modelData
            path: modelData
            blockLoading: true
        }
    }
    Timer {
        interval: 200
        running: root.ledsMayus.length > 0
        repeat: true
        onTriggered: {
            var encendido = false
            for (var i = 0; i < lectores.instances.length; i++) {
                var f = lectores.instances[i]
                f.reload()
                if (parseInt(f.text()) > 0) encendido = true
            }
            if (!root.mayusLeido) { root.mayus = encendido; root.mayusLeido = true; return }
            if (encendido !== root.mayus) { root.mayus = encendido; root.mostrar("mayus") }
        }
    }

    // ===== Lo que se muestra =====
    readonly property bool conBarra: root.tipo === "volumen" || root.tipo === "brillo"
    readonly property real valor: root.tipo === "volumen" ? (root.silencio ? 0 : root.volumen / 100)
                                : root.tipo === "brillo" ? Math.max(0, root.brillo) / 100 : 0
    readonly property string icono: {
        if (root.tipo === "volumen") {
            if (root.silencio || root.volumen === 0) return ic(0xF075F)
            if (root.volumen < 34) return ic(0xF057F)
            if (root.volumen < 67) return ic(0xF0580)
            return ic(0xF057E)
        }
        if (root.tipo === "brillo") return ic(root.brillo < 34 ? 0xF00DE : root.brillo < 67 ? 0xF00DF : 0xF00E0)
        if (root.tipo === "micro") return ic(root.microMudo ? 0xF036D : 0xF036C)
        return ic(0xF0632)
    }
    readonly property string texto: {
        if (root.tipo === "volumen") return root.silencio ? "mudo" : root.volumen + "%"
        if (root.tipo === "brillo") return root.brillo < 0 ? "…" : root.brillo + "%"
        if (root.tipo === "micro") return root.microMudo ? "Micrófono silenciado" : "Micrófono activo"
        return root.mayus ? "Bloq Mayús activado" : "Bloq Mayús desactivado"
    }
    // Apagado (mudo, micro silenciado, Mayús desactivado) se ve más tenue
    readonly property bool apagado: (root.tipo === "volumen" && root.silencio)
                                  || (root.tipo === "micro" && root.microMudo)
                                  || (root.tipo === "mayus" && !root.mayus)

    PanelWindow {
        id: ventana
        anchors.bottom: true
        implicitWidth: 300
        implicitHeight: root.abajoConDock + root.alto + 16
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "osd"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}                   // no atrapa el mouse: los clics pasan
        visible: p > 0.001

        // Blur real de niri (ext-background-effect), solo con la forma de la pastilla.
        // Se pide a mitad del fundido para que no aparezca de golpe.
        BackgroundEffect.blurRegion: ventana.p > 0.5 ? zonaBlur : null
        property Region zonaBlur: Region { item: pastilla; radius: root.alto / 2 }

        // 0 = escondida, 1 = visible. Entra en 150 ms y sale en 120 (OutCubic, sin rebote)
        property real p: root.activo ? 1 : 0
        Behavior on p { NumberAnimation { duration: root.activo ? 150 : 120; easing.type: Easing.OutCubic } }

        // Altura sobre el borde: 24 px, o lo justo para no tapar el dock
        property real abajo: root.dockVisible ? root.abajoConDock : root.abajoNormal
        Behavior on abajo { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Item {
            id: pastilla
            width: root.conBarra ? root.ancho : Math.max(170, fila.implicitWidth + 32)
            height: root.alto
            anchors.horizontalCenter: parent.horizontalCenter
            y: ventana.height - ventana.abajo - height + (1 - ventana.p) * 12
            opacity: ventana.p
            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            // Fondo translúcido + borde sutil (sin sombra)
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: root.alfa(tema.surface, root.opacidadFondo)
                border.color: root.alfa(tema.primary, 0.35)
                border.width: 1
            }

            Row {
                id: fila
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: root.conBarra ? undefined : parent.horizontalCenter
                x: root.conBarra ? 14 : 0
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    horizontalAlignment: Text.AlignHCenter
                    text: root.icono
                    font.family: root.fuente
                    font.pixelSize: 15
                    color: root.apagado ? root.alfa(tema.surfaceText, 0.5) : tema.primary
                }

                // Barra fina (volumen y brillo): 220 - 14 - 18 - 10 - 10 - 34 - 14 = 120
                Item {
                    visible: root.conBarra
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.ancho - 100
                    height: 4
                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: root.alfa(tema.surfaceText, 0.15)
                    }
                    Rectangle {
                        height: parent.height
                        radius: 2
                        width: Math.max(height, parent.width * Math.max(0, Math.min(1, root.valor)))
                        opacity: root.valor > 0 ? 1 : 0
                        color: tema.primary
                        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.conBarra ? 34 : undefined
                    horizontalAlignment: root.conBarra ? Text.AlignRight : Text.AlignLeft
                    text: root.texto
                    font.family: root.fuente
                    font.pixelSize: 11
                    color: root.apagado ? root.alfa(tema.surfaceText, 0.6) : root.alfa(tema.surfaceText, 0.9)
                }
            }
        }
    }

    // ===== IPC: qs -c osd ipc call osd <función> ... =====
    IpcHandler {
        target: "osd"
        function volumen(accion: string): string {
            if (accion === "subir") return root.cambiarVolumen(root.pasoVolumen)
            if (accion === "bajar") return root.cambiarVolumen(-root.pasoVolumen)
            if (accion === "silenciar") return root.alternarSilencio()
            return "uso: volumen subir|bajar|silenciar"
        }
        function micro(): string { return root.alternarMicro() }
        function brillo(accion: string): string {
            if (accion === "subir") return root.cambiarBrillo(root.pasoBrillo)
            if (accion === "bajar") return root.cambiarBrillo(-root.pasoBrillo)
            return "uso: brillo subir|bajar"
        }
        // Mostrar sin cambiar nada (para probar): volumen | micro | brillo | mayus
        function mostrar(tipo: string): string { root.mostrar(tipo); return tipo }
        function info(): string {
            return JSON.stringify({ activo: root.activo, tipo: root.tipo, volumen: root.volumen,
                silencio: root.silencio, micro_mudo: root.microMudo, brillo: root.brillo,
                mayus: root.mayus, leds_mayus: root.ledsMayus, audio: root.hayAudio,
                led_leido: lectores.instances.map(f => f.text().trim()) })
        }
    }
}
