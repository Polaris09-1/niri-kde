import Quickshell
import Quickshell.Wayland
import QtQuick

// Campanita discreta para los avisos normales que llegan con pantalla completa en el monitor enfocado:
// píldora arriba a la derecha que entra, se balancea, muestra el número y se va sola. Más avisos solo suben el número.
// Con el cursor encima se expande con el título del último y no se va; un clic abre el historial.
// Solo existe mientras se ve. El estado (número y título) está en Avisos.qml.
PanelWindow {
    id: w

    property var s
    property var tema
    property var av
    property int mostrarMs: 3000
    property string salida: ""
    property bool activa: false
    readonly property bool encima: sensor.hovered

    // 0 = escondida, 1 = a la vista. Entra en 150 ms y sale en 120, como los paneles y el OSD
    property real p: activa ? 1 : 0
    Behavior on p { NumberAnimation { duration: w.activa ? 150 : 120; easing.type: Easing.OutCubic } }

    screen: Principal.porNombre(w.salida) || Principal.pantalla
    visible: Principal.lista && p > 0.001
    anchors { top: true; right: true }
    margins.right: 10
    implicitWidth: 340
    implicitHeight: 110
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hola-campanita"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Coordenadas explícitas: solo la píldora recibe el cursor, el resto deja pasar los clics
    mask: Region { x: pildora.x; y: pildora.yFinal; width: pildora.width; height: pildora.height }

    Connections {
        target: w.av
        function onSonarCampanita() {
            if (!w.activa) {
                w.salida = w.s.salidaEnfocada
                w.activa = true
                balanceo.restart()
            } else {
                pulso.restart()      // ya está a la vista: no se repite, solo sube el número
            }
            ocultar.restart()
        }
        function onCallarPCChanged() { if (!w.av.callarPC) w.activa = false }
        function onEmergentesVisiblesChanged() { if (!w.av.emergentesVisibles) w.activa = false }
    }
    onEncimaChanged: encima ? ocultar.stop() : (w.activa ? ocultar.restart() : undefined)
    Timer { id: ocultar; interval: w.mostrarMs; onTriggered: w.activa = false }

    Rectangle {
        id: pildora
        // Con la barra bajada, debajo de ella
        readonly property real yFinal: w.s.barraEnfocada && w.s.barraEnfocada.barraRevelada ? w.s.altoIsla + 14 : 8
        readonly property real anchoRecogido: fila.implicitWidth + 24
        anchors.right: parent.right
        y: yFinal - (1 - w.p) * 10
        opacity: w.p
        height: 34
        radius: height / 2
        width: w.encima && titulo.text !== "" ? Math.min(w.width, anchoRecogido + 10 + medida.advanceWidth + 2) : anchoRecogido
        color: w.s.alfa(w.tema.surface, w.s.opacidadIsla)
        border.color: w.s.alfa(w.tema.primary, 0.5)
        border.width: 1.5
        clip: true
        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        HoverHandler { id: sensor; cursorShape: Qt.PointingHandCursor }
        MouseArea {
            anchors.fill: parent
            onClicked: {
                w.activa = false
                w.s.ignorarAbrirHasta = Date.now() + 800
                w.s.alternar("avisos", null, w.s.barraEnfocada)
            }
        }

        Row {
            id: fila
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            // Se balancea desde arriba, como si sonara
            Text {
                id: campana
                anchors.verticalCenter: parent.verticalCenter
                text: w.s.ic(0xF009A)
                font.family: w.s.fuente
                font.pixelSize: 16
                color: w.tema.primary
                transformOrigin: Item.Top
                SequentialAnimation {
                    id: balanceo
                    NumberAnimation { target: campana; property: "rotation"; to: 20; duration: 110; easing.type: Easing.OutSine }
                    NumberAnimation { target: campana; property: "rotation"; to: -16; duration: 170; easing.type: Easing.InOutSine }
                    NumberAnimation { target: campana; property: "rotation"; to: 11; duration: 150; easing.type: Easing.InOutSine }
                    NumberAnimation { target: campana; property: "rotation"; to: -6; duration: 130; easing.type: Easing.InOutSine }
                    NumberAnimation { target: campana; property: "rotation"; to: 0; duration: 110; easing.type: Easing.OutSine }
                }
            }
            Text {
                id: numero
                anchors.verticalCenter: parent.verticalCenter
                text: String(Math.min(w.av.nuevosPC, 99))
                font.family: w.s.fuente
                font.pixelSize: 13
                font.bold: true
                color: w.tema.surfaceText
                SequentialAnimation {
                    id: pulso
                    NumberAnimation { target: numero; property: "scale"; to: 1.3; duration: 90; easing.type: Easing.OutCubic }
                    NumberAnimation { target: numero; property: "scale"; to: 1; duration: 130; easing.type: Easing.InOutCubic }
                }
            }
        }

        // Se mide aparte: el ancho del título depende del de la píldora
        TextMetrics { id: medida; text: w.av.tituloPC; font: titulo.font }
        Text {
            id: titulo
            anchors.left: fila.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: w.av.tituloPC
            font.family: w.s.fuente
            font.pixelSize: 12
            font.bold: true
            color: w.tema.surfaceText
            opacity: w.encima ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }
}
