import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

Scope {
    id: root

    // ===== Ajustes =====
    property string nombre: "@NOMBRE@"
    property string fuente: "JetBrainsMono Nerd Font"
    property int margenDerecho: 90
    property int margenInferior: 110

    property var kanji: ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]

    Colors { id: tema }

    SystemClock {
        id: reloj
        precision: SystemClock.Seconds
    }

    function saludo() {
        var h = reloj.date.getHours()
        return h < 12 ? "Buenos días" : (h < 19 ? "Buenas tardes" : "Buenas noches")
    }

    function fechaLarga() {
        var s = reloj.date.toLocaleDateString(Qt.locale("es_EC"), "dddd d 'de' MMMM")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    PanelWindow {
        anchors {
            bottom: true
            right: true
        }
        margins {
            bottom: root.margenInferior
            right: root.margenDerecho
        }
        implicitWidth: 700
        implicitHeight: 420
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "reloj-escritorio"

        Item {
            anchors.fill: parent

            // Aparece lento al iniciar sesión
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity {
                NumberAnimation { duration: 1500; easing.type: Easing.OutCubic }
            }

            // Sombra para leerse sobre cualquier parte del fondo
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.85
                shadowBlur: 1.0
                shadowVerticalOffset: 3
            }

            Column {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 4

                // Día de la semana en kanji
                Text {
                    anchors.right: parent.right
                    text: root.kanji[reloj.date.getDay()]
                    font.pixelSize: 30
                    font.letterSpacing: 10
                    color: tema.surfaceText
                    opacity: 0.9
                }

                // Hora gigante con dos puntos que laten
                Row {
                    anchors.right: parent.right
                    Text {
                        text: Qt.formatDateTime(reloj.date, "hh")
                        font.family: root.fuente
                        font.weight: Font.ExtraLight
                        font.pixelSize: 140
                        color: tema.surfaceText
                    }
                    Text {
                        text: ":"
                        font.family: root.fuente
                        font.weight: Font.ExtraLight
                        font.pixelSize: 140
                        color: tema.primary
                        opacity: reloj.date.getSeconds() % 2 === 0 ? 1 : 0.25
                        Behavior on opacity {
                            NumberAnimation { duration: 500; easing.type: Easing.InOutSine }
                        }
                    }
                    Text {
                        text: Qt.formatDateTime(reloj.date, "mm")
                        font.family: root.fuente
                        font.weight: Font.ExtraLight
                        font.pixelSize: 140
                        color: tema.surfaceText
                    }
                }

                // Línea de acento
                Rectangle {
                    anchors.right: parent.right
                    width: 140
                    height: 3
                    radius: 2
                    color: tema.primary
                }

                Item { width: 1; height: 10 }

                // Fecha en español
                Text {
                    anchors.right: parent.right
                    text: root.fechaLarga()
                    font.family: root.fuente
                    font.weight: Font.Light
                    font.pixelSize: 28
                    color: tema.surfaceText
                }

                // Saludo según la hora
                Text {
                    anchors.right: parent.right
                    text: root.saludo() + ", " + root.nombre
                    font.family: root.fuente
                    font.italic: true
                    font.pixelSize: 20
                    color: tema.surfaceText
                    opacity: 0.85
                }
            }
        }
    }
}
