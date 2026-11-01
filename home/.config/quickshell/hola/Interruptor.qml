import QtQuick

// Interruptor encendido/apagado estilo Material 3
Item {
    id: sw

    property var tema
    property bool activo: false
    property bool ocupado: false      // gira suave mientras se aplica
    signal cambiado(bool v)

    implicitWidth: 46
    implicitHeight: 26

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: sw.activo ? sw.tema.primary : Qt.rgba(sw.tema.surfaceText.r, sw.tema.surfaceText.g, sw.tema.surfaceText.b, 0.15)
        border.color: sw.activo ? sw.tema.primary : Qt.rgba(sw.tema.surfaceText.r, sw.tema.surfaceText.g, sw.tema.surfaceText.b, 0.4)
        border.width: 1.5
        opacity: sw.ocupado ? 0.6 : 1
        Behavior on color {
            ColorAnimation { duration: 180 }
        }

        Rectangle {
            width: ma.pressed ? 22 : (sw.activo ? 20 : 14)
            height: ma.pressed ? 22 : (sw.activo ? 20 : 14)
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.activo ? parent.width - width - 3 : 5
            color: sw.activo ? sw.tema.primaryText : Qt.rgba(sw.tema.surfaceText.r, sw.tema.surfaceText.g, sw.tema.surfaceText.b, 0.7)
            Behavior on x {
                NumberAnimation { duration: 220; easing.type: Easing.OutBack }
            }
            Behavior on width {
                NumberAnimation { duration: 150 }
            }
            Behavior on height {
                NumberAnimation { duration: 150 }
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (!sw.ocupado) sw.cambiado(!sw.activo)
    }
}
