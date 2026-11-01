import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io

// Un fondo a pantalla completa: imagen, GIF animado o vídeo (en bucle, sin sonido).
// "listo" se pone a true cuando ya hay algo que pintar (para empezar la transición).
//
// Vídeo: no reproduce el archivo original tal cual (p. ej. 4K a 60 fps), sino una copia
// recortada al tamaño de la pantalla y limitada a "fps" (fondo-optimizar.sh, caché en
// ~/.cache/fondo/optimizados). La primera vez, mientras se crea la copia, se ve el original
// y al terminar se cambia a la copia sin parpadeo (en el mismo punto del vídeo).
Item {
    id: lienzo

    property string ruta: ""
    property bool pausado: false
    property bool listo: false
    property bool optimizar: true       // usar la copia ajustada a la pantalla
    property int fps: 30
    property string rutaVideo: ""       // archivo que se está reproduciendo de verdad (para "info")
    property string estadoVideo: ""     // optimizado | original | creando | fallo

    readonly property string tipo: {
        var r = ruta.toLowerCase()
        if (r === "") return ""
        if (/\.(mp4|webm|mkv|mov)$/.test(r)) return "video"
        if (/\.gif$/.test(r)) return "gif"
        return "imagen"
    }

    onRutaChanged: { listo = false; rutaVideo = ""; estadoVideo = "" }

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
            id: cv
            property int frente: 0          // capa que se ve: 1, 2 (0 = todavía ninguna)
            property string pedida: ""      // ruta del vídeo para el que se pidió la copia

            function capa(n) { return n === 1 ? v1 : v2 }

            // Carga un archivo en la capa de atrás; cuando tenga fotograma pasa al frente
            function cargar(archivo, mismaPosicion) {
                if (archivo === "") return
                var delante = cv.frente === 0 ? null : cv.capa(cv.frente)
                if (delante && delante.fuente === archivo) return
                var atras = cv.frente === 1 ? v2 : v1
                atras.posicionInicial = (mismaPosicion && delante) ? delante.posicion : 0
                atras.fuente = archivo
            }
            function alListo(n) {
                var anterior = cv.frente
                cv.frente = n
                lienzo.rutaVideo = cv.capa(n).fuente
                lienzo.listo = true
                if (anterior !== 0 && anterior !== n) cv.capa(anterior).fuente = ""   // libera el decodificador
            }

            function iniciar() {
                if (lienzo.ruta === "" || lienzo.width <= 0 || lienzo.height <= 0 || cv.pedida === lienzo.ruta) return
                cv.pedida = lienzo.ruta
                if (!lienzo.optimizar) { lienzo.estadoVideo = "original"; cv.cargar(lienzo.ruta, false); return }
                var r = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
                var w = Math.round(lienzo.width * r / 2) * 2
                var h = Math.round(lienzo.height * r / 2) * 2
                optimizador.command = [Quickshell.env("HOME") + "/.local/bin/fondo-optimizar.sh",
                                       lienzo.ruta, String(w), String(h), String(Math.max(1, lienzo.fps))]
                optimizador.running = true
            }
            Component.onCompleted: iniciar()
            Connections {
                target: lienzo
                function onWidthChanged() { cv.iniciar() }
                function onHeightChanged() { cv.iniciar() }
                function onRutaChanged() { cv.iniciar() }
            }

            Process {
                id: optimizador
                stdout: SplitParser {
                    onRead: linea => {
                        if (linea.startsWith("LISTO ")) {
                            var archivo = linea.substring(6)
                            lienzo.estadoVideo = archivo === lienzo.ruta ? "original" : "optimizado"
                            cv.cargar(archivo, true)
                        } else if (linea === "ORIGINAL") {
                            lienzo.estadoVideo = "creando"
                            cv.cargar(lienzo.ruta, false)
                        } else if (linea.startsWith("FALLO")) {
                            console.warn("fondo: no pude optimizar el vídeo:", linea)
                            lienzo.estadoVideo = "fallo"
                            cv.cargar(lienzo.ruta, false)
                        }
                    }
                }
            }

            CapaVideo {
                id: v1
                anchors.fill: parent
                z: cv.frente === 1 ? 1 : 0
                // La de atrás nunca se pausa mientras carga (necesita su primer fotograma)
                pausado: lienzo.pausado && cv.frente === 1
                onListoChanged: if (listo && fuente !== "") cv.alListo(1)
            }
            CapaVideo {
                id: v2
                anchors.fill: parent
                z: cv.frente === 2 ? 1 : 0
                pausado: lienzo.pausado && cv.frente === 2
                onListoChanged: if (listo && fuente !== "") cv.alListo(2)
            }
        }
    }
}
