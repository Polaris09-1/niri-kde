import QtQuick
import Quickshell
import Quickshell.Io

// Página Sistema: CPU, RAM, temperatura y procesos que más consumen,
// con opción de cerrar uno (pide confirmación; envía SIGTERM).
Item {
    id: p

    property var s
    property var tema
    property bool activa: false
    signal atras()

    implicitHeight: col.implicitHeight

    property var procesos: []         // {pid, usuario, cpu, mem, nombre}
    property int confirmar: -1        // pid pendiente de confirmar
    property string mensaje: ""
    property bool mensajeError: false
    property string usuario: Quickshell.env("USER")

    onActivaChanged: {
        p.confirmar = -1
        p.mensaje = ""
        if (activa) pTop.running = true
    }

    Timer {
        interval: 2500
        running: p.activa && p.confirmar < 0
        repeat: true
        onTriggered: if (!pTop.running) pTop.running = true
    }

    // Dos pasadas de top: la segunda mide el consumo actual (no el promedio desde que arrancó)
    Process {
        id: pTop
        command: ["sh", "-c", "LC_ALL=C top -b -n 2 -d 0.6 -w 512 -o %CPU | awk '/^ *PID /{n++; next} n==2 && NF>=12 {print $1\"\\t\"$2\"\\t\"$9\"\\t\"$10\"\\t\"$12}' | head -8"]
        stdout: StdioCollector {
            onStreamFinished: {
                p.procesos = text.trim().split("\n").filter(l => l !== "").map(l => {
                    var c = l.split("\t")
                    return { pid: parseInt(c[0]), usuario: c[1], cpu: parseFloat(c[2]), mem: parseFloat(c[3]), nombre: c[4] }
                })
            }
        }
    }

    Process {
        id: pKill
        property string nombre: ""
        stderr: StdioCollector { id: errKill }
        onExited: code => {
            if (code === 0) {
                p.mensaje = "Se cerró " + pKill.nombre
                p.mensajeError = false
            } else {
                p.mensajeError = true
                p.mensaje = /not permitted/i.test(errKill.text)
                    ? "No tienes permiso para cerrar " + pKill.nombre + " (es del sistema)"
                    : /no such process/i.test(errKill.text) ? pKill.nombre + " ya se había cerrado"
                    : "No se pudo cerrar " + pKill.nombre
            }
            pTop.running = true
        }
    }

    function cerrarProceso(pr) {
        p.confirmar = -1
        pKill.nombre = pr.nombre
        pKill.command = ["kill", "-TERM", String(pr.pid)]
        pKill.running = true
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        Encabezado {
            tema: p.tema
            titulo: "Sistema"
            onAtras: p.atras()
        }

        // Medidores
        Row {
            width: parent.width
            spacing: 10
            Repeater {
                model: [
                    { icono: 0xF0EE0, nombre: "CPU", valor: p.s.cpu, texto: p.s.cpu + "%" },
                    { icono: 0xF035B, nombre: "RAM", valor: p.s.ram, texto: p.s.ram + "%" },
                    { icono: 0xF2C9, nombre: "Temperatura", valor: p.s.temp, texto: p.s.temp + "°C" }
                ]
                delegate: Rectangle {
                    id: med
                    required property var modelData
                    property bool alerta: med.modelData.valor >= 85
                    width: (col.width - 20) / 3
                    height: 70
                    radius: 14
                    color: p.s.alfa(p.tema.primary, 0.1)
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 20
                        spacing: 5
                        Row {
                            spacing: 6
                            Text {
                                text: p.s.ic(med.modelData.icono)
                                font.family: p.s.fuente
                                font.pixelSize: 14
                                color: med.alerta ? "#ff5555" : p.tema.primary
                            }
                            Text {
                                text: med.modelData.texto
                                font.family: p.s.fuente
                                font.pixelSize: 14
                                font.bold: true
                                color: p.tema.surfaceText
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: 6
                            radius: 3
                            color: p.s.alfa(p.tema.surfaceText, 0.15)
                            Rectangle {
                                width: Math.max(6, parent.width * Math.min(100, med.modelData.valor) / 100)
                                height: parent.height
                                radius: 3
                                color: med.alerta ? "#ff5555" : p.tema.primary
                                Behavior on width {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                        Text {
                            text: med.modelData.nombre
                            font.family: p.s.fuente
                            font.pixelSize: 10
                            color: p.s.alfa(p.tema.surfaceText, 0.6)
                        }
                    }
                }
            }
        }

        // Aviso
        Rectangle {
            visible: p.mensaje !== ""
            width: parent.width
            height: txtAviso.implicitHeight + 16
            radius: 12
            color: p.mensajeError ? Qt.rgba(1, 0.33, 0.33, 0.18) : p.s.alfa(p.tema.primary, 0.14)
            Text {
                id: txtAviso
                anchors.verticalCenter: parent.verticalCenter
                x: 12
                width: parent.width - 24
                wrapMode: Text.Wrap
                text: (p.mensajeError ? "✕  " : "✓  ") + p.mensaje
                font.family: p.s.fuente
                font.pixelSize: 12
                color: p.mensajeError ? "#ff8a80" : p.tema.surfaceText
            }
        }

        // Cabecera de la tabla
        Item {
            width: parent.width
            height: 18
            Etiqueta { s: p.s; tema: p.tema; texto: "Procesos que más consumen"; anchors.left: parent.left; topPadding: 0 }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 44
                text: "CPU    RAM"
                font.family: p.s.fuente
                font.pixelSize: 10
                color: p.s.alfa(p.tema.surfaceText, 0.5)
            }
        }

        Column {
            width: parent.width
            spacing: 4

            Text {
                visible: p.procesos.length === 0
                leftPadding: 4
                text: "Midiendo…"
                font.family: p.s.fuente
                font.pixelSize: 12
                color: p.s.alfa(p.tema.surfaceText, 0.55)
            }

            Repeater {
                model: p.procesos
                delegate: Rectangle {
                    id: fp
                    required property var modelData
                    property bool pidiendo: p.confirmar === fp.modelData.pid
                    width: parent.width
                    height: 38
                    radius: 12
                    color: fp.pidiendo ? Qt.rgba(1, 0.33, 0.33, 0.15) : p.s.alfa(p.tema.primary, maP.containsMouse ? 0.1 : 0.04)
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                    MouseArea {
                        id: maP
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    // Normal: nombre · pid · cpu · ram · ✕
                    Item {
                        anchors.fill: parent
                        visible: !fp.pidiendo
                        Column {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 170
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: fp.modelData.nombre
                                font.family: p.s.fuente
                                font.pixelSize: 12
                                font.bold: true
                                color: p.tema.surfaceText
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: "PID " + fp.modelData.pid + (fp.modelData.usuario !== p.usuario ? " · " + fp.modelData.usuario : "")
                                font.family: p.s.fuente
                                font.pixelSize: 9
                                color: p.s.alfa(p.tema.surfaceText, 0.5)
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 44
                            anchors.verticalCenter: parent.verticalCenter
                            text: (fp.modelData.cpu.toFixed(1) + "%").padStart(6, " ") + " " + (fp.modelData.mem.toFixed(1) + "%").padStart(6, " ")
                            font.family: p.s.fuente
                            font.pixelSize: 11
                            color: p.tema.surfaceText
                        }
                        Boton {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            tema: p.tema
                            icono: p.s.ic(0xF0156)
                            colorIcono: "#ff8a80"
                            onClic: { p.mensaje = ""; p.confirmar = fp.modelData.pid }
                        }
                    }

                    // Confirmación
                    Row {
                        visible: fp.pidiendo
                        anchors.verticalCenter: parent.verticalCenter
                        x: 12
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: fp.width - 12 - 6 * 2 - btnNo.width - btnSi.width - 12
                            elide: Text.ElideRight
                            text: "¿Cerrar " + fp.modelData.nombre + "?"
                            font.family: p.s.fuente
                            font.pixelSize: 12
                            color: p.tema.surfaceText
                        }
                        BotonTexto {
                            id: btnNo
                            height: 28
                            tema: p.tema
                            fuente: p.s.fuente
                            texto: "Cancelar"
                            onClic: p.confirmar = -1
                        }
                        BotonTexto {
                            id: btnSi
                            height: 28
                            tema: p.tema
                            fuente: p.s.fuente
                            texto: "Cerrar"
                            peligro: true
                            onClic: p.cerrarProceso(fp.modelData)
                        }
                    }
                }
            }
        }
    }
}
