import QtQuick

// Página Luz nocturna: interruptor, estado de ahora, cuándo (según el sol / siempre / apagada)
// y calidez (3000–5500 K). El trabajo lo hace LuzNocturna.qml (wlsunset).
Item {
    id: p

    property var s
    property var tema
    property var luz
    property bool activa: false
    signal atras()

    implicitHeight: col.implicitHeight

    readonly property string horario: p.luz.atardecer !== ""
        ? "Del atardecer (" + p.luz.atardecer + ") al amanecer (" + p.luz.amanecer + ")"
        : "Del atardecer al amanecer"

    function estadoAhora() {
        if (!p.luz.activa) return "Apagada"
        if (p.luz.previa) return "Vista previa · " + p.luz.temperatura + " K"
        if (p.luz.modo === "siempre") return "Encendida · " + p.luz.tempActual + " K"
        if (p.luz.calida) return p.luz.tempActual <= p.luz.temperatura + 50
            ? "Encendida · " + p.luz.tempActual + " K"
            : "Cambiando · " + p.luz.tempActual + " K"
        return "De día · luz normal"
    }
    function detalleAhora() {
        if (!p.luz.activa) return "La pantalla tiene sus colores normales"
        if (p.luz.modo === "siempre") return "Hasta que la apagues"
        if (p.luz.calida) return p.luz.amanecer !== "" ? "Vuelve a la normalidad al amanecer (" + p.luz.amanecer + ")" : ""
        return p.luz.atardecer !== "" ? "Se enciende sola al atardecer (" + p.luz.atardecer + ")" : "Se enciende sola al atardecer"
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        Encabezado {
            tema: p.tema
            titulo: "Luz nocturna"
            onAtras: p.atras()
            Interruptor {
                tema: p.tema
                activo: p.luz.activa
                onCambiado: p.luz.alternar()
            }
        }

        // Estado de ahora
        Rectangle {
            width: parent.width
            height: 62
            radius: 16
            color: p.s.alfa(p.tema.primary, p.luz.calida ? 0.2 : 0.08)
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            Text {
                id: icAhora
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                text: p.s.ic(p.luz.calida ? 0xF0594 : p.luz.activa ? 0xF059A : 0xF05A8)
                font.family: p.s.fuente
                font.pixelSize: 26
                color: p.tema.primary
            }
            Column {
                anchors.left: icAhora.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: p.estadoAhora()
                    font.family: p.s.fuente
                    font.pixelSize: 13
                    font.bold: true
                    color: p.tema.surfaceText
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: p.detalleAhora()
                    font.family: p.s.fuente
                    font.pixelSize: 10
                    color: p.s.alfa(p.tema.surfaceText, 0.65)
                }
            }
        }

        Etiqueta { s: p.s; tema: p.tema; texto: "CUÁNDO" }

        Repeater {
            model: [
                { id: "sol", icono: 0xF059A, texto: "Según el sol", detalle: p.horario },
                { id: "siempre", icono: 0xF0594, texto: "Siempre encendida", detalle: "Ahora mismo, de día y de noche" },
                { id: "apagada", icono: 0xF05A8, texto: "Apagada", detalle: "Colores normales todo el día" }
            ]
            delegate: FilaOpcion {
                required property var modelData
                width: col.width
                s: p.s
                tema: p.tema
                icono: p.s.ic(modelData.icono)
                texto: modelData.texto
                detalle: modelData.detalle
                elegido: p.luz.modo === modelData.id
                onClic: p.luz.ponerModo(modelData.id)
            }
        }

        Etiqueta { s: p.s; tema: p.tema; texto: "CALIDEZ" }

        // Más a la derecha = más cálida (menos luz azul). 5500 K … 3000 K
        Row {
            width: parent.width
            spacing: 10
            Text {
                id: icFria
                anchors.verticalCenter: parent.verticalCenter
                text: p.s.ic(0xF05A8)
                font.family: p.s.fuente
                font.pixelSize: 16
                color: p.s.alfa(p.tema.surfaceText, 0.6)
            }
            Deslizador {
                id: deslCalidez
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - icFria.width - icCalida.width - txtK.width - 30
                tema: p.tema
                valor: (5500 - p.luz.temperatura) / 2500
                onSoltado: v => p.luz.ponerTemperatura(5500 - v * 2500)
            }
            Text {
                id: icCalida
                anchors.verticalCenter: parent.verticalCenter
                text: p.s.ic(0xF0594)
                font.family: p.s.fuente
                font.pixelSize: 16
                color: p.tema.primary
            }
            Text {
                id: txtK
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                horizontalAlignment: Text.AlignRight
                text: (deslCalidez.arrastrando ? Math.round((5500 - deslCalidez.vista * 2500) / 100) * 100 : p.luz.temperatura) + " K"
                font.family: p.s.fuente
                font.pixelSize: 12
                color: p.tema.surfaceText
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            leftPadding: 4
            text: p.luz.modo === "sol" && !p.luz.calida
                ? "Al soltar verás la calidez 3 segundos, aunque sea de día"
                : "Recomendado: 4000 K. Menos kelvin = más cálida"
            font.family: p.s.fuente
            font.pixelSize: 10
            color: p.s.alfa(p.tema.surfaceText, 0.55)
        }
        Text {
            visible: p.luz.error !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            leftPadding: 4
            text: "wlsunset: " + p.luz.error
            font.family: p.s.fuente
            font.pixelSize: 10
            color: "#ff8a80"
        }
    }
}
