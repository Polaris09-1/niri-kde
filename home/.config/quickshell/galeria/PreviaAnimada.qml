import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

// Vista previa animada de la galería: reproduce en bucle y sin sonido el vídeo o GIF elegido,
// aunque no esté aplicado. Los vídeos se reproducen desde la copia optimizada de
// fondo-optimizar.sh (pantalla, 30 fps; la misma caché que usa el módulo "fondo"), nunca desde el
// original 4K. Si la copia aún no existe, se crea en segundo plano y mientras tanto queda la
// imagen fija. ruta = "" detiene todo (al cerrar la galería).
// La tarjeta del centro no decodifica nada: copia esta imagen con un ShaderEffectSource.
Item {
    id: pa

    property string ruta: ""
    property int anchoV: 1920
    property int altoV: 1080
    property int fps: 30
    readonly property string script: Quickshell.env("HOME") + "/.local/bin/fondo-optimizar.sh"

    property var optimizados: ({})        // ruta original -> copia ("" = no se pudo)
    property string reproduciendo: ""     // ruta original que se está viendo
    property bool listo: false            // ya hay un fotograma pintado de "reproduciendo"
    readonly property bool esGif: /\.gif$/i.test(pa.reproduciendo)

    function detener() {
        reproductor.stop()
        reproductor.source = ""
        gif.source = ""
        pa.listo = false
        pa.reproduciendo = ""
    }

    // Cada cambio detiene lo anterior y espera a que la selección se asiente (no decodifica
    // nada mientras recorres el carrusel deprisa)
    onRutaChanged: { pa.detener(); if (pa.ruta !== "") espera.restart(); else espera.stop() }

    Timer {
        id: espera
        interval: 250
        onTriggered: pa.empezar()
    }

    function empezar() {
        var r = pa.ruta
        if (r === "") return
        if (/\.gif$/i.test(r)) {
            pa.reproduciendo = r
            gif.source = "file://" + r
            return
        }
        if (pa.optimizados[r] !== undefined) { pa.usar(r, pa.optimizados[r]); return }
        if (optimizar.running) return      // al terminar el que va, se vuelve a intentar
        optimizar.para = r
        optimizar.command = [pa.script, r, String(pa.anchoV), String(pa.altoV), String(pa.fps)]
        optimizar.running = true
    }

    function usar(r, copia) {
        if (r !== pa.ruta || copia === "") return
        pa.reproduciendo = r
        reproductor.source = "file://" + copia
        reproductor.play()
    }

    Process {
        id: optimizar
        property string para: ""
        stdout: SplitParser {
            onRead: linea => {
                var copia = Object.assign({}, pa.optimizados)
                if (linea.startsWith("LISTO ")) {
                    copia[optimizar.para] = linea.slice(6)
                    pa.optimizados = copia
                    pa.usar(optimizar.para, copia[optimizar.para])
                } else if (linea.startsWith("FALLO")) {
                    copia[optimizar.para] = ""
                    pa.optimizados = copia
                }
                // ORIGINAL: la copia se está creando; mientras, queda la imagen fija
            }
        }
        onRunningChanged: if (!running && pa.ruta !== "" && pa.reproduciendo !== pa.ruta) espera.restart()
    }

    MediaPlayer {
        id: reproductor
        loops: MediaPlayer.Infinite
        videoOutput: salida
        // Sin audioOutput: nunca suena
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.BufferedMedia || mediaStatus === MediaPlayer.BufferingMedia)
                primerFotograma.restart()
        }
        onErrorOccurred: (codigo, texto) => console.warn("galeria: error de vídeo:", texto)
    }
    // Da tiempo a que llegue el primer fotograma antes de mostrarlo (sin parpadeo negro)
    Timer {
        id: primerFotograma
        interval: 120
        onTriggered: if (pa.reproduciendo !== "") pa.listo = true
    }

    VideoOutput {
        id: salida
        anchors.fill: parent
        visible: !pa.esGif
        fillMode: VideoOutput.PreserveAspectCrop
    }

    AnimatedImage {
        id: gif
        anchors.fill: parent
        visible: pa.esGif
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        playing: source != ""
        onStatusChanged: if (status === Image.Ready && pa.esGif) pa.listo = true
    }

    function info() {
        return { ruta: pa.ruta, reproduciendo: pa.reproduciendo, listo: pa.listo,
            fuente: pa.esGif ? gif.source.toString() : reproductor.source.toString(),
            estado: reproductor.playbackState, optimizando: optimizar.running }
    }
}
