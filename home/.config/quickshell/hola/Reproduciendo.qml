import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Qué está sonando: reproductores MPRIS y audio de apps sin MPRIS (lo publica el módulo "bloqueo").
// Decide cuándo se ve la píldora y lleva las ondas (cava; si falla, una animación simulada).
// Los títulos solo viven en memoria: el registro de "bloqueo" guarda nombres de apps, nunca títulos.
Scope {
    id: r

    // Entradas
    property var audio: []              // nombres de apps con un flujo de audio activo
    property bool pausarOndas: false    // barra escondida o sesión bloqueada
    property bool retener: false        // el cursor está encima: no se oculta aunque pase el tiempo
    property var salida: null           // salida predeterminada: al cambiar, cava vuelve a engancharse

    // Ajustes
    property int esperaOcultar: 10000   // ms desde que deja de sonar hasta que se oculta
    property bool ondasReales: true     // false = animación simulada
    property int esperaAudio: 5500      // ms para creer a un audio sin MPRIS (dos lecturas de "bloqueo": un aviso no cuenta)

    // ===== Reproductores =====
    readonly property var reproductores: Mpris.players.values
    readonly property var enJuego: r.reproductores.find(j => j.isPlaying) || null
    // Recuerda el último que sonó: al pausar no salta a otro reproductor parado
    property var ultimo: null
    onEnJuegoChanged: if (r.enJuego) r.ultimo = r.enJuego
    readonly property var jugador: r.enJuego
        || (r.ultimo && r.reproductores.indexOf(r.ultimo) >= 0 ? r.ultimo : null)
        || r.reproductores[0] || null

    // ===== Audio de apps sin MPRIS =====
    function parecido(a, b) {
        if (!a || !b) return false
        a = a.toLowerCase(); b = b.toLowerCase()
        return a.indexOf(b) >= 0 || b.indexOf(a) >= 0
    }
    // Un flujo de una app con MPRIS no cuenta: al pausar, el navegador lo mantiene abierto un rato
    readonly property var audioAjeno: (r.audio || [])
        .filter((n, i, l) => l.indexOf(n) === i)
        .filter(n => !r.reproductores.some(j => r.parecido(n, j.identity) || r.parecido(n, j.desktopEntry)))
    readonly property string claveAudio: r.audioAjeno.join("|")
    property var audioConfirmado: []
    onClaveAudioChanged: {
        if (r.claveAudio === "") { confirmar.stop(); r.audioConfirmado = [] }
        else if (r.audioConfirmado.length > 0) r.audioConfirmado = r.audioAjeno
        else confirmar.restart()
    }
    Timer {
        id: confirmar
        interval: r.esperaAudio
        onTriggered: r.audioConfirmado = r.audioAjeno
    }

    // ===== Lo que se muestra =====
    readonly property bool sonando: r.enJuego !== null || r.audioConfirmado.length > 0
    // El reproductor al que van los botones; null = solo hay audio sin MPRIS (sin controles)
    readonly property var activo: r.enJuego || (r.audioConfirmado.length > 0 ? null : r.jugador)
    readonly property var entrada: {
        var nombre = r.activo ? r.activo.identity : (r.audioConfirmado[0] || "")
        var e = r.activo && r.activo.desktopEntry ? DesktopEntries.byId(r.activo.desktopEntry) : null
        return e || (nombre ? DesktopEntries.heuristicLookup(nombre) : null)
    }
    readonly property string nombreApp: r.entrada ? r.entrada.name
        : r.activo ? (r.activo.identity || "") : (r.audioConfirmado[0] || "")
    // Sin título (p. ej. contenido con DRM): el nombre de la app o "Reproduciendo"
    readonly property string titulo: {
        var t = r.activo && r.activo.trackTitle ? String(r.activo.trackTitle).trim() : ""
        return t || r.nombreApp || "Reproduciendo"
    }
    readonly property string icono: Quickshell.iconPath(r.entrada && r.entrada.icon ? r.entrada.icon : "audio-x-generic", "audio-x-generic")

    // ===== Píldora visible =====
    property bool presente: false
    function revisar() {
        if (r.sonando) { ocultar.stop(); r.presente = true }
        else if (r.presente) ocultar.restart()
    }
    onSonandoChanged: r.revisar()
    Component.onCompleted: r.revisar()
    Timer {
        id: ocultar
        interval: r.esperaOcultar
        onTriggered: { if (r.retener) restart(); else r.presente = false }
    }

    // ===== Ondas =====
    property var niveles: [0, 0, 0, 0, 0]
    readonly property bool quiereOndas: r.sonando && r.presente && !r.pausarOndas
    property bool cavaFallo: false
    property bool reiniciando: false
    onQuiereOndasChanged: if (!r.sonando) r.cavaFallo = false     // otra oportunidad la próxima vez
    onSalidaChanged: if (pCava.running) { r.reiniciando = true; volver.restart() }
    Timer { id: volver; interval: 300; onTriggered: r.reiniciando = false }

    Process {
        id: pCava
        running: r.quiereOndas && r.ondasReales && !r.cavaFallo && !r.reiniciando
        command: ["cava", "-p", Quickshell.shellDir + "/cava-ondas.conf"]
        stdout: SplitParser {
            onRead: linea => {
                var v = linea.split(";")
                if (v.length >= 5) r.niveles = v.slice(0, 5).map(Number)
            }
        }
        onRunningChanged: if (!running && r.quiereOndas && r.ondasReales && !r.reiniciando) r.cavaFallo = true
    }
    // Sin cava: barras que suben y bajan con ritmos distintos
    Timer {
        running: r.quiereOndas && (r.cavaFallo || !r.ondasReales)
        repeat: true
        interval: 50
        property real t: 0
        onTriggered: {
            t += 0.05
            r.niveles = [0, 1, 2, 3, 4].map(i => 45 + 30 * Math.sin(t * (3.1 + i * 1.3) + i * 1.7)
                + 20 * Math.sin(t * (7.3 - i * 0.9) + i))
        }
    }
}
