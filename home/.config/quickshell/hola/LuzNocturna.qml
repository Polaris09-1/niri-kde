import QtQuick
import Quickshell
import Quickshell.Io

// Luz nocturna con wlsunset (protocolo wlr-gamma-control de niri).
// modo: "apagada" | "sol" (se calienta al ponerse el sol, según lat/lon) | "siempre"
// Ajustes en hola/luz-nocturna.json. wlsunset no cambia en vivo: cada cambio lo reinicia.
// "siempre" = wlsunset con alta = baja + 1 K (siempre a esa calidez, sin depender del sol).
Item {
    id: ln

    readonly property string modo: ajustes.modo
    readonly property int temperatura: ajustes.temperatura
    readonly property bool activa: ajustes.modo !== "apagada"
    readonly property string ultimoModo: ajustes.ultimoModo
    // Lo que va diciendo wlsunset (stdout)
    property int tempActual: 6500
    property string amanecer: ""
    property string atardecer: ""
    property string anochecer: ""     // fin del crepúsculo (calidez completa)
    property string alba: ""          // inicio del crepúsculo de la mañana
    property string error: ""
    readonly property bool calida: ln.activa && ln.tempActual < 6400
    // Vista previa: unos segundos a la calidez elegida aunque sea de día
    property bool previa: false

    readonly property int alta: 6500

    function ponerModo(m) {
        if (["apagada", "sol", "siempre"].indexOf(m) < 0) return
        if (m !== "apagada") ajustes.ultimoModo = m
        ajustes.modo = m
    }
    function alternar() { ponerModo(ln.activa ? "apagada" : (ajustes.ultimoModo || "sol")) }
    function ponerUbicacion(lat, lon) {
        ajustes.lat = Math.max(-90, Math.min(90, lat))
        ajustes.lon = Math.max(-180, Math.min(180, lon))
    }
    function ponerTemperatura(k) {
        k = Math.round(Math.max(3000, Math.min(5500, k)) / 100) * 100
        ajustes.temperatura = k
        // De día en modo "sol" no se vería nada: muestra la calidez 3 s
        if (ajustes.modo === "sol" && !ln.calida) { ln.previa = true; finPrevia.restart() }
    }

    readonly property var comando: {
        var t = String(ajustes.temperatura)
        var forzado = ajustes.modo === "siempre" || ln.previa
        var alta = forzado ? String(ajustes.temperatura + 1) : String(ln.alta)
        return ["wlsunset", "-t", t, "-T", alta, "-l", String(ajustes.lat), "-L", String(ajustes.lon)]
    }
    readonly property bool debeCorrer: ajustes.modo !== "apagada" || ln.previa
    onComandoChanged: reiniciar.restart()
    onDebeCorrerChanged: reiniciar.restart()

    // Un pequeño retraso junta cambios seguidos (modo + temperatura) en un solo reinicio
    Timer {
        id: reiniciar
        interval: 80
        onTriggered: {
            if (proc.running) { proc.running = false; arrancar.restart() }
            else if (ln.debeCorrer) arrancar.restart()
            if (!ln.debeCorrer) ln.tempActual = ln.alta
        }
    }
    Timer {
        id: arrancar
        interval: 120
        onTriggered: if (ln.debeCorrer && !proc.running) { ln.error = ""; proc.command = ln.comando; proc.running = true }
    }
    Timer {
        id: finPrevia
        interval: 3000
        onTriggered: ln.previa = false
    }

    // wlsunset escribe todo por stderr (horas del sol, temperatura y errores)
    function leerLinea(linea) {
        var m = linea.match(/dawn (\S+), sunrise (\S+), sunset (\S+), dusk (\S+)/)
        if (m) { ln.alba = m[1]; ln.amanecer = m[2]; ln.atardecer = m[3]; ln.anochecer = m[4]; return }
        var t = linea.match(/setting temperature to (\d+) K/)
        if (t) { ln.tempActual = parseInt(t[1]); return }
        if (/must|invalid|fail|could not|error|not supported|unable/i.test(linea)) ln.error = linea
    }
    Process {
        id: proc
        stdout: SplitParser { onRead: linea => ln.leerLinea(linea) }
        stderr: SplitParser { onRead: linea => ln.leerLinea(linea) }
        onExited: (codigo, estado) => {
            ln.tempActual = ln.alta
            // Se cerró solo (no por un reinicio nuestro): reintenta una vez a los 5 s
            if (ln.debeCorrer && codigo !== 0 && !reiniciar.running && !arrancar.running) reintento.restart()
        }
    }
    Timer {
        id: reintento
        interval: 5000
        onTriggered: if (ln.debeCorrer && !proc.running) arrancar.restart()
    }

    FileView {
        path: Quickshell.shellDir + "/luz-nocturna.json"
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter() }
        onAdapterUpdated: writeAdapter()
        onLoaded: reiniciar.restart()
        JsonAdapter {
            id: ajustes
            property string modo: "sol"
            property string ultimoModo: "sol"
            property int temperatura: 4000
            // Ubicación para calcular el sol (cámbiala aquí o en hola/luz-nocturna.json)
            property real lat: 0.0
            property real lon: 0.0
        }
    }

    function info() {
        return { modo: ln.modo, temperatura: ln.temperatura, actual: ln.tempActual, calida: ln.calida,
            corriendo: proc.running, previa: ln.previa, alba: ln.alba, amanecer: ln.amanecer,
            atardecer: ln.atardecer, anochecer: ln.anochecer, error: ln.error, comando: proc.command,
            lat: ajustes.lat, lon: ajustes.lon }
    }
}
