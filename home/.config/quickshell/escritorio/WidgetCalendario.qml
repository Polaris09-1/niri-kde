import Quickshell
import QtQuick

// Calendario: S = el día de hoy; M y L = el mes (con flechas para cambiarlo fuera del modo edición).
TarjetaWidget {
    id: w
    required property string fuente
    property string tam: "M"
    property var opciones: ({})
    property bool activo: true
    property bool interactivo: true
    readonly property bool usaTarjeta: true

    SystemClock { id: reloj; enabled: w.activo; precision: SystemClock.Minutes }
    readonly property date hoy: reloj.date
    readonly property int anioHoy: hoy.getFullYear()
    readonly property int mesHoy: hoy.getMonth()
    readonly property int diaHoy: hoy.getDate()
    property int desfase: 0                 // meses respecto al actual
    onDiaHoyChanged: desfase = 0
    readonly property date primero: new Date(anioHoy, mesHoy + desfase, 1)
    readonly property int primerDia: w.opciones.domingo === true ? 0 : 1
    readonly property var loc: Qt.locale("es_EC")
    function mayuscula(s) { return s.charAt(0).toUpperCase() + s.slice(1) }
    readonly property var cabeceras: {
        var l = []
        for (var i = 0; i < 7; i++) l.push(mayuscula(new Date(2023, 0, 1 + (primerDia + i) % 7).toLocaleDateString(loc, "ddd")).slice(0, 2))
        return l
    }
    readonly property var celdas: {
        var d0 = (primero.getDay() - primerDia + 7) % 7
        var l = []
        for (var i = 0; i < 42; i++) {
            var f = new Date(primero.getFullYear(), primero.getMonth(), 1 - d0 + i)
            l.push({ n: f.getDate(), delMes: f.getMonth() === primero.getMonth(),
                     esHoy: f.getDate() === diaHoy && f.getMonth() === mesHoy && f.getFullYear() === anioHoy })
        }
        return l
    }

    // ----- S: hoy -----
    Column {
        visible: w.tam === "S"
        anchors.centerIn: parent
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: w.mayuscula(w.hoy.toLocaleDateString(w.loc, "dddd"))
            font.family: w.fuente; font.pixelSize: 13; font.bold: true
            color: w.tema.primary
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: w.diaHoy
            font.family: w.fuente; font.pixelSize: 64; font.weight: Font.Light
            color: w.tema.surfaceText
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: w.mayuscula(w.hoy.toLocaleDateString(w.loc, "MMMM yyyy"))
            font.family: w.fuente; font.pixelSize: 11
            color: w.tema.surfaceText
            opacity: 0.8
        }
    }

    // ----- M y L: el mes -----
    Column {
        visible: w.tam !== "S"
        anchors.fill: parent
        spacing: 4
        readonly property real lado: Math.min(width / 7, (height - 62) / 6)

        Item {
            width: parent.width
            height: 28
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: w.mayuscula(w.primero.toLocaleDateString(w.loc, "MMMM yyyy"))
                font.family: w.fuente; font.pixelSize: w.tam === "L" ? 15 : 13; font.bold: true
                color: w.tema.surfaceText
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                visible: w.interactivo
                Repeater {
                    model: [ { g: 0xF0141, d: -1 }, { g: 0xF0142, d: 1 } ]
                    delegate: Rectangle {
                        id: fl
                        required property var modelData
                        width: 26; height: 26; radius: 13
                        color: Qt.rgba(w.tema.primary.r, w.tema.primary.g, w.tema.primary.b, zf.containsMouse ? 0.25 : 0)
                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(fl.modelData.g)
                            font.family: w.fuente; font.pixelSize: 16
                            color: w.tema.surfaceText
                        }
                        MouseArea {
                            id: zf
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: w.desfase += fl.modelData.d
                        }
                    }
                }
            }
        }
        Row {
            Repeater {
                model: w.cabeceras
                delegate: Text {
                    required property string modelData
                    width: parent.parent.lado
                    height: 20
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.family: w.fuente; font.pixelSize: 10; font.bold: true
                    color: w.tema.primary
                }
            }
        }
        Grid {
            columns: 7
            Repeater {
                model: w.celdas
                delegate: Item {
                    id: cd
                    required property var modelData
                    width: parent.parent.lado
                    height: width
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 4
                        height: width
                        radius: width / 2
                        color: cd.modelData.esHoy ? w.tema.primary : "transparent"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: cd.modelData.n
                        font.family: w.fuente; font.pixelSize: w.tam === "L" ? 14 : 12
                        font.bold: cd.modelData.esHoy
                        color: cd.modelData.esHoy ? w.tema.primaryText : w.tema.surfaceText
                        opacity: cd.modelData.delMes ? 1 : 0.35
                    }
                }
            }
        }
    }
}
