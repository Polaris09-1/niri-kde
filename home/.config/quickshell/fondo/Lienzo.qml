import QtQuick
import QtMultimedia

// Un fondo a pantalla completa: imagen, GIF animado o vídeo (en bucle, sin sonido).
// "listo" se pone a true cuando ya hay algo que pintar (para empezar la transición).
Item {
    id: lienzo

    property string ruta: ""
    property bool pausado: false
    property bool listo: false

    readonly property string tipo: {
        var r = ruta.toLowerCase()
        if (r === "") return ""
        if (/\.(mp4|webm|mkv|mov)$/.test(r)) return "video"
        if (/\.gif$/.test(r)) return "gif"
        return "imagen"
    }

    onRutaChanged: listo = false

    Loader {
        anchors.fill: parent
        sourceComponent: lienzo.tipo === "video" ? cVideo
                       : lienzo.tipo === "gif" ? cGif
                       : lienzo.tipo === "imagen" ? cImagen : null
    }

    Component {
        id: cImagen
        Image {
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: lienzo.width
            sourceSize.height: lienzo.height
            source: "file://" + lienzo.ruta
            onStatusChanged: if (status === Image.Ready || status === Image.Error) lienzo.listo = true
        }
    }

    Component {
        id: cGif
        AnimatedImage {
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            source: "file://" + lienzo.ruta
            paused: lienzo.pausado
            onStatusChanged: if (status === Image.Ready || status === Image.Error) lienzo.listo = true
        }
    }

    Component {
        id: cVideo
        Item {
            MediaPlayer {
                id: reproductor
                source: "file://" + lienzo.ruta
                loops: MediaPlayer.Infinite
                videoOutput: salida
                // Sin audioOutput: el fondo nunca suena
                onMediaStatusChanged: {
                    if (mediaStatus === MediaPlayer.BufferedMedia || mediaStatus === MediaPlayer.BufferingMedia)
                        esperaFotograma.restart()
                    else if (mediaStatus === MediaPlayer.InvalidMedia)
                        lienzo.listo = true
                }
                onErrorOccurred: (codigo, texto) => {
                    console.warn("fondo: error de vídeo:", texto)
                    lienzo.listo = true
                }
                Component.onCompleted: play()
            }
            // Da tiempo a que llegue el primer fotograma antes de la transición
            Timer {
                id: esperaFotograma
                interval: 120
                onTriggered: {
                    lienzo.listo = true
                    if (lienzo.pausado) reproductor.pause()
                }
            }
            Connections {
                target: lienzo
                function onPausadoChanged() {
                    if (lienzo.pausado) reproductor.pause()
                    else reproductor.play()
                }
            }
            VideoOutput {
                id: salida
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }
        }
    }
}
