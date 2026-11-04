import QtQuick

// Una opción: título y ayuda a la izquierda, su control a la derecha.
Rectangle {
    id: f

    property var op
    property var raiz

    readonly property var valor: f.raiz.valor(f.op.id)
    readonly property bool resaltada: f.raiz.resaltada === f.op.id

    width: parent ? parent.width : 400
    height: Math.max(textos.implicitHeight, control.height) + 22
    radius: 14
    color: f.raiz.alfa(f.raiz.tema.primary, f.resaltada ? 0.28 : 0.07)
    border.color: f.resaltada ? f.raiz.tema.primary : "transparent"
    border.width: 1.5
    Behavior on color { ColorAnimation { duration: 200 } }

    Component.onCompleted: f.raiz.registrarFila(f.op.id, f)
    Component.onDestruction: f.raiz.quitarFila(f.op.id, f)

    Column {
        id: textos
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 28 - control.width - 16
        spacing: 2
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: f.op.t
            font.family: f.raiz.fuente
            font.pixelSize: 13
            color: f.raiz.tema.surfaceText
        }
        Text {
            visible: !!f.op.a
            width: parent.width
            wrapMode: Text.Wrap
            text: f.op.a || ""
            font.family: f.raiz.fuente
            font.pixelSize: 10
            color: f.raiz.alfa(f.raiz.tema.surfaceText, 0.62)
        }
    }

    Item {
        id: control
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: f.op.tipo === "interruptor" ? 46 : f.op.tipo === "deslizador" ? 270 : f.op.tipo === "texto" ? 210 : 260
        height: f.op.tipo === "interruptor" ? 26 : f.op.tipo === "elegir" ? chips.implicitHeight : f.op.tipo === "texto" ? 34 : 24

        Interruptor {
            visible: f.op.tipo === "interruptor"
            anchors.fill: parent
            tema: f.raiz.tema
            activo: f.valor === true
            ocupado: f.raiz.aplicando
            onCambiado: v => f.raiz.cambiar(f.op.id, v)
        }

        // Deslizador: se aplica al soltar; mientras tanto solo cambia el número
        Item {
            visible: f.op.tipo === "deslizador"
            anchors.fill: parent
            readonly property real min: f.op.min === undefined ? 0 : f.op.min
            readonly property real max: f.op.max === undefined ? 1 : f.op.max
            readonly property real paso: f.op.paso || 1
            function aValor(p) {
                var v = min + Math.round(p * (max - min) / paso) * paso
                return Number(Math.max(min, Math.min(max, v)).toFixed(3))
            }
            Deslizador {
                id: barraValor
                anchors.left: parent.left
                anchors.right: numero.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                tema: f.raiz.tema
                conRueda: false      // desplazar la página con el cursor encima no debe cambiar el valor
                valor: typeof f.valor === "number" ? (f.valor - parent.min) / (parent.max - parent.min) : 0
                onSoltado: v => f.raiz.cambiar(f.op.id, parent.aValor(v))
            }
            Text {
                id: numero
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 58
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                readonly property real mostrado: barraValor.arrastrando ? parent.aValor(barraValor.vista) : f.valor
                text: mostrado === 0 && f.op.cero ? f.op.cero : mostrado + (f.op.unidad || "")
                font.family: f.raiz.fuente
                font.pixelSize: 11
                color: f.raiz.tema.surfaceText
            }
        }

        Row {
            id: chips
            visible: f.op.tipo === "elegir"
            anchors.right: parent.right
            spacing: 6
            Repeater {
                model: f.op.tipo === "elegir" ? f.op.lista : []
                delegate: Chip {
                    required property var modelData
                    s: f.raiz
                    tema: f.raiz.tema
                    texto: modelData.t
                    elegido: f.valor === modelData.v
                    onClic: f.raiz.cambiar(f.op.id, modelData.v)
                }
            }
        }

        // Texto: se aplica con Enter o al salir del campo
        Rectangle {
            visible: f.op.tipo === "texto"
            anchors.fill: parent
            radius: 10
            color: f.raiz.alfa(f.raiz.tema.surfaceText, 0.07)
            border.width: 1
            border.color: campo.activeFocus ? f.raiz.tema.primary : f.raiz.alfa(f.raiz.tema.primary, 0.35)
            TextInput {
                id: campo
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                selectByMouse: true
                maximumLength: 120
                font.family: f.raiz.fuente
                font.pixelSize: 12
                color: f.raiz.tema.surfaceText
                selectionColor: f.raiz.tema.primary
                selectedTextColor: f.raiz.tema.primaryText
                text: typeof f.valor === "string" ? f.valor : ""
                function enviar() {
                    var t = campo.text.trim()
                    if (t !== f.valor) f.raiz.cambiar(f.op.id, t)
                }
                onAccepted: { campo.enviar(); f.raiz.soltarFoco() }
                onActiveFocusChanged: if (!activeFocus) campo.enviar()
                Keys.onEscapePressed: { campo.text = f.valor; f.raiz.soltarFoco() }
            }
            Text {
                visible: campo.text === ""
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: f.op.ejemplo || ""
                font.family: f.raiz.fuente
                font.pixelSize: 12
                color: f.raiz.alfa(f.raiz.tema.surfaceText, 0.4)
            }
        }
    }
}
