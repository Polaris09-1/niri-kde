import QtQuick
import "arreglo.js" as Arreglo

// Mapa de monitores: arrástralos para ordenarlos. Un clic elige de cuál ver los ajustes.
// Al soltar se pega al lado más cercano de otro monitor, sin solapar; el orden real se prueba con "¿Conservar?".
Item {
    id: v

    property var raiz
    property var salidas: []         // solo las encendidas
    property string elegida: ""
    property string principal: ""    // id del principal
    signal elegir(string nombre)
    signal ordenado(var rects)       // todos, con su posición nueva

    height: 200

    readonly property var rects: v.salidas.map(o => ({ n: o.name, id: o.id, x: o.logical.x, y: o.logical.y, w: o.logical.width, h: o.logical.height }))
    readonly property real minX: v.rects.length ? Math.min.apply(null, v.rects.map(r => r.x)) : 0
    readonly property real minY: v.rects.length ? Math.min.apply(null, v.rects.map(r => r.y)) : 0
    readonly property real anchoTotal: v.rects.length ? Math.max.apply(null, v.rects.map(r => r.x + r.w)) - v.minX : 1
    readonly property real altoTotal: v.rects.length ? Math.max.apply(null, v.rects.map(r => r.y + r.h)) - v.minY : 1
    // Con margen para poder arrastrar a los lados
    readonly property real escala: Math.min((v.width - 80) / v.anchoTotal, (v.height - 40) / v.altoTotal, 0.14)
    readonly property real origenX: (v.width - v.anchoTotal * v.escala) / 2
    readonly property real origenY: (v.height - v.altoTotal * v.escala) / 2

    Repeater {
        model: v.rects
        delegate: Rectangle {
            id: mon
            required property var modelData
            readonly property bool actual: v.elegida === mon.modelData.n
            property real dx: 0
            property real dy: 0
            x: v.origenX + (mon.modelData.x - v.minX) * v.escala + mon.dx
            y: v.origenY + (mon.modelData.y - v.minY) * v.escala + mon.dy
            width: mon.modelData.w * v.escala
            height: mon.modelData.h * v.escala
            z: zona.pressed ? 2 : 1
            radius: 8
            clip: true
            color: v.raiz.alfa(v.raiz.tema.primary, mon.actual ? 0.34 : 0.14)
            border.width: mon.actual ? 2 : 1
            border.color: mon.actual ? v.raiz.tema.primary : v.raiz.alfa(v.raiz.tema.primary, 0.5)

            Column {
                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 2
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: mon.modelData.n
                    font.family: v.raiz.fuente
                    font.pixelSize: 12
                    font.bold: true
                    color: v.raiz.tema.surfaceText
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: mon.modelData.w + "×" + mon.modelData.h
                    font.family: v.raiz.fuente
                    font.pixelSize: 9
                    color: v.raiz.alfa(v.raiz.tema.surfaceText, 0.7)
                }
                Text {
                    visible: v.principal === mon.modelData.id && v.rects.length > 1
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: "Principal"
                    font.family: v.raiz.fuente
                    font.pixelSize: 9
                    font.bold: true
                    color: v.raiz.tema.primary
                }
            }

            MouseArea {
                id: zona
                anchors.fill: parent
                cursorShape: v.rects.length > 1 ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                preventStealing: true
                property real px: 0
                property real py: 0
                property bool movido: false
                onPressed: m => {
                    var p = mapToItem(v, m.x, m.y)
                    px = p.x; py = p.y; movido = false
                    v.elegir(mon.modelData.n)
                }
                onPositionChanged: m => {
                    if (v.rects.length < 2) return
                    var p = mapToItem(v, m.x, m.y)
                    mon.dx = p.x - px
                    mon.dy = p.y - py
                    if (Math.abs(mon.dx) + Math.abs(mon.dy) > 3) movido = true
                }
                onReleased: {
                    if (!movido) { mon.dx = 0; mon.dy = 0; return }
                    var r = { x: mon.modelData.x + mon.dx / v.escala, y: mon.modelData.y + mon.dy / v.escala, w: mon.modelData.w, h: mon.modelData.h }
                    var otros = v.rects.filter(o => o.n !== mon.modelData.n)
                    var c = Arreglo.colocar(r, otros, 80)
                    var todos = Arreglo.normalizar(otros.concat([Object.assign({}, mon.modelData, { x: Math.round(c.x), y: Math.round(c.y) })]))
                    mon.dx = 0
                    mon.dy = 0
                    v.ordenado(todos)
                }
                onCanceled: { mon.dx = 0; mon.dy = 0 }
            }
        }
    }
}
