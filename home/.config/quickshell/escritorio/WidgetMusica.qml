import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Reproductor (MPRIS): usa el que esté sonando o, si ninguno, el primero. Sin reproductor, lo dice.
// La posición solo se pide mientras suena y el escritorio está a la vista.
TarjetaWidget {
    id: w
    required property string fuente
    property string tam: "M"
    property var opciones: ({})
    property bool activo: true
    property bool interactivo: true
    readonly property bool usaTarjeta: true
    readonly property bool conCaratula: w.opciones.caratula !== false
    readonly property bool conControles: w.opciones.controles !== false
    relleno: 12

    // El que suena; si ninguno, el último usado (al pausar no salta a otro y el botón sigue siendo suyo)
    property var ultimo: null
    readonly property var jugador: {
        var l = Mpris.players.values
        var u = l.indexOf(w.ultimo) >= 0 ? w.ultimo : null
        if (u && u.isPlaying) return u
        return l.find(j => j.isPlaying) || u || l[0] || null
    }
    onJugadorChanged: if (jugador !== ultimo) Qt.callLater(() => { w.ultimo = w.jugador })
    readonly property string titulo: w.jugador && w.jugador.trackTitle ? w.jugador.trackTitle : (w.jugador ? w.jugador.identity : "Sin reproducción")
    readonly property string artista: w.jugador ? (w.jugador.trackArtist || "") : ""
    readonly property string caratula: w.jugador ? (w.jugador.trackArtUrl || "") : ""
    readonly property bool conTiempo: !!w.jugador && w.jugador.positionSupported && w.jugador.lengthSupported && w.jugador.length > 0

    Timer {
        running: w.activo && !!w.jugador && w.jugador.isPlaying
        interval: 1000
        repeat: true
        onTriggered: w.jugador.positionChanged()
    }

    component Control: Rectangle {
        id: b
        property int glifo: 0
        property bool puede: true
        property bool fuerte: false
        signal pulsado()
        width: b.fuerte ? 34 : 28
        height: width
        radius: width / 2
        color: b.fuerte ? w.tema.primary : Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, zc.containsMouse ? 0.25 : 0)
        opacity: b.puede ? 1 : 0.35
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(b.glifo)
            font.family: w.fuente; font.pixelSize: b.fuerte ? 18 : 16
            color: b.fuerte ? w.tema.primaryText : w.tema.surfaceText
        }
        MouseArea {
            id: zc
            anchors.fill: parent
            enabled: w.interactivo && b.puede
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: b.pulsado()
        }
    }

    // Carátula: arriba en L; a la izquierda en S y M
    Rectangle {
        id: marco
        visible: w.conCaratula
        x: w.tam === "L" ? (parent.width - width) / 2 : 0
        anchors.verticalCenter: w.tam === "L" ? undefined : parent.verticalCenter
        width: w.tam === "L" ? 132 : parent.height
        height: width
        radius: 12
        clip: true
        color: Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, 0.16)
        Text {
            anchors.centerIn: parent
            visible: foto.status !== Image.Ready
            text: String.fromCodePoint(0xF075A)
            font.family: w.fuente; font.pixelSize: parent.width * 0.42
            color: w.tema.primary
        }
        Image {
            id: foto
            anchors.fill: parent
            source: w.caratula
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 264
        }
    }

    Column {
        id: textos
        x: w.tam !== "L" && w.conCaratula ? marco.width + 12 : 0
        y: w.tam === "L" ? (w.conCaratula ? marco.height + 10 : 12) : 0
        width: parent.width - x
        spacing: 2
        Text {
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: w.tam === "L" ? Text.AlignHCenter : Text.AlignLeft
            text: w.titulo
            font.family: w.fuente; font.pixelSize: 13; font.bold: true
            color: w.tema.surfaceText
        }
        Text {
            visible: w.artista !== "" && w.tam !== "S"
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: w.tam === "L" ? Text.AlignHCenter : Text.AlignLeft
            text: w.artista
            font.family: w.fuente; font.pixelSize: 11
            color: w.tema.surfaceText
            opacity: 0.75
        }
    }

    Column {
        x: textos.x
        width: textos.width
        anchors.bottom: parent.bottom
        spacing: 6
        // Progreso
        Rectangle {
            visible: w.conTiempo && w.tam !== "S"
            width: parent.width
            height: 3
            radius: 2
            color: Qt.rgba(w.tema.surfaceText.r, w.tema.surfaceText.g, w.tema.surfaceText.b, 0.2)
            Rectangle {
                height: parent.height
                radius: 2
                width: w.conTiempo ? parent.width * Math.min(1, w.jugador.position / w.jugador.length) : 0
                color: w.tema.primary
            }
        }
        Row {
            visible: w.conControles && !!w.jugador
            anchors.horizontalCenter: w.tam === "L" ? parent.horizontalCenter : undefined
            spacing: 6
            Control { visible: w.tam !== "S"; anchors.verticalCenter: parent.verticalCenter; glifo: 0xF04AE; puede: !!w.jugador && w.jugador.canGoPrevious; onPulsado: w.jugador.previous() }
            Control { anchors.verticalCenter: parent.verticalCenter; fuerte: true; glifo: w.jugador && w.jugador.isPlaying ? 0xF03E4 : 0xF040A; puede: !!w.jugador && w.jugador.canTogglePlaying; onPulsado: w.jugador.togglePlaying() }
            Control { visible: w.tam !== "S"; anchors.verticalCenter: parent.verticalCenter; glifo: 0xF04AD; puede: !!w.jugador && w.jugador.canGoNext; onPulsado: w.jugador.next() }
        }
    }
}
