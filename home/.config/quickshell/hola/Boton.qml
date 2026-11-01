import QtQuick

// Botón reutilizable de la barra: icono o imagen + texto, con hover y clic
Item {
    id: boton

    property var tema
    property string fuente: "JetBrainsMono Nerd Font"
    property string icono: ""
    property string imagen: ""
    property string texto: ""
    property color colorIcono: tema ? tema.primary : "white"
    property int anchoMaxTexto: 200
    property bool activo: false          // fondo marcado (p. ej. su panel está abierto)
    readonly property bool encima: area.containsMouse

    signal clic()
    signal clicDerecho()
    signal rueda(int delta)

    implicitWidth: fila.implicitWidth + 16
    implicitHeight: 28

    // Resalte al pasar el mouse
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: boton.tema ? boton.tema.primary : "white"
        opacity: area.pressed ? 0.35 : boton.activo ? (area.containsMouse ? 0.32 : 0.25) : area.containsMouse ? 0.18 : 0
        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
    }

    Row {
        id: fila
        anchors.centerIn: parent
        spacing: 6
        scale: area.pressed ? 0.9 : 1
        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutBack }
        }

        Image {
            anchors.verticalCenter: parent.verticalCenter
            visible: boton.imagen !== ""
            width: 18
            height: 18
            sourceSize.width: 36
            sourceSize.height: 36
            source: boton.imagen
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: boton.icono !== ""
            text: boton.icono
            font.family: boton.fuente
            font.pixelSize: 15
            color: boton.colorIcono
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: boton.texto !== ""
            width: Math.min(implicitWidth, boton.anchoMaxTexto)
            elide: Text.ElideRight
            text: boton.texto
            font.family: boton.fuente
            font.pixelSize: 13
            color: boton.tema ? boton.tema.surfaceText : "white"
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) boton.clicDerecho()
            else boton.clic()
        }
        onWheel: wheel => boton.rueda(wheel.angleDelta.y)
    }
}
