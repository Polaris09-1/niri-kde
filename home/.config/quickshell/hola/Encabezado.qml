import QtQuick

// Encabezado de página: ← título ...controles a la derecha
Item {
    id: enc

    property var tema
    property string titulo: ""
    property string fuente: "JetBrainsMono Nerd Font"
    property bool conAtras: true
    default property alias derecha: filaDer.data
    signal atras()

    width: parent ? parent.width : 300
    height: 34

    Boton {
        id: btnAtras
        visible: enc.conAtras
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        tema: enc.tema
        icono: String.fromCodePoint(0xF004D)
        onClic: enc.atras()
    }

    Text {
        anchors.left: enc.conAtras ? btnAtras.right : parent.left
        anchors.leftMargin: enc.conAtras ? 6 : 0
        anchors.verticalCenter: parent.verticalCenter
        text: enc.titulo
        font.family: enc.fuente
        font.pixelSize: 16
        font.bold: true
        color: enc.tema.surfaceText
    }

    Row {
        id: filaDer
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
    }
}
