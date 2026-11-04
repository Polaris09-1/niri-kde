import Quickshell
import QtQuick
import QtQuick.Effects

// Reloj japonés del escritorio: día en kanji, hora, fecha y saludo (cada parte se puede ocultar, ver
// "opciones"). Decorativo: muestra la hora a propósito. "activo" en false lo detiene (una ventana tapa
// el escritorio). "nombre" es el del saludo si el usuario no pone otro.
Item {
    id: w

    required property var tema
    required property string fuente
    property string tam: "L"
    property bool activo: true
    property string nombre: "@NOMBRE@"
    property var opciones: ({})
    readonly property bool conKanji: w.opciones.kanji !== false
    readonly property bool conFecha: w.opciones.fecha !== false
    readonly property bool conSaludo: w.opciones.saludo !== false
    readonly property bool conTarjeta: w.opciones.tarjeta === true
    readonly property bool usaTarjeta: w.conTarjeta         // pide el desenfoque de niri
    readonly property bool h12: w.opciones.h12 === true

    // Tamaño del texto respecto al diseño original (L)
    property real e: w.tam === "S" ? 0.5 : w.tam === "M" ? 0.75 : 1
    Behavior on e { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    readonly property var kanji: ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]
    readonly property string horaMostrada: Qt.formatDateTime(reloj.date, "hh:mm:ss")   // para probar la pausa
    readonly property real altoContenido: contenido.implicitHeight
    readonly property real anchoContenido: contenido.implicitWidth

    SystemClock {
        id: reloj
        enabled: w.activo
        precision: SystemClock.Seconds
    }

    // Buenos días 5:00-11:59 · buenas tardes 12:00-18:59 · buenas noches 19:00-4:59
    function saludoDe(h) {
        if (h >= 5 && h < 12) return "Buenos días"
        if (h >= 12 && h < 19) return "Buenas tardes"
        return "Buenas noches"
    }

    function textoSaludo() {
        return w.saludoDe(reloj.date.getHours()) + ", " + (w.opciones.nombre || w.nombre)
    }

    function textoHora() {
        if (!w.h12) return Qt.formatDateTime(reloj.date, "hh")
        return String(reloj.date.getHours() % 12 || 12)
    }

    function fechaLarga() {
        var s = reloj.date.toLocaleDateString(Qt.locale("es_EC"), "dddd d 'de' MMMM")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    // Tarjeta opcional detrás del reloj
    Rectangle {
        anchors.fill: parent
        radius: 20
        color: Qt.rgba(w.tema.surface.r, w.tema.surface.g, w.tema.surface.b, 0.55)
        border.width: 1
        border.color: Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, 0.3)
        opacity: w.conTarjeta ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    Item {
        anchors.fill: parent

        // Aparece lento al iniciar sesión
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            NumberAnimation { duration: 1500; easing.type: Easing.OutCubic }
        }

        // Sombra para leerse sobre cualquier parte del fondo
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.85
            shadowBlur: 1.0
            shadowVerticalOffset: 3
        }

        Column {
            id: contenido
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: w.conTarjeta ? Math.max(14, (w.width - contenido.implicitWidth) / 2) : 14
            anchors.bottomMargin: w.conTarjeta ? Math.max(12, (w.height - contenido.implicitHeight) / 2) : 12
            spacing: 4 * w.e

            // Día de la semana en kanji y, con 12 h, a. m. / p. m.
            Row {
                anchors.right: parent.right
                visible: w.conKanji || w.h12
                spacing: 14 * w.e
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: w.h12
                    text: reloj.date.getHours() < 12 ? "a. m." : "p. m."
                    font.family: w.fuente
                    font.pixelSize: 22 * w.e
                    color: w.tema.primary
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: w.conKanji
                    text: w.kanji[reloj.date.getDay()]
                    font.pixelSize: 30 * w.e
                    font.letterSpacing: 10 * w.e
                    color: w.tema.surfaceText
                    opacity: 0.9
                }
            }

            // Hora gigante con dos puntos que laten
            Row {
                anchors.right: parent.right
                Text {
                    text: w.textoHora()
                    font.family: w.fuente
                    font.weight: Font.ExtraLight
                    font.pixelSize: 140 * w.e
                    color: w.tema.surfaceText
                }
                Text {
                    text: ":"
                    font.family: w.fuente
                    font.weight: Font.ExtraLight
                    font.pixelSize: 140 * w.e
                    color: w.tema.primary
                    opacity: reloj.date.getSeconds() % 2 === 0 ? 1 : 0.25
                    Behavior on opacity {
                        enabled: w.activo
                        NumberAnimation { duration: 500; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    text: Qt.formatDateTime(reloj.date, "mm")
                    font.family: w.fuente
                    font.weight: Font.ExtraLight
                    font.pixelSize: 140 * w.e
                    color: w.tema.surfaceText
                }
            }

            // Línea de acento
            Rectangle {
                visible: w.conFecha || w.conSaludo
                anchors.right: parent.right
                width: 140 * w.e
                height: Math.max(2, 3 * w.e)
                radius: 2
                color: w.tema.primary
            }

            Item { visible: w.conFecha || w.conSaludo; width: 1; height: 10 * w.e }

            // Fecha en español
            Text {
                visible: w.conFecha
                anchors.right: parent.right
                text: w.fechaLarga()
                font.family: w.fuente
                font.weight: Font.Light
                font.pixelSize: 28 * w.e
                color: w.tema.surfaceText
            }

            // Saludo según la hora
            Text {
                visible: w.conSaludo
                anchors.right: parent.right
                text: w.textoSaludo()
                font.family: w.fuente
                font.italic: true
                font.pixelSize: 20 * w.e
                color: w.tema.surfaceText
                opacity: 0.85
            }
        }
    }
}
