import QtQuick
import QtMultimedia

// Un vídeo en bucle, sin sonido, a pantalla completa (lo usa Lienzo.qml).
// "listo" = ya hay un fotograma que pintar. Al pausar, el decodificador se detiene
// (queda el último fotograma a la vista y no gasta CPU/GPU).
Item {
    id: capa

    property string fuente: ""
    property bool pausado: false
    property real posicionInicial: 0     // ms: para cambiar de archivo sin que el vídeo salte
    property bool listo: false
    readonly property real posicion: reproductor.position

    onFuenteChanged: listo = false

    MediaPlayer {
        id: reproductor
        source: capa.fuente !== "" ? "file://" + capa.fuente : ""
        loops: MediaPlayer.Infinite
        videoOutput: salida
        // Sin audioOutput: el fondo nunca suena
        onSourceChanged: if (source != "") play()
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia && capa.posicionInicial > 0)
                setPosition(capa.posicionInicial % Math.max(1, duration))
            if (mediaStatus === MediaPlayer.BufferedMedia || mediaStatus === MediaPlayer.BufferingMedia)
                esperaFotograma.restart()
            else if (mediaStatus === MediaPlayer.InvalidMedia)
                capa.listo = true
        }
        onErrorOccurred: (codigo, texto) => {
            console.warn("fondo: error de vídeo:", texto)
            capa.listo = true
        }
        Component.onCompleted: if (source != "") play()
    }
    // Da tiempo a que llegue el primer fotograma antes de mostrarlo
    Timer {
        id: esperaFotograma
        interval: 120
        onTriggered: {
            capa.listo = true
            if (capa.pausado) reproductor.pause()
        }
    }
    onPausadoChanged: {
        if (capa.fuente === "") return
        if (capa.pausado) { if (capa.listo) reproductor.pause() }
        else reproductor.play()
    }
    VideoOutput {
        id: salida
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }
}
