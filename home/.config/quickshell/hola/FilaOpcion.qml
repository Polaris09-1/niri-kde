import QtQuick

// Fila elegible (tipo radio): icono, texto y check si está elegida
Rectangle {
    id: o

    property var s
    property var tema
    property string icono: ""
    property string texto: ""
    property string detalle: ""
    property bool elegido: false
    signal clic()

    height: o.detalle !== "" ? 46 : 38
    radius: 12
    color: o.elegido ? o.s.alfa(o.tema.primary, 0.2) : o.s.alfa(o.tema.primary, ma.containsMouse ? 0.12 : 0.05)
    Behavior on color {
        ColorAnimation { duration: 150 }
    }

    Text {
        id: ic
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        text: o.icono
        font.family: o.s.fuente
        font.pixelSize: 16
        color: o.tema.primary
    }

    Column {
        anchors.left: ic.right
        anchors.leftMargin: 10
        anchors.right: check.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: o.texto
            font.family: o.s.fuente
            font.pixelSize: 12
            font.bold: o.elegido
            color: o.tema.surfaceText
        }
        Text {
            visible: o.detalle !== ""
            width: parent.width
            elide: Text.ElideRight
            text: o.detalle
            font.family: o.s.fuente
            font.pixelSize: 10
            color: o.s.alfa(o.tema.surfaceText, 0.6)
        }
    }

    Text {
        id: check
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: o.elegido ? String.fromCodePoint(0xF012C) : ""
        font.family: o.s.fuente
        font.pixelSize: 15
        color: o.tema.primary
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: o.clic()
    }
}
