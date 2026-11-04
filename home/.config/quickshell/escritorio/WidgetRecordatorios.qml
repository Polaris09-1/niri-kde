import Quickshell
import Quickshell.Io
import QtQuick

// Recordatorios locales: lista con casillas, en recordatorios.json (no sube al repo).
// Para escribir, la capa del escritorio pide el teclado solo mientras el campo está en uso.
TarjetaWidget {
    id: w
    required property string fuente
    required property var raiz
    property string tam: "M"
    property var opciones: ({})
    property bool interactivo: true
    readonly property bool usaTarjeta: true
    readonly property bool conCompletados: w.opciones.completados !== false

    property var lista: []                  // [{ id, texto, hecho }]
    property var confirmando: null          // id pendiente de confirmar el borrado
    readonly property var visibles: w.conCompletados ? w.lista : w.lista.filter(r => !r.hecho)
    readonly property int pendientes: w.lista.filter(r => !r.hecho).length

    function guardar() { archivo.setText(JSON.stringify(w.lista, null, 1) + "\n") }
    function anadir(t) {
        var texto = t.trim()
        if (texto === "") return
        w.lista = w.lista.concat([{ id: Date.now(), texto: texto, hecho: false }])
        w.guardar()
    }
    function alternar(id) {
        w.lista = w.lista.map(r => r.id === id ? { id: r.id, texto: r.texto, hecho: !r.hecho } : r)
        w.guardar()
    }
    function borrar(id) {
        w.lista = w.lista.filter(r => r.id !== id)
        w.confirmando = null
        w.guardar()
    }
    function soltar() {
        if (!campo.activeFocus) return
        w.raiz.escribiendo = false
        w.raiz.soltarTexto()
    }

    FileView {
        id: archivo
        path: Quickshell.env("HOME") + "/.config/quickshell/escritorio/recordatorios.json"
        printErrors: false
        onLoaded: {
            try { var l = JSON.parse(text()); if (Array.isArray(l)) w.lista = l }
            catch (e) { console.warn("recordatorios: el archivo no se pudo leer") }
        }
    }
    Timer { id: cancelarBorrado; interval: 3000; onTriggered: w.confirmando = null }

    // Si el cursor sale del widget, se suelta el teclado (lo escrito se queda en el campo)
    HoverHandler {
        onHoveredChanged: hovered ? perderTeclado.stop() : perderTeclado.restart()
    }
    Timer { id: perderTeclado; interval: 700; onTriggered: w.soltar() }

    Item {
        id: cabecera
        width: parent.width
        height: 24
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Recordatorios"
            font.family: w.fuente; font.pixelSize: 13; font.bold: true
            color: w.tema.surfaceText
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: w.pendientes
            font.family: w.fuente; font.pixelSize: 13; font.bold: true
            color: w.tema.primary
        }
    }

    ListView {
        id: vista
        anchors.top: cabecera.bottom
        anchors.topMargin: 6
        anchors.bottom: pieCampo.top
        anchors.bottomMargin: 8
        width: parent.width
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        interactive: w.interactivo
        model: w.visibles
        delegate: Item {
            id: fila
            required property var modelData
            width: vista.width
            height: Math.max(28, textoFila.implicitHeight + 8)
            readonly property bool confirmar: w.confirmando === fila.modelData.id

            Rectangle {
                id: casilla
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18; radius: 9
                color: fila.modelData.hecho ? w.tema.primary : "transparent"
                border.width: 1.5
                border.color: w.tema.primary
                Text {
                    anchors.centerIn: parent
                    visible: fila.modelData.hecho
                    text: "✓"
                    font.pixelSize: 11; font.bold: true
                    color: w.tema.primaryText
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -5
                    enabled: w.interactivo
                    cursorShape: Qt.PointingHandCursor
                    onClicked: w.alternar(fila.modelData.id)
                }
            }
            Text {
                id: textoFila
                anchors.left: casilla.right
                anchors.leftMargin: 8
                anchors.right: botonBorrar.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: fila.modelData.texto
                font.family: w.fuente; font.pixelSize: 12
                font.strikeout: fila.modelData.hecho
                color: w.tema.surfaceText
                opacity: fila.modelData.hecho ? 0.55 : 1
            }
            // Primer clic: pregunta. Segundo clic, antes de 3 s: borra.
            Rectangle {
                id: botonBorrar
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: fila.confirmar ? 62 : 24
                height: 24
                radius: 12
                color: fila.confirmar ? "#e05555" : Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, zb.containsMouse ? 0.22 : 0)
                opacity: w.interactivo && (filaHover.hovered || fila.confirmar) ? 1 : 0
                Text {
                    anchors.centerIn: parent
                    text: fila.confirmar ? "¿Borrar?" : "✕"
                    font.family: w.fuente; font.pixelSize: 11; font.bold: fila.confirmar
                    color: fila.confirmar ? "white" : w.tema.surfaceText
                }
                MouseArea {
                    id: zb
                    anchors.fill: parent
                    enabled: w.interactivo
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (fila.confirmar) { cancelarBorrado.stop(); w.borrar(fila.modelData.id) }
                        else { w.confirmando = fila.modelData.id; cancelarBorrado.restart() }
                    }
                }
            }
            HoverHandler { id: filaHover }
        }
        Text {
            anchors.centerIn: parent
            visible: vista.count === 0
            text: "Nada pendiente"
            font.family: w.fuente; font.pixelSize: 12
            color: w.tema.surfaceText
            opacity: 0.6
        }
    }

    Rectangle {
        id: pieCampo
        anchors.bottom: parent.bottom
        width: parent.width
        height: 30
        radius: 10
        color: Qt.rgba(w.tema.surfaceText.r, w.tema.surfaceText.g, w.tema.surfaceText.b, 0.08)
        border.width: 1
        border.color: campo.activeFocus ? w.tema.primary : Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, 0.3)
        TextInput {
            id: campo
            objectName: "campoRecordatorio"
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            enabled: w.interactivo
            maximumLength: 120
            font.family: w.fuente; font.pixelSize: 12
            color: w.tema.surfaceText
            selectionColor: w.tema.primary
            selectedTextColor: w.tema.primaryText
            onActiveFocusChanged: if (activeFocus) w.raiz.escribiendo = true
            Keys.onReturnPressed: { w.anadir(text); text = "" }
            Keys.onEnterPressed: { w.anadir(text); text = "" }
            Keys.onEscapePressed: w.soltar()
        }
        Text {
            anchors.fill: parent
            anchors.leftMargin: 10
            verticalAlignment: Text.AlignVCenter
            visible: campo.text === ""
            text: "Añadir recordatorio…"
            font.family: w.fuente; font.pixelSize: 12
            color: w.tema.surfaceText
            opacity: 0.45
        }
    }
    // Para probar sin teclado
    function probarAnadir(t) { w.anadir(t) }
}
