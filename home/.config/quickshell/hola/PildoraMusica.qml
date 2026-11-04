import QtQuick
import Quickshell

// Píldora de "reproduciendo ahora", a la izquierda de la hora.
// Recogida: icono + ondas. Con el cursor encima: icono, título y botones. Clic: abre el calendario.
Rectangle {
    id: p

    property var rep                    // Reproduciendo.qml
    property var s                      // la barra (alfa, ic, fuente, tiempos)
    property var tema
    property real disponible: 320       // sitio hasta la isla de la izquierda
    property bool simEncima: false      // solo pruebas por IPC
    signal abrir()

    readonly property bool cursorDentro: sensor.hovered || p.simEncima
    property bool expandida: false
    onCursorDentroChanged: {
        if (p.cursorDentro) { retrasoCerrar.stop(); retrasoAbrir.restart() }
        else { retrasoAbrir.stop(); retrasoCerrar.restart() }
    }
    Timer { id: retrasoAbrir; interval: p.s.esperaAbrir; onTriggered: p.expandida = true }
    Timer { id: retrasoCerrar; interval: p.s.esperaCerrar; onTriggered: p.expandida = false }

    readonly property real anchoRecogido: 12 + 20 + 8 + ondas.implicitWidth + 14
    readonly property real anchoExpandido: Math.max(p.anchoRecogido, Math.min(320, p.disponible,
        10 + 20 + 8 + titulo.implicitWidth + 6 + botones.implicitWidth + 6))

    width: p.expandida ? p.anchoExpandido : p.anchoRecogido
    height: p.s.altoIsla
    radius: height / 2
    clip: true
    color: p.s.alfa(p.tema.surface, p.s.opacidadIsla)
    border.color: p.s.alfa(p.tema.primary, 0.5)
    border.width: 1.5
    opacity: p.rep.presente ? 1 : 0
    visible: opacity > 0.01
    transform: Translate {
        x: p.rep.presente ? 0 : 12
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }
    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: p.rep.presente ? 150 : 120 } }
    Behavior on color { ColorAnimation { duration: 200 } }

    HoverHandler { id: sensor }

    // Clic en la píldora (los botones van encima y no lo disparan)
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: p.abrir()
    }

    Image {
        id: iconoApp
        x: p.expandida ? 10 : 12
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        sourceSize.width: 40
        sourceSize.height: 40
        source: p.rep.icono
    }

    // Ondas: sin Behavior a propósito (repintarían a 144 Hz); cambian solo con cada dato de cava
    Row {
        id: ondas
        anchors.left: iconoApp.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        opacity: p.expandida ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Repeater {
            model: 5
            Rectangle {
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                radius: 1.5
                height: 4 + 14 * Math.max(0, Math.min(100, p.rep.niveles[index] || 0)) / 100
                color: p.tema.primary
            }
        }
    }

    Text {
        id: titulo
        anchors.left: iconoApp.right
        anchors.leftMargin: 8
        anchors.right: botones.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: p.rep.titulo
        textFormat: Text.PlainText
        font.family: p.s.fuente
        font.pixelSize: 12
        font.bold: true
        color: p.tema.surfaceText
        opacity: p.expandida ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    Row {
        id: botones
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        opacity: p.expandida ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Boton {
            tema: p.tema
            icono: p.s.ic(0xF04AE)
            enabled: !!p.rep.activo && p.rep.activo.canGoPrevious
            opacity: enabled ? 1 : 0.35
            onClic: p.rep.activo.previous()
        }
        Boton {
            tema: p.tema
            icono: p.rep.activo && p.rep.activo.isPlaying ? p.s.ic(0xF03E4) : p.s.ic(0xF040A)
            enabled: !!p.rep.activo && p.rep.activo.canTogglePlaying
            opacity: enabled ? 1 : 0.35
            onClic: p.rep.activo.togglePlaying()
        }
        Boton {
            tema: p.tema
            icono: p.s.ic(0xF04AD)
            enabled: !!p.rep.activo && p.rep.activo.canGoNext
            opacity: enabled ? 1 : 0.35
            onClic: p.rep.activo.next()
        }
    }
}
