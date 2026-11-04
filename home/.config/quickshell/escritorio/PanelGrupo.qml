import Quickshell
import QtQuick

// Panel flotante de un grupo. Fuera del modo edición: un clic abre y clic derecho da el menú.
// En el modo edición: renombrar, sacar arrastrando fuera del panel y quitar con "−".
Rectangle {
    id: p

    required property var raiz
    required property var tema
    required property var elemento          // el Elemento del grupo

    readonly property var miembros: p.elemento ? (p.elemento.opciones.miembros || []) : []
    readonly property int columnas: Math.max(2, Math.min(4, Math.ceil(Math.sqrt(miembros.length))))
    readonly property int filas: Math.max(1, Math.ceil(miembros.length / columnas))
    readonly property int lado: 100
    readonly property string fuente: p.raiz.fuente

    width: columnas * lado + 24
    height: 46 + Math.min(filas, 4) * lado + 14
    radius: 20
    color: Qt.rgba(tema.surface.r, tema.surface.g, tema.surface.b, p.raiz.arrastreSobrePanel ? 0.75 : 0.6)
    border.width: p.raiz.arrastreSobrePanel ? 2 : 1.5
    border.color: Qt.rgba(tema.primary.r, tema.primary.g, tema.primary.b, p.raiz.arrastreSobrePanel ? 1 : 0.6)

    // Que un clic en el panel no llegue al hueco de debajo
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: p.raiz.soltarTexto() }

    // Título: en edición se puede renombrar
    Text {
        x: 14; y: 12
        width: p.width - 28
        visible: !p.raiz.editando
        elide: Text.ElideRight
        text: p.elemento ? p.elemento.titulo : ""
        font.family: p.fuente; font.pixelSize: 14; font.bold: true
        color: p.tema.primary
    }
    Rectangle {
        x: 12; y: 8
        width: p.width - 24
        height: 30
        radius: 10
        visible: p.raiz.editando
        color: Qt.rgba(p.tema.surfaceText.r, p.tema.surfaceText.g, p.tema.surfaceText.b, 0.08)
        border.width: 1
        border.color: nombreGrupo.activeFocus ? p.tema.primary : Qt.rgba(p.tema.primary.r, p.tema.primary.g, p.tema.primary.b, 0.35)
        TextInput {
            id: nombreGrupo
            objectName: "nombreGrupo"
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            autoScroll: activeFocus   // sin foco se ve el principio del nombre, no el final
            maximumLength: 30
            selectByMouse: true
            font.family: p.fuente; font.pixelSize: 13; font.bold: true
            color: p.tema.primary
            selectionColor: p.tema.primary
            selectedTextColor: p.tema.primaryText
            Component.onCompleted: text = p.elemento ? p.elemento.titulo : ""
            onTextEdited: if (text.trim() !== "") p.raiz.ponerOpcion(p.elemento.clave, "nombre", text.trim())
            Keys.onReturnPressed: p.raiz.soltarTexto()
            Keys.onEnterPressed: p.raiz.soltarTexto()
            Keys.onEscapePressed: p.raiz.soltarTexto()
        }
    }

    GridView {
        id: rejilla
        x: 12
        y: 46
        width: p.columnas * p.lado
        height: Math.min(p.filas, 4) * p.lado
        cellWidth: p.lado
        cellHeight: p.lado
        clip: true
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        model: p.miembros

        WheelHandler {
            enabled: rejilla.contentHeight > rejilla.height
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: ev => {
                rejilla.contentY = Math.max(0, Math.min(rejilla.contentHeight - rejilla.height, rejilla.contentY - ev.angleDelta.y))
            }
        }

        delegate: Item {
            id: celda
            required property string modelData
            width: p.lado
            height: p.lado
            opacity: p.raiz.miembroArrastrado === celda.modelData ? 0.3 : 1

            WidgetIcono {
                id: icono
                anchors.fill: parent
                tema: p.tema
                raiz: p.raiz
                fuente: p.fuente
                carpeta: p.raiz.carpeta
                archivo: celda.modelData
                tam: "S"
                unClic: true
                interactivo: !p.raiz.editando
                menuActual: p.raiz.menu
                onPideMenu: (datos, px, py) => {
                    var q = mapToItem(p.parent, px, py)
                    p.raiz.abrirMenu(datos, q.x, q.y)
                }
                onClicSimple: p.raiz.cerrarMenu()
                onAbierto: p.raiz.cerrarGrupo()
            }

            // Edición: arrastrar fuera del panel saca el icono del grupo
            MouseArea {
                id: zonaSacar
                anchors.fill: parent
                enabled: p.raiz.editando
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property point inicio
                onPressed: mouse => { inicio = Qt.point(mouse.x, mouse.y); p.raiz.soltarTexto() }
                onPositionChanged: mouse => {
                    if (!pressed) return
                    var q = mapToItem(p.parent, mouse.x, mouse.y)
                    if (p.raiz.miembroArrastrado === "") {
                        if (Math.abs(mouse.x - inicio.x) + Math.abs(mouse.y - inicio.y) < 5) return
                        p.raiz.empezarSacar(celda.modelData)
                    }
                    p.raiz.moverSacar(q.x, q.y)
                }
                onReleased: mouse => {
                    if (p.raiz.miembroArrastrado === "") return
                    var q = mapToItem(p.parent, mouse.x, mouse.y)
                    p.raiz.soltarSacar(q.x, q.y, p.elemento.clave)
                }
                onCanceled: p.raiz.cancelarSacar()
            }
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                z: 5
                visible: p.raiz.editando
                width: 22; height: 22; radius: 11
                color: zonaMenos.containsMouse ? "#e05555" : Qt.rgba(p.tema.surface.r, p.tema.surface.g, p.tema.surface.b, 0.95)
                border.color: Qt.rgba(p.tema.primary.r, p.tema.primary.g, p.tema.primary.b, 0.6)
                Text {
                    anchors.centerIn: parent
                    text: "−"
                    font.family: p.fuente; font.pixelSize: 14; font.bold: true
                    color: zonaMenos.containsMouse ? "white" : p.tema.surfaceText
                }
                MouseArea {
                    id: zonaMenos
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        var q = mapToItem(p.parent, mouse.x, mouse.y)
                        p.raiz.pedirQuitar(celda.modelData, q.x, q.y)
                    }
                }
            }
        }
    }
}
