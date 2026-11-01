import QtQuick

// Opción pequeña elegible (tipo pastilla)
Rectangle {
    id: ch

    property var s
    property var tema
    property string texto: ""
    property bool elegido: false
    signal clic()

    width: t.implicitWidth + 20
    height: 28
    radius: 14
    color: ch.elegido ? ch.tema.primary : ch.s.alfa(ch.tema.primary, ma.containsMouse ? 0.2 : 0.1)
    Behavior on color {
        ColorAnimation { duration: 150 }
    }

    Text {
        id: t
        anchors.centerIn: parent
        text: ch.texto
        font.family: ch.s.fuente
        font.pixelSize: 11
        font.bold: ch.elegido
        color: ch.elegido ? ch.tema.primaryText : ch.tema.surfaceText
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ch.clic()
    }
}
