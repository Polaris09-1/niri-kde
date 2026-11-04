import QtQuick

// Botón con texto (píldora). lleno = color primario; peligro = rojo.
Rectangle {
    id: bt

    property var tema
    property string fuente: "JetBrainsMono Nerd Font"
    property string texto: ""
    property bool lleno: false
    property bool peligro: false
    property real anchoMax: 100000   // con un texto largo (p. ej. acciones de un aviso) recorta con "…"
    signal clic()

    width: txt.width + 24
    height: 32
    radius: 12
    color: bt.peligro ? (ma.containsMouse ? "#ff6b6b" : "#e05555")
        : bt.lleno ? bt.tema.primary
        : Qt.rgba(bt.tema.primary.r, bt.tema.primary.g, bt.tema.primary.b, ma.containsMouse ? 0.25 : 0.12)
    scale: ma.pressed ? 0.94 : 1
    Behavior on scale {
        NumberAnimation { duration: 120; easing.type: Easing.OutBack }
    }
    Behavior on color {
        ColorAnimation { duration: 150 }
    }

    Text {
        id: txt
        anchors.centerIn: parent
        width: Math.min(implicitWidth, Math.max(0, bt.anchoMax - 24))
        elide: Text.ElideRight
        text: bt.texto
        font.family: bt.fuente
        font.pixelSize: 12
        font.bold: bt.lleno || bt.peligro
        color: bt.peligro ? "white" : bt.lleno ? bt.tema.primaryText : bt.tema.surfaceText
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: bt.clic()
    }
}
