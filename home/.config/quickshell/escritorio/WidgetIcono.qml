import Quickshell
import QtQuick

// Un archivo de ~/Desktop. Doble clic abre (un clic dentro de un grupo); clic derecho pide el menú.
Item {
    id: w

    required property var tema
    required property string fuente
    required property string archivo         // nombre del archivo dentro de la carpeta
    required property string carpeta
    required property var raiz
    property bool unClic: false
    property string tam: "M"
    property var opciones: ({})
    property bool interactivo: true
    property var menuActual: null            // lo que tiene el menú abierto ahora (para el resalte)

    readonly property string ruta: w.carpeta + "/" + w.archivo
    readonly property var entrada: w.raiz.entradaDe(w.archivo)
    readonly property string nombreVisible: w.entrada ? w.entrada.name : w.archivo
    readonly property int ladoIcono: w.tam === "S" ? 40 : w.tam === "L" ? 72 : 52
    readonly property bool sobre: zona.containsMouse && w.interactivo
    readonly property bool conEtiqueta: w.opciones.etiqueta !== false

    signal pideMenu(var datos, real x, real y)
    signal clicSimple()
    signal abierto()

    function datos() {
        return { fileName: w.archivo, filePath: w.ruta, entrada: w.entrada, nombre: w.nombreVisible }
    }

    // Resalte suave al pasar el mouse (todo el icono + nombre)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 16
        color: Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, zona.pressed ? 0.3 : 0.16)
        border.color: Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, 0.45)
        border.width: 1
        opacity: w.sobre || (w.menuActual && w.menuActual.filePath === w.ruta) ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 7

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: w.ladoIcono
            height: w.ladoIcono
            sourceSize.width: 144
            sourceSize.height: 144
            source: w.raiz.fuenteIcono(w.archivo)
            scale: w.sobre ? 1.08 : 1
            Behavior on scale {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
        }

        // Nombre sobre una pastilla translúcida: se lee sobre cualquier fondo
        Rectangle {
            visible: w.conEtiqueta
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(nombre.implicitWidth, w.width - 22) + 14
            height: nombre.height + 6
            radius: 9
            color: Qt.rgba(w.tema.surface.r, w.tema.surface.g, w.tema.surface.b, w.sobre ? 0.85 : 0.62)
            border.color: Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, w.sobre ? 0.55 : 0.18)
            border.width: 1
            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            Text {
                id: nombre
                anchors.centerIn: parent
                width: Math.min(implicitWidth, w.width - 22)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
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

        // Doble clic: abrir
        onDoubleClicked: mouse => {
            if (mouse.button !== Qt.LeftButton || w.unClic) return
            w.raiz.abrirArchivo(w.archivo)
        }

        // Clic izquierdo: cierra el menú · Clic derecho: abre el menú de este icono
        onClicked: mouse => {
            if (mouse.button !== Qt.RightButton) {
                w.clicSimple()
                if (w.unClic) { w.raiz.abrirArchivo(w.archivo); w.abierto() }
                return
            }
            w.pideMenu(w.datos(), w.width - 8, w.height - 8)
        }
    }
}
