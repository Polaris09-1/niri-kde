import QtQuick

// Slider redondeado: arrastra, haz clic o usa la rueda. valor va de 0 a 1.
// - movido(v): en cada movimiento (en vivo, mientras arrastras)
// - soltado(v): al soltar, con el valor final exacto
// - vista: lo que se dibuja (sigue al mouse mientras arrastras)
Item {
    id: d

    property var tema
    property real valor: 0
    readonly property bool arrastrando: ma.pressed
    property real local: 0
    readonly property real vista: Math.max(0, Math.min(1, ma.pressed ? d.local : d.valor))

    signal movido(real v)
    signal soltado(real v)

    implicitHeight: 24

    function limitar(v) { return Math.max(0, Math.min(1, v)) }

    function arrastrar(v) {
        d.local = d.limitar(v)
        d.movido(d.local)
    }

    Rectangle {
        id: pista
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 8
        radius: 4
        color: Qt.rgba(d.tema.surfaceText.r, d.tema.surfaceText.g, d.tema.surfaceText.b, 0.15)

        Rectangle {
            width: Math.max(pista.height, pista.width * d.vista)
            height: parent.height
            radius: 4
            color: d.tema.primary
            Behavior on width {
                enabled: !ma.pressed
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }
    }

    Rectangle {
        width: ma.pressed || ma.containsMouse ? 20 : 16
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: (d.width - width) * d.vista
        color: d.tema.primary
        border.color: d.tema.surface
        border.width: 3
        Behavior on width {
            NumberAnimation { duration: 140; easing.type: Easing.OutBack }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: m => d.arrastrar(m.x / width)
        onPositionChanged: m => { if (pressed) d.arrastrar(m.x / width) }
        onReleased: m => d.soltado(d.limitar(m.x / width))
        onCanceled: d.soltado(d.local)
        onWheel: w => {
            var v = d.limitar(d.valor + (w.angleDelta.y > 0 ? 0.05 : -0.05))
            d.movido(v)
            d.soltado(v)
        }
    }
}
