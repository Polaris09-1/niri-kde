import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Página Bluetooth (bluez).
// El estado de cada dispositivo sale SIEMPRE de bluez (propiedades Paired/Connected/
// Trusted vía Quickshell.Bluetooth, que escucha los cambios por D-Bus).
// Emparejar/conectar/olvidar y el código de confirmación van por el agente
// (AgenteBluetooth.qml, con bluetoothctl).
Item {
    id: b

    property var s
    property var tema
    property var agente
    property bool activa: false
    signal atras()

    implicitHeight: col.implicitHeight

    property var adaptador: Bluetooth.defaultAdapter
    property bool disponible: b.adaptador !== null
    property bool encendido: b.disponible && b.adaptador.enabled
    property var dispositivos: b.disponible ? b.adaptador.devices.values : []
    property string elegido: ""          // dirección de la fila desplegada
    property var solicitud: b.agente ? b.agente.solicitud : null
    property var aviso: b.agente ? b.agente.aviso : null

    // Conectado de verdad = emparejado + conectado. Un enlace sin emparejar
    // (pasa unos segundos mientras se empareja) NO cuenta como conectado.
    function conectado(d) { return d.connected && d.paired }

    // Orden: conectados, emparejados, con nombre, sin nombre
    property var lista: {
        var l = b.dispositivos.slice()
        function rango(d) { return b.conectado(d) ? 0 : d.paired ? 1 : (d.name && d.name !== d.address.replace(/:/g, "-")) ? 2 : 3 }
        l.sort((x, y) => rango(x) - rango(y) || (x.name || "").localeCompare(y.name || ""))
        return l
    }

    onActivaChanged: {
        b.elegido = ""
        if (b.disponible) b.adaptador.discovering = b.activa && b.encendido
        if (b.activa && b.agente && b.aviso && !b.agente.operacion) b.agente.aviso = null
    }

    // Busca durante 30 s y para (ahorra batería)
    Timer {
        id: finBusqueda
        interval: 30000
        onTriggered: if (b.disponible) b.adaptador.discovering = false
    }

    function buscar() {
        if (!b.encendido) return
        b.adaptador.discovering = true
        finBusqueda.restart()
    }

    function operando(d) {
        var op = b.agente ? b.agente.operacion : null
        return op && op.mac === d.address ? op.tipo : ""
    }

    function estadoTexto(d) {
        if (b.solicitud && b.solicitud.mac === d.address) return "Confirma el código en tu celular"
        var op = b.operando(d)
        if (op === "pair") return d.paired ? "Emparejado, guardando…" : "Emparejando…"
        if (op === "connect") return "Conectando…"
        if (op === "disconnect") return "Desconectando…"
        if (op === "remove") return "Olvidando…"
        if (b.conectado(d)) return "Conectado" + (d.batteryAvailable ? " · batería " + Math.round(d.battery * 100) + "%" : "")
        if (d.paired) return "Emparejado · Desconectado"
        return "Disponible"
    }

    function iconoDe(d) {
        var i = d.icon || ""
        if (/headset|headphone|audio/.test(i)) return 0xF02CB
        if (/mouse/.test(i)) return 0xF037D
        if (/keyboard/.test(i)) return 0xF030C
        if (/phone/.test(i)) return 0xF011C
        if (/gaming|joystick/.test(i)) return 0xF0297
        if (/computer/.test(i)) return 0xF0322
        return 0xF00AF
    }

    // Un clic: nuevo -> emparejar · emparejado/conectado -> desplegar opciones
    function tocar(d) {
        if (!b.agente || b.agente.operacion) return
        if (!d.paired) {
            b.elegido = ""
            b.agente.emparejar(d.address)
            return
        }
        b.elegido = b.elegido === d.address ? "" : d.address
        if (b.elegido !== "") b.agente.pedirPerfiles(d.address)
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        Encabezado {
            tema: b.tema
            titulo: "Bluetooth"
            onAtras: b.atras()

            Boton {
                id: btnBuscar
                anchors.verticalCenter: parent.verticalCenter
                visible: b.encendido
                tema: b.tema
                icono: b.s.ic(0xF0450)
                RotationAnimation on rotation {
                    running: b.disponible && b.adaptador.discovering
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                    onStopped: btnBuscar.rotation = 0
                }
                onClic: b.buscar()
            }

            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                visible: b.disponible
                tema: b.tema
                activo: b.encendido
                onCambiado: v => {
                    b.adaptador.enabled = v
                    if (v) arranque.restart()
                }
            }
        }

        Timer {
            id: arranque
            interval: 800
            onTriggered: b.buscar()
        }

        // ---------- Pregunta del agente: código de 6 dígitos ----------
        Rectangle {
            visible: b.solicitud !== null
            width: parent.width
            height: colSol.implicitHeight + 28
            radius: 18
            color: b.s.alfa(b.tema.primary, 0.16)
            border.color: b.tema.primary
            border.width: 1.5

            Column {
                id: colSol
                anchors.centerIn: parent
                width: parent.width - 28
                spacing: 10

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: !b.solicitud ? ""
                        : b.solicitud.tipo === "confirmar" ? "Emparejar con " + b.solicitud.nombre
                        : b.solicitud.tipo === "autorizar" ? "¿Permitir que " + b.solicitud.nombre + " se conecte?"
                        : b.solicitud.tipo === "pin" ? b.solicitud.nombre + " pide un PIN"
                        : "Escribe este código en " + b.solicitud.nombre
                    font.family: b.s.fuente
                    font.pixelSize: 13
                    font.bold: true
                    color: b.tema.surfaceText
                }

                // Código grande
                Text {
                    visible: b.solicitud && b.solicitud.codigo !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: b.solicitud ? b.solicitud.codigo.replace(/(\d{3})(\d{3})/, "$1 $2") : ""
                    font.family: b.s.fuente
                    font.pixelSize: 34
                    font.bold: true
                    font.letterSpacing: 2
                    color: b.tema.primary
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: !b.solicitud ? ""
                        : b.solicitud.tipo === "confirmar" ? "Confirma el código en tu celular: ¿muestra el mismo número? Acepta aquí y en el celular."
                        : b.solicitud.tipo === "pin" ? "Prueba con 0000 o 1234 si el dispositivo no indica otro"
                        : b.solicitud.tipo === "mostrar" ? "Escríbelo en el dispositivo y pulsa Enter"
                        : "Solo acepta si fuiste tú"
                    font.family: b.s.fuente
                    font.pixelSize: 11
                    color: b.s.alfa(b.tema.surfaceText, 0.75)
                }

                // Campo para PIN
                Rectangle {
                    visible: b.solicitud && b.solicitud.tipo === "pin"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 160
                    height: 36
                    radius: 12
                    color: b.s.alfa(b.tema.surface, 0.9)
                    border.color: b.tema.primary
                    border.width: 1.5
                    TextInput {
                        id: campoPin
                        anchors.fill: parent
                        anchors.margins: 8
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: b.s.fuente
                        font.pixelSize: 15
                        color: b.tema.surfaceText
                        inputMethodHints: Qt.ImhDigitsOnly
                        maximumLength: 16
                        onAccepted: { b.agente.responder(true, campoPin.text); campoPin.text = ""; b.s.soltarFoco() }
                    }
                }

                Row {
                    visible: b.solicitud && b.solicitud.tipo !== "mostrar"
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    BotonTexto {
                        tema: b.tema
                        fuente: b.s.fuente
                        texto: "Rechazar"
                        onClic: { b.agente.responder(false); campoPin.text = ""; b.s.soltarFoco() }
                    }
                    BotonTexto {
                        tema: b.tema
                        fuente: b.s.fuente
                        texto: "Aceptar"
                        lleno: true
                        onClic: { b.agente.responder(true, campoPin.text); campoPin.text = ""; b.s.soltarFoco() }
                    }
                }
            }
        }

        // Sin bluez
        Text {
            visible: !b.disponible
            width: parent.width
            wrapMode: Text.Wrap
            topPadding: 6
            bottomPadding: 10
            text: "Bluetooth no está disponible.\nInstala bluez y activa el servicio:\nsudo pacman -S bluez bluez-utils\nsudo systemctl enable --now bluetooth"
            font.family: b.s.fuente
            font.pixelSize: 12
            color: b.s.alfa(b.tema.surfaceText, 0.75)
        }

        Text {
            visible: b.disponible && !b.encendido
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            topPadding: 12
            bottomPadding: 12
            text: "El Bluetooth está apagado"
            font.family: b.s.fuente
            font.pixelSize: 13
            color: b.s.alfa(b.tema.surfaceText, 0.6)
        }

        Text {
            visible: b.disponible && b.encendido && b.agente && !b.agente.registrado
            width: parent.width
            wrapMode: Text.Wrap
            text: "Preparando el agente de emparejamiento…"
            font.family: b.s.fuente
            font.pixelSize: 11
            color: b.s.alfa(b.tema.surfaceText, 0.6)
        }

        // Aviso del agente (éxito / error en lenguaje claro)
        Rectangle {
            visible: b.aviso !== null && b.solicitud === null
            width: parent.width
            height: txtAviso.implicitHeight + 16
            radius: 12
            color: b.aviso && b.aviso.error ? Qt.rgba(1, 0.33, 0.33, 0.18) : b.s.alfa(b.tema.primary, 0.14)
            Text {
                id: txtAviso
                anchors.verticalCenter: parent.verticalCenter
                x: 12
                width: parent.width - 36
                wrapMode: Text.Wrap
                text: b.aviso ? (b.aviso.error ? "✕  " : "✓  ") + b.aviso.texto : ""
                font.family: b.s.fuente
                font.pixelSize: 12
                color: b.aviso && b.aviso.error ? "#ff8a80" : b.tema.surfaceText
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.top: parent.top
                anchors.topMargin: 6
                text: "✕"
                font.pixelSize: 11
                color: b.s.alfa(b.tema.surfaceText, 0.5)
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: b.agente.aviso = null
                }
            }
        }

        Text {
            visible: b.encendido && b.lista.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            topPadding: 10
            bottomPadding: 10
            text: b.adaptador && b.adaptador.discovering ? "Buscando dispositivos…" : "No hay dispositivos. Toca ↻ para buscar"
            font.family: b.s.fuente
            font.pixelSize: 12
            color: b.s.alfa(b.tema.surfaceText, 0.6)
        }

        Flickable {
            visible: b.encendido && b.lista.length > 0
            width: parent.width
            height: Math.min(listaDisp.implicitHeight, 330)
            contentHeight: listaDisp.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: listaDisp
                width: parent.width
                spacing: 4

                Repeater {
                    model: b.lista
                    delegate: Rectangle {
                        id: fd
                        required property var modelData
                        property bool abierta: b.elegido === fd.modelData.address
                        property bool conectado: b.conectado(fd.modelData)
                        property var perfiles: b.agente ? (b.agente.perfiles[fd.modelData.address] || []) : []
                        width: listaDisp.width
                        height: 46 + (fd.abierta ? extra.implicitHeight + 10 : 0)
                        radius: 14
                        clip: true
                        color: fd.conectado ? b.s.alfa(b.tema.primary, 0.2)
                            : b.s.alfa(b.tema.primary, maD.containsMouse || fd.abierta ? 0.12 : 0.05)
                        Behavior on height {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }

                        MouseArea {
                            id: maD
                            width: parent.width
                            height: 46
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: b.tocar(fd.modelData)
                        }

                        Text {
                            x: 12
                            y: 12
                            text: b.s.ic(b.iconoDe(fd.modelData))
                            font.family: b.s.fuente
                            font.pixelSize: 18
                            color: b.tema.primary
                        }
                        Column {
                            x: 44
                            y: 7
                            width: parent.width - 44 - 40
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: fd.modelData.name || fd.modelData.address
                                font.family: b.s.fuente
                                font.pixelSize: 13
                                font.bold: fd.conectado
                                color: b.tema.surfaceText
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: b.estadoTexto(fd.modelData)
                                font.family: b.s.fuente
                                font.pixelSize: 10
                                color: b.s.alfa(b.tema.surfaceText, 0.6)
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            y: 14
                            text: fd.conectado ? b.s.ic(0xF012C) : fd.modelData.paired ? b.s.ic(0xF0142) : ""
                            font.family: b.s.fuente
                            font.pixelSize: 15
                            color: b.tema.primary
                        }

                        // Opciones (emparejados)
                        Column {
                            id: extra
                            x: 10
                            y: 50
                            width: parent.width - 20
                            spacing: 8
                            visible: fd.abierta

                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: fd.perfiles.length > 0 ? "Puede usarse para: " + fd.perfiles.join(" · ")
                                    : "Leyendo qué servicios ofrece…"
                                font.family: b.s.fuente
                                font.pixelSize: 10
                                color: b.s.alfa(b.tema.surfaceText, 0.65)
                            }
                            Row {
                                spacing: 6
                                BotonTexto {
                                    tema: b.tema
                                    fuente: b.s.fuente
                                    texto: fd.conectado ? "Desconectar" : "Conectar"
                                    lleno: true
                                    onClic: {
                                        b.elegido = ""
                                        if (fd.conectado) b.agente.desconectar(fd.modelData.address)
                                        else b.agente.conectar(fd.modelData.address)
                                    }
                                }
                                BotonTexto {
                                    tema: b.tema
                                    fuente: b.s.fuente
                                    texto: "Olvidar"
                                    peligro: true
                                    onClic: { b.elegido = ""; b.agente.olvidar(fd.modelData.address) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
