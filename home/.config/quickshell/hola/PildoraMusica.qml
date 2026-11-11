import QtQuick
import Quickshell

// Píldora de "reproduciendo ahora" como un tocadiscos en miniatura, a la izquierda de la hora.
// Recogida: solo el tocadiscos. Con el cursor encima: título y artista (si el reproductor los da; nunca el
// nombre de la app ni de la página) y botones. Clic fuera de los botones: enfoca la ventana de la app que
// suena (root.enfocarMusica en shell.qml); si no sabe cuál, nada. El calendario solo se abre con la hora.
// El vinilo gira mientras suena y frena al pausar; el brazo se apoya o se levanta. Las ondas de cava son el
// halo que late alrededor del vinilo. Todo en colores de matugen.
// Consumo: el giro avanza en pasos de 50 ms, al ritmo de los datos de cava, nunca a la frecuencia de la
// pantalla (un giro continuo a 144 Hz repintaría la barra sin parar). Parado = ningún temporizador.
Rectangle {
    id: p

    property var rep                    // Reproduciendo.qml
    property var s                      // la barra (alfa, ic, fuente, tiempos)
    property var tema
    property real disponible: 320       // sitio hasta la isla de la izquierda
    property bool simEncima: false      // solo pruebas por IPC
    property bool habilitada: true      // se puede apagar desde Ajustes
    signal abrir()

    readonly property bool cursorDentro: sensor.hovered || p.simEncima
    property bool expandida: false
    onCursorDentroChanged: {
        if (p.cursorDentro) { retrasoCerrar.stop(); retrasoAbrir.restart() }
        else { retrasoAbrir.stop(); retrasoCerrar.restart() }
    }
    Timer { id: retrasoAbrir; interval: p.s.esperaAbrir; onTriggered: p.expandida = true }
    Timer { id: retrasoCerrar; interval: p.s.esperaCerrar; onTriggered: p.expandida = false }

    readonly property bool suena: p.rep.sonando
    readonly property bool brazoApoyado: p.suena
    readonly property bool hayTexto: p.rep.cancion !== ""
    readonly property real anchoTexto: Math.max(titulo.implicitWidth, artista.visible ? artista.implicitWidth : 0)
    readonly property real anchoRecogido: 8 + disco.width + 8
    readonly property real anchoExpandido: Math.max(p.anchoRecogido, Math.min(320, p.disponible,
        8 + disco.width + (p.hayTexto ? 8 + p.anchoTexto : 0) + 6 + botones.implicitWidth + 6))

    width: p.expandida ? p.anchoExpandido : p.anchoRecogido
    height: p.s.altoIsla
    radius: height / 2
    clip: true
    color: p.s.alfa(p.tema.surface, p.s.opacidadIsla)
    border.color: p.s.alfa(p.tema.primary, 0.5)
    border.width: 1.5
    opacity: p.rep.presente && p.habilitada ? 1 : 0
    visible: opacity > 0.01
    transform: Translate {
        x: p.rep.presente && p.habilitada ? 0 : 12
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

    // ===== Giro del vinilo =====
    property real angulo: 0
    property real velocidad: 0          // grados por paso; 10 = unas 33 vueltas por minuto
    Timer {
        interval: 50
        repeat: true
        running: p.visible && !p.rep.pausarOndas && (p.suena || p.velocidad > 0)
        onTriggered: {
            var meta = p.suena ? 10 : 0
            // Arranca en ~0,5 s y frena en ~1 s, como un plato de verdad
            p.velocidad += (meta - p.velocidad) * (p.suena ? 0.25 : 0.12)
            if (!p.suena && p.velocidad < 0.05) p.velocidad = 0
            p.angulo = (p.angulo + p.velocidad) % 360
        }
    }

    // ===== Tocadiscos (30 × 30) =====
    Item {
        id: disco
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 30

        // Plato
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: p.s.alfa(p.tema.primary, 0.08)
            border.color: p.s.alfa(p.tema.primary, 0.25)
            border.width: 1
        }

        // Halo de cava: late con el sonido (cambia solo con cada dato, sin animaciones propias)
        Rectangle {
            readonly property real nivel: {
                var n = p.rep.niveles || []
                var suma = 0
                for (var i = 0; i < n.length; i++) suma += Math.max(0, Math.min(100, n[i] || 0))
                return n.length ? suma / n.length / 100 : 0
            }
            x: 2
            y: 3
            width: 24
            height: 24
            radius: 12
            color: "transparent"
            border.color: p.tema.primary
            border.width: 1.5
            visible: p.suena
            scale: 1 + 0.16 * nivel
            opacity: 0.12 + 0.6 * nivel
        }

        // Vinilo: surcos, un brillo y la etiqueta con su marca (para que se vea girar)
        Item {
            id: vinilo
            x: 3
            y: 4
            width: 22
            height: 22
            rotation: p.angulo

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.darker(p.tema.surface, 1.7)
                border.color: p.s.alfa(p.tema.surfaceText, 0.18)
                border.width: 1
            }
            Repeater {
                model: [16, 12]
                Rectangle {
                    required property var modelData
                    anchors.centerIn: parent
                    width: modelData
                    height: modelData
                    radius: modelData / 2
                    color: "transparent"
                    border.color: p.s.alfa(p.tema.primary, 0.22)
                    border.width: 0.8
                }
            }
            Rectangle {
                x: parent.width / 2 - 0.75
                y: 2.5
                width: 1.5
                height: 4.5
                radius: 0.75
                color: p.s.alfa(p.tema.surfaceText, 0.4)
            }
            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: p.tema.primary
                Rectangle {
                    x: 4.6
                    y: 1.6
                    width: 1.6
                    height: 1.6
                    radius: 0.8
                    color: p.tema.primaryText
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 2
                height: 2
                radius: 1
                color: Qt.darker(p.tema.surface, 1.7)
            }
        }

        // Brazo: gira desde su eje (arriba a la derecha); apoyado sobre los surcos mientras suena
        Item {
            x: 26
            y: 5
            width: 0
            height: 0
            rotation: p.brazoApoyado ? 28 : 0
            Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
            Rectangle {
                x: -0.9
                y: 0
                width: 1.8
                height: 15
                radius: 0.9
                antialiasing: true
                color: p.s.alfa(p.tema.surfaceText, 0.85)
            }
            Rectangle {
                x: -2
                y: 13
                width: 4
                height: 5
                radius: 1
                antialiasing: true
                color: p.tema.primary
            }
            Rectangle {
                x: -2.5
                y: -2.5
                width: 5
                height: 5
                radius: 2.5
                color: p.s.alfa(p.tema.surfaceText, 0.9)
            }
        }
    }

    // ===== Título y artista (solo expandida) =====
    Column {
        anchors.left: disco.right
        anchors.leftMargin: 8
        anchors.right: botones.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        opacity: p.expandida && p.hayTexto ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Text {
            id: titulo
            width: parent.width
            elide: Text.ElideRight
            text: p.rep.cancion
            textFormat: Text.PlainText
            font.family: p.s.fuente
            font.pixelSize: 12
            font.bold: true
            color: p.tema.surfaceText
        }
        Text {
            id: artista
            width: parent.width
            visible: text !== ""
            elide: Text.ElideRight
            text: p.rep.artista
            textFormat: Text.PlainText
            font.family: p.s.fuente
            font.pixelSize: 10
            color: p.s.alfa(p.tema.surfaceText, 0.65)
        }
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
