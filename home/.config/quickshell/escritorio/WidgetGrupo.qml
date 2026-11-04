import Quickshell
import QtQuick

// Grupo de iconos: miniatura con los 4 primeros y su nombre. El clic abre el panel flotante.
Item {
    id: w

    required property var tema
    required property var raiz
    required property string fuente
    required property string clave
    property string tam: "M"
    property var opciones: ({})
    property bool interactivo: true

    readonly property var miembros: w.opciones.miembros || []
    readonly property string nombreVisible: w.opciones.nombre || "Grupo"
    readonly property int lado: w.tam === "S" ? 52 : w.tam === "L" ? 92 : 68
    readonly property bool sobre: zona.containsMouse && w.interactivo
    readonly property bool conEtiqueta: w.opciones.etiqueta !== false

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 16
        color: Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, zona.pressed ? 0.3 : 0.16)
        border.color: Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, 0.45)
        border.width: 1
        opacity: w.sobre ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    Column {
        anchors.centerIn: parent
        spacing: 7

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: w.lado
            height: w.lado
            radius: w.lado * 0.26
            color: Qt.rgba(w.tema.surface.r, w.tema.surface.g, w.tema.surface.b, 0.62)
            border.width: 1
            border.color: Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, 0.35)
            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: w.lado * 0.06
                Repeater {
                    model: w.miembros.slice(0, 4)
                    delegate: Image {
                        required property string modelData
                        width: w.lado * 0.36
                        height: width
                        sourceSize.width: 72
                        sourceSize.height: 72
                        source: w.raiz.fuenteIcono(modelData)
                    }
                }
            }
        }

        Rectangle {
            visible: w.conEtiqueta
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(nombre.implicitWidth, w.width - 22) + 14
            height: nombre.height + 6
            radius: 9
            color: Qt.rgba(w.tema.surface.r, w.tema.surface.g, w.tema.surface.b, w.sobre ? 0.85 : 0.62)
            border.color: Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, w.sobre ? 0.55 : 0.18)
            border.width: 1
            Text {
                id: nombre
                anchors.centerIn: parent
                width: Math.min(implicitWidth, w.width - 22)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: w.nombreVisible
                font.family: w.fuente
                font.pixelSize: w.tam === "S" ? 10 : w.tam === "L" ? 12 : 11
                font.weight: Font.DemiBold
                color: w.tema.surfaceText
            }
        }
    }

    MouseArea {
        id: zona
        anchors.fill: parent
        enabled: w.interactivo
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                var p = mapToItem(w.parent ? w.parent.parent : w, mouse.x, mouse.y)
                w.raiz.abrirMenu({ grupo: w.clave, nombre: w.nombreVisible }, p.x, p.y)
            } else {
                w.raiz.alternarGrupo(w.clave)
            }
        }
    }
}
