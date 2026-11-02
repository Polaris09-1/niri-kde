import QtQuick
import Quickshell

// Página Energía: bloquear, suspender, cerrar sesión, reiniciar, apagar.
// Reiniciar y apagar piden confirmación con cuenta atrás de 5 s (cancelable);
// cerrar sesión también pide confirmación.
Item {
    id: e

    property var s
    property var tema
    property var limite          // LimiteCarga.qml (límite de carga de la batería)
    property bool activa: false
    signal atras()
    signal hecho()        // para cerrar el panel tras una acción

    implicitHeight: col.implicitHeight

    property string pendiente: ""     // "" | "apagar" | "reiniciar" | "salir"
    property int cuenta: 5

    onActivaChanged: if (!activa) e.cancelar()

    readonly property var acciones: [
        { id: "bloquear", icono: 0xF033E, texto: "Bloquear" },
        { id: "suspender", icono: 0xF0904, texto: "Suspender" },
        { id: "salir", icono: 0xF0343, texto: "Cerrar sesión" },
        { id: "reiniciar", icono: 0xF0709, texto: "Reiniciar" },
        { id: "apagar", icono: 0xF0425, texto: "Apagar" }
    ]

    function textoConfirmar() {
        if (e.pendiente === "apagar") return "El equipo se apagará en " + e.cuenta + " s"
        if (e.pendiente === "reiniciar") return "El equipo se reiniciará en " + e.cuenta + " s"
        if (e.pendiente === "salir") return "¿Cerrar la sesión? Se cerrarán todas tus ventanas"
        return ""
    }

    function pedir(id) {
        if (id === "bloquear" || id === "suspender") { e.ejecutar(id); return }
        e.pendiente = id
        e.cuenta = 5
        if (id !== "salir") reloj.restart()
    }

    function cancelar() {
        reloj.stop()
        e.pendiente = ""
    }

    function ejecutar(id) {
        reloj.stop()
        e.pendiente = ""
        e.hecho()
        var cmd = {
            bloquear: [Quickshell.env("HOME") + "/.local/bin/bloquear.sh"],   // módulo "bloqueo" (o swaylock si no corre)
            suspender: ["systemctl", "suspend"],
            salir: ["niri", "msg", "action", "quit", "--skip-confirmation"],
            reiniciar: ["systemctl", "reboot"],
            apagar: ["systemctl", "poweroff"]
        }[id]
        if (cmd) Quickshell.execDetached(cmd)
    }

    Timer {
        id: reloj
        interval: 1000
        repeat: true
        onTriggered: {
            e.cuenta--
            if (e.cuenta <= 0) e.ejecutar(e.pendiente)
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 12

        Encabezado {
            tema: e.tema
            titulo: "Energía"
            onAtras: e.atras()
        }

        Grid {
            columns: 3
            spacing: 8
            width: parent.width

            Repeater {
                model: e.acciones
                delegate: Rectangle {
                    id: t
                    required property var modelData
                    property bool peligro: t.modelData.id === "apagar" || t.modelData.id === "reiniciar"
                    property bool marcado: e.pendiente === t.modelData.id
                    width: (col.width - 16) / 3
                    height: 78
                    radius: 18
                    color: t.marcado ? (t.peligro ? Qt.rgba(1, 0.33, 0.33, 0.3) : e.s.alfa(e.tema.primary, 0.3))
                        : e.s.alfa(e.tema.primary, maT.containsMouse ? 0.18 : 0.08)
                    scale: maT.pressed ? 0.95 : 1
                    opacity: e.pendiente !== "" && !t.marcado ? 0.45 : 1
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: e.s.ic(t.modelData.icono)
                            font.family: e.s.fuente
                            font.pixelSize: 24
                            color: t.peligro ? "#ff8a80" : e.tema.primary
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: t.modelData.texto
                            font.family: e.s.fuente
                            font.pixelSize: 11
                            color: e.tema.surfaceText
                        }
                    }

                    MouseArea {
                        id: maT
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (e.pendiente === "") e.pedir(t.modelData.id)
                    }
                }
            }
        }

        // Batería: límite de carga (UPower) y salud
        Etiqueta {
            visible: !!(e.limite && e.limite.soportado)
            s: e.s
            tema: e.tema
            texto: "BATERÍA"
        }
        Rectangle {
            visible: !!(e.limite && e.limite.soportado)
            width: parent.width
            height: colLim.implicitHeight + 24
            radius: 16
            color: e.s.alfa(e.tema.primary, e.limite && e.limite.activo ? 0.16 : 0.07)
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            Column {
                id: colLim
                x: 14
                y: 12
                width: parent.width - 28
                spacing: 8
                Item {
                    width: parent.width
                    height: 34
                    Text {
                        id: icLim
                        anchors.verticalCenter: parent.verticalCenter
                        text: e.s.ic(0xF008A)
                        font.family: e.s.fuente
                        font.pixelSize: 22
                        color: e.tema.primary
                    }
                    Column {
                        anchors.left: icLim.right
                        anchors.leftMargin: 10
                        anchors.right: swLim.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: "Cargar solo hasta el " + (e.limite ? e.limite.fin : 80) + " %"
                            font.family: e.s.fuente
                            font.pixelSize: 12
                            font.bold: true
                            color: e.tema.surfaceText
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: e.limite && e.limite.activo
                                ? "Vuelve a cargar al bajar del " + e.limite.inicio + " %"
                                : "Carga completa hasta el 100 %"
                            font.family: e.s.fuente
                            font.pixelSize: 10
                            color: e.s.alfa(e.tema.surfaceText, 0.65)
                        }
                    }
                    Interruptor {
                        id: swLim
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        tema: e.tema
                        activo: e.limite ? e.limite.activo : false
                        ocupado: e.limite ? e.limite.ocupado : false
                        onCambiado: v => e.limite.poner(v)
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Alarga la vida de la batería si pasas mucho tiempo enchufado. Apágalo antes de un viaje para cargarla al 100 %."
                    font.family: e.s.fuente
                    font.pixelSize: 10
                    color: e.s.alfa(e.tema.surfaceText, 0.55)
                }
                Text {
                    visible: !!(e.limite && e.limite.salud >= 0)
                    text: "Salud de la batería: " + (e.limite ? e.limite.salud : 0) + " % de su capacidad original"
                    font.family: e.s.fuente
                    font.pixelSize: 10
                    color: e.s.alfa(e.tema.surfaceText, 0.75)
                }
                Text {
                    visible: !!(e.limite && e.limite.error !== "")
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: e.limite ? "No se pudo cambiar: " + e.limite.error : ""
                    font.family: e.s.fuente
                    font.pixelSize: 10
                    color: "#ff8a80"
                }
            }
        }

        // Confirmación
        Rectangle {
            visible: e.pendiente !== ""
            width: parent.width
            height: 92
            radius: 16
            color: e.pendiente === "salir" ? e.s.alfa(e.tema.primary, 0.12) : Qt.rgba(1, 0.33, 0.33, 0.15)

            Column {
                anchors.centerIn: parent
                spacing: 10
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: e.textoConfirmar()
                    font.family: e.s.fuente
                    font.pixelSize: 13
                    font.bold: true
                    color: e.tema.surfaceText
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    BotonTexto {
                        tema: e.tema
                        fuente: e.s.fuente
                        texto: "Cancelar"
                        lleno: true
                        onClic: e.cancelar()
                    }
                    BotonTexto {
                        tema: e.tema
                        fuente: e.s.fuente
                        peligro: true
                        texto: e.pendiente === "apagar" ? "Apagar ahora" : e.pendiente === "reiniciar" ? "Reiniciar ahora" : "Cerrar sesión"
                        onClic: e.ejecutar(e.pendiente)
                    }
                }
            }
        }
    }
}
