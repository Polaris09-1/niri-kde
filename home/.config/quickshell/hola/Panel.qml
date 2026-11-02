import QtQuick
import QtQuick.Effects

// Panel que nace del botón que lo abre y se estira hasta su tamaño final
// (estilo caelestia). Pon el contenido como hijo; se coloca en el tamaño final
// y la caja lo va "destapando" mientras crece.
Item {
    id: panel

    property var tema
    property bool abierto: false
    property rect origen: Qt.rect(0, 0, 0, 0)   // rectángulo del botón (coords. de pantalla)
    property real anchoFinal: 360
    property real altoFinal: 400
    property real arriba: 54                     // y final del panel
    property real margen: 10
    property real radioFinal: 22
    property real p: 0                           // 0 = botón, 1 = panel abierto
    readonly property bool vivo: p > 0.001
    // Cursor dentro de la caja (incluidos sus botones) y clic/arrastre en curso dentro de ella
    readonly property bool encima: vivo && sobreCaja.hovered
    readonly property bool pulsado: vivo && pulsacion.active
    default property alias contenido: interior.data
    // Una pulsación dentro de la caja (posición en la escena): la usa la barra para soltar el foco
    // de un campo de texto al hacer clic en otra cosa
    signal presion(point posicion)

    property real xFinal: Math.max(margen, Math.min(width - anchoFinal - margen,
        origen.x + origen.width / 2 - anchoFinal / 2))

    // Ya abierto, si cambia de botón/tamaño (p. ej. calendario <-> notificaciones),
    // la caja se desliza y se estira en vez de cerrarse y abrirse
    Behavior on xFinal {
        enabled: panel.p > 0.98
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
    Behavior on anchoFinal {
        enabled: panel.p > 0.98
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    function mezcla(a, b) { return a + (b - a) * p }

    onAbiertoChanged: {
        anim.stop()
        anim.to = abierto ? 1 : 0
        // Casi instantáneo: sin rebote (a esta velocidad se notaría como un tirón)
        anim.duration = abierto ? 150 : 120
        anim.easing.type = abierto ? Easing.OutCubic : Easing.InCubic
        anim.start()
    }

    NumberAnimation {
        id: anim
        target: panel
        property: "p"
    }

    visible: vivo

    // Sombra aparte: un layer sobre "caja" rompería su recorte (clip)
    Rectangle {
        x: caja.x
        y: caja.y
        width: caja.width
        height: caja.height
        radius: caja.radius
        color: panel.tema.surface
        opacity: Math.min(1, panel.p)
        layer.enabled: panel.vivo
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: 0.45
            shadowBlur: 0.8
            shadowVerticalOffset: 6
        }
    }

    Rectangle {
        id: caja
        x: panel.mezcla(panel.origen.x, panel.xFinal)
        y: panel.mezcla(panel.origen.y, panel.arriba)
        width: Math.max(1, panel.mezcla(panel.origen.width, panel.anchoFinal))
        height: Math.max(1, panel.mezcla(panel.origen.height, panel.altoFinal))
        radius: Math.max(0, panel.mezcla(panel.origen.height / 2, panel.radioFinal))
        color: Qt.rgba(panel.tema.surface.r, panel.tema.surface.g, panel.tema.surface.b, 0.94)
        border.color: Qt.rgba(panel.tema.primary.r, panel.tema.primary.g, panel.tema.primary.b, 0.5)
        border.width: 1.5
        clip: true

        // Traga los clics para que no cierren el panel
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onWheel: w => w.accepted = true
        }

        // Pasivo: no roba clics, solo avisa de que el cursor está aquí
        HoverHandler { id: sobreCaja }

        // El contenido se estira con la caja: nunca se sale de ella
        Item {
            id: interior
            width: panel.anchoFinal
            height: panel.altoFinal
            opacity: Math.max(0, Math.min(1, (panel.p - 0.45) / 0.45))
            transform: Scale {
                xScale: caja.width / panel.anchoFinal
                yScale: caja.height / panel.altoFinal
            }
        }

        // Pulsación/arrastre dentro de la caja. Va ENCIMA del contenido: Qt entrega la pulsación
        // de arriba abajo y un MouseArea que la acepta corta el reparto, así que debajo (como
        // estaba antes) nunca se enteraba. Un PointHandler solo toma una captura pasiva: el clic
        // sigue llegando al botón de debajo.
        Item {
            anchors.fill: parent
            z: 1000
            PointHandler {
                id: pulsacion
                onActiveChanged: if (active) panel.presion(pulsacion.point.scenePosition)
            }
        }
    }
}
