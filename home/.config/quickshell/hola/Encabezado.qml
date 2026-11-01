import QtQuick

// Encabezado de página: ← título ...controles a la derecha
Item {
    id: enc

    property var tema
    property string titulo: ""
    property string fuente: "JetBrainsMono Nerd Font"
    default property alias derecha: filaDer.data
    signal atras()

    width: parent ? parent.width : 300
    height: 34

    Boton {
        id: btnAtras
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        tema: enc.tema
        icono: String.fromCodePoint(0xF004D)
        onClic: enc.atras()
    }

    Text {
        anchors.left: btnAtras.right
        anchors.leftMargin: 6
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
