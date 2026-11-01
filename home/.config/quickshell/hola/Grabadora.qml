import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Grabación de pantalla con wf-recorder.
// iniciar("pantalla"|"area", "no"|"sistema"|"mic") · detener() (SIGINT: el MP4 queda bien cerrado)
Scope {
    id: g

    property bool grabando: false
    property bool eligiendoArea: false
    property int segundos: 0
    property string ruta: ""
    property string error: ""
    property string audio: "no"
    property string carpeta: Quickshell.env("HOME") + "/Videos/Grabaciones"

    function dosDigitos(n) { return (n < 10 ? "0" : "") + n }
    function tiempo() { return g.dosDigitos(Math.floor(g.segundos / 60)) + ":" + g.dosDigitos(g.segundos % 60) }

    function iniciar(modo, audio) {
        if (g.grabando || g.eligiendoArea) return
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
        if (g.grabando) proc.signal(2)
    }

    function alternar() { g.grabando ? g.detener() : g.iniciar("pantalla", g.audio) }

    function arrancar(geometria) {
        var ahora = new Date()
        g.ruta = g.carpeta + "/Grabación " + Qt.formatDateTime(ahora, "yyyy-MM-dd HH-mm-ss") + ".mp4"
        var extra = []
        if (geometria !== "") extra.push("-g", geometria)
        var sink = Pipewire.defaultAudioSink
        if (g.audio === "sistema" && sink) extra.push("--audio=" + sink.name + ".monitor")
        else if (g.audio === "mic") extra.push("--audio")
        // exec: la señal de "detener" le llega directo a wf-recorder
        proc.command = ["sh", "-c", "mkdir -p \"$1\" && f=\"$2\" && shift 2 && exec wf-recorder -y -f \"$f\" \"$@\"",
                        "sh", g.carpeta, g.ruta].concat(extra)
        g.segundos = 0
        proc.running = true
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

    Process {
        id: proc
        stderr: StdioCollector { id: errorGrab }
        onStarted: { g.grabando = true; reloj.start() }
        onExited: code => {
            reloj.stop()
            var duro = g.segundos
            g.grabando = false
            if (duro >= 1) {
                Quickshell.execDetached(["notify-send", "-a", "Grabación", "-i", "media-record",
                    "Grabación guardada (" + g.tiempo() + ")", g.ruta.replace(Quickshell.env("HOME"), "~")])
            } else {
                g.error = /audio|pulse|pipewire/i.test(errorGrab.text) ? "No se pudo grabar el audio elegido"
                    : "No se pudo iniciar la grabación"
            }
        }
    }

    Timer {
        id: reloj
        interval: 1000
        repeat: true
        onTriggered: g.segundos++
    }
}
