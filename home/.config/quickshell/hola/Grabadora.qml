import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Grabación de pantalla: todo el trabajo lo hace ~/.local/bin/grabar.sh, fuera de este proceso, porque
// una recarga de hola (matugen al cambiar el fondo) mataría a un hijo y dejaría el vídeo sin cerrar.
// Aquí solo se piden cosas y se lee su estado, también el de una grabación que empezó antes de recargar.
// iniciar("pantalla"|"area", "no"|"sistema"|"mic") · detener()
Scope {
    id: g

    property bool grabando: false
    property bool procesando: false     // ya no graba: convirtiendo a .mp4
    property bool arrancando: false     // pedida al script, aún sin respuesta
    property bool eligiendoArea: false
    property int inicio: 0
    property int segundos: 0
    property string ruta: ""
    property string error: ""
    property string audio: "no"
    property string idPedido: ""
    readonly property string script: Quickshell.env("HOME") + "/.local/bin/grabar.sh"

    function dosDigitos(n) { return (n < 10 ? "0" : "") + n }
    function tiempo() { return g.dosDigitos(Math.floor(g.segundos / 60)) + ":" + g.dosDigitos(g.segundos % 60) }

    function iniciar(modo, audio) {
        if (g.grabando || g.procesando || g.arrancando || g.eligiendoArea) return
        g.error = ""
        g.audio = audio || "no"
        if (modo === "area") {
            g.eligiendoArea = true
            pArea.running = true
        } else {
            g.arrancar("")
        }
    }

    function detener() {
        if (g.grabando) Quickshell.execDetached([g.script, "detener"])
    }

    function alternar() { g.grabando ? g.detener() : g.iniciar("pantalla", g.audio) }

    function arrancar(geometria) {
        var extra = []
        if (geometria !== "") extra.push("-g", geometria)
        var sink = Pipewire.defaultAudioSink
        if (g.audio === "sistema") {
            // Sin salida de audio no hay qué grabar: antes grababa sin sonido sin avisar
            if (!sink) {
                g.error = "No hay ninguna salida de audio para grabar el sonido del sistema"
                Quickshell.execDetached(["notify-send", "-a", "Grabación", "-i", "media-record", "-u", "critical",
                                         "No se empezó a grabar", g.error])
                return
            }
            extra.push("--audio=" + sink.name + ".monitor")
        }
        else if (g.audio === "mic") extra.push("--audio")
        g.idPedido = String(Date.now())
        g.segundos = 0
        g.arrancando = true
        limiteArranque.restart()
        Quickshell.execDetached([g.script, "iniciar", g.idPedido].concat(extra))
    }

    function leerEstado() {
        var d
        try { d = JSON.parse(fEstado.text()) } catch (e) { return }
        var inactivo = d.estado === "inactivo"
        // Mientras arranca, el archivo aún puede ser el de la grabación anterior
        if (g.arrancando && inactivo && d.id !== g.idPedido) return
        if (inactivo && (g.grabando || g.procesando || g.arrancando)) g.error = d.error
        g.arrancando = false
        limiteArranque.stop()
        g.grabando = d.estado === "grabando"
        g.procesando = d.estado === "procesando"
        if (inactivo) return
        g.ruta = d.ruta
        g.inicio = d.inicio
        if (g.grabando) g.segundos = Math.max(0, Math.floor(Date.now() / 1000) - g.inicio)
    }

    FileView {
        id: fEstado
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/grabacion/estado.json"
        printErrors: false
        onLoaded: g.leerEstado()
    }

    // Solo lee mientras hay algo en marcha: sin grabar no gasta nada
    Timer {
        interval: 500
        repeat: true
        running: g.grabando || g.procesando || g.arrancando
        onTriggered: fEstado.reload()
    }

    Timer {
        id: limiteArranque
        interval: 5000
        onTriggered: {
            g.arrancando = false
            g.error = "No se pudo iniciar la grabación"
        }
    }

    // Al arrancar o recargar: retomar una grabación en curso y limpiar si su vigilante ya no existe
    Component.onCompleted: {
        Quickshell.execDetached([g.script, "revisar"])
        fEstado.reload()
    }

    // Elegir área con slurp
    Process {
        id: pArea
        command: ["slurp", "-d", "-b", "#00000066", "-c", "#ffb4a9ff", "-w", "2"]
        stdout: StdioCollector { id: salidaArea }
        onExited: code => {
            g.eligiendoArea = false
            var geo = salidaArea.text.trim()
            if (code === 0 && geo !== "") g.arrancar(geo)
            else g.error = "Se canceló la selección del área"
        }
    }
}
