import QtQuick

// Fila dentro de una tarjeta: título y detalle a la izquierda, controles a la derecha.
Item {
    id: f

    property var raiz
    property string t: ""
    property string a: ""
    default property alias controles: slot.data

    width: parent ? parent.width : 400
    height: Math.max(textos.implicitHeight, slot.implicitHeight, 26)

    Column {
        id: textos
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - (slot.width > 0 ? slot.width + 12 : 0)
        spacing: 2
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            text: f.t
            textFormat: Text.PlainText
            font.family: f.raiz.fuente
            font.pixelSize: 13
            color: f.raiz.tema.surfaceText
        }
        Text {
            visible: f.a !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: f.a
            textFormat: Text.PlainText
            font.family: f.raiz.fuente
            font.pixelSize: 10
            color: f.raiz.alfa(f.raiz.tema.surfaceText, 0.62)
        }
    }
    Row {
        id: slot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }
}
