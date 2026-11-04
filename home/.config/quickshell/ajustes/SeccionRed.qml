import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Red y Bluetooth. La lista de redes es la misma página del panel (PaginaWifi.qml), con su regla de contraseñas:
// solo por stdin y el campo se vacía. Emparejar va en el panel: bluetoothctl admite un único agente, y es el de "hola".
Column {
    id: c

    property var raiz
    spacing: 8

    // Salida de nmcli -t: los ":" del contenido van escapados como "\:"
    function partir(linea) {
        var l = [], t = "", i
        for (i = 0; i < linea.length; i++) {
            if (linea[i] === "\\" && i + 1 < linea.length) { t += linea[++i]; continue }
            if (linea[i] === ":") { l.push(t); t = ""; continue }
            t += linea[i]
        }
        l.push(t)
        return l
    }

    // ===== Wi-Fi =====
    Ancla {
        raiz: c.raiz
        opId: "red.wifi"
        PaginaWifi {
            width: parent.width
            s: c.raiz
            tema: c.raiz.tema
            activa: true
            conAtras: false
        }
    }

    // ===== Conexión activa (los datos no se muestran hasta pedirlo: pueden salir en una captura) =====
    property var dispositivos: []
    property var detalles: ({})
    property bool verDetalles: false
    Process {
        id: pDisp
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var l = []
                text.trim().split("\n").forEach(s => {
                    var p = c.partir(s)
                    if ((p[1] === "wifi" || p[1] === "ethernet") && p[2] === "connected") l.push({ dev: p[0], tipo: p[1], con: p[3] })
                })
                if (JSON.stringify(l) !== JSON.stringify(c.dispositivos)) c.dispositivos = l
            }
        }
    }
    Process {
        id: pDetalles
        property string dev: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var d = { ip: [], gw: "", dns: [] }
                text.trim().split("\n").forEach(s => {
                    var p = c.partir(s)
                    if (p[0].indexOf("IP4.ADDRESS") === 0) d.ip.push(p[1])
                    else if (p[0] === "IP4.GATEWAY") d.gw = p[1]
                    else if (p[0].indexOf("IP4.DNS") === 0) d.dns.push(p[1])
                })
                var t = Object.assign({}, c.detalles)
                t[pDetalles.dev] = d
                c.detalles = t
            }
        }
    }
    function leerDetalles(dev) {
        pDetalles.dev = dev
        pDetalles.command = ["nmcli", "-t", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show", dev]
        pDetalles.running = true
    }
    Timer {
        interval: 5000; repeat: true; running: true
        onTriggered: { pDisp.running = true; pGuardadas.running = true }
    }

    Etiqueta { s: c.raiz; tema: c.raiz.tema; texto: "Conexión activa" }
    Ancla {
        raiz: c.raiz
        opId: "red.actual"
        Text {
            visible: c.dispositivos.length === 0
            width: parent.width
            wrapMode: Text.Wrap
            text: "Sin conexión."
            font.family: c.raiz.fuente
            font.pixelSize: 12
            color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.6)
        }
        Repeater {
            model: c.dispositivos
            delegate: Column {
                id: filaDisp
                required property var modelData
                width: parent ? parent.width : 300
                spacing: 4
                readonly property var d: c.detalles[filaDisp.modelData.dev] || null
                FilaSimple {
                    raiz: c.raiz
                    t: filaDisp.modelData.con
                    a: (filaDisp.modelData.tipo === "wifi" ? "Wi-Fi" : "Cable") + " · " + filaDisp.modelData.dev
                    BotonTexto {
                        anchors.verticalCenter: parent.verticalCenter
                        tema: c.raiz.tema
                        fuente: c.raiz.fuente
                        texto: c.verDetalles ? "Ocultar datos" : "Mostrar datos"
                        onClic: {
                            c.verDetalles = !c.verDetalles
                            if (c.verDetalles) c.leerDetalles(filaDisp.modelData.dev)
                        }
                    }
                }
                Text {
                    visible: c.verDetalles && !!filaDisp.d
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    text: filaDisp.d ? "IP: " + (filaDisp.d.ip.join(", ") || "—") + "\nPuerta de enlace: " + (filaDisp.d.gw || "—")
                        + "\nDNS: " + (filaDisp.d.dns.join(", ") || "—") : ""
                    textFormat: Text.PlainText
                    font.family: c.raiz.fuente
                    font.pixelSize: 11
                    color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.75)
                }
            }
        }
    }

    // ===== Redes guardadas =====
    property var guardadas: []
    property string confirmarOlvidar: ""
    property string errorRed: ""
    Timer { id: finConfirmar; interval: 4000; onTriggered: c.confirmarOlvidar = "" }
    Process {
        id: pGuardadas
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,AUTOCONNECT", "connection", "show"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var l = []
                text.trim().split("\n").forEach(s => {
                    var p = c.partir(s)
                    if (p[2] === "802-11-wireless" || p[2] === "802-3-ethernet" || p[2] === "vpn")
                        l.push({ nombre: p[0], uuid: p[1], tipo: p[2], auto: p[3] === "yes" })
                })
                l.sort((a, b) => a.nombre.localeCompare(b.nombre))
                if (JSON.stringify(l) !== JSON.stringify(c.guardadas)) c.guardadas = l
            }
        }
    }
    // Comandos de NetworkManager con su error en lenguaje claro
    Process {
        id: pAccion
        property string errorTexto: ""
        stderr: StdioCollector { onStreamFinished: pAccion.errorTexto = text }
        onExited: code => {
            Qt.callLater(() => {
                if (code !== 0) c.raiz.avisar("NetworkManager no lo aceptó: " + (pAccion.errorTexto.trim() || ("error " + code)), true)
                pGuardadas.running = true
            })
        }
    }
    function nm(cmd) {
        pAccion.errorTexto = ""
        pAccion.command = cmd
        pAccion.running = true
    }

    Etiqueta { s: c.raiz; tema: c.raiz.tema; texto: "Redes guardadas" }
    Ancla {
        raiz: c.raiz
        opId: "red.guardadas"
        Text {
            visible: c.guardadas.length === 0
            width: parent.width
            wrapMode: Text.Wrap
            text: "No hay redes guardadas."
            font.family: c.raiz.fuente
            font.pixelSize: 12
            color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.6)
        }
        Repeater {
            model: c.guardadas
            delegate: FilaSimple {
                id: filaRed
                required property var modelData
                raiz: c.raiz
                t: filaRed.modelData.nombre
                a: c.confirmarOlvidar === filaRed.modelData.uuid ? "Se borrará también su contraseña. Esto no se puede deshacer."
                    : filaRed.modelData.auto ? "Se conecta sola" : "Solo a mano"
                Interruptor {
                    anchors.verticalCenter: parent.verticalCenter
                    tema: c.raiz.tema
                    activo: filaRed.modelData.auto
                    onCambiado: v => {
                        c.raiz.registrar("Conectar sola: " + filaRed.modelData.nombre, [{ clave: "ext.redAuto", uuid: filaRed.modelData.uuid, antes: filaRed.modelData.auto }])
                        c.nm(["nmcli", "connection", "modify", filaRed.modelData.uuid, "connection.autoconnect", v ? "yes" : "no"])
                    }
                }
                BotonTexto {
                    anchors.verticalCenter: parent.verticalCenter
                    tema: c.raiz.tema
                    fuente: c.raiz.fuente
                    peligro: c.confirmarOlvidar === filaRed.modelData.uuid
                    texto: c.confirmarOlvidar === filaRed.modelData.uuid ? "¿Seguro?" : "Olvidar"
                    onClic: {
                        if (c.confirmarOlvidar !== filaRed.modelData.uuid) { c.confirmarOlvidar = filaRed.modelData.uuid; finConfirmar.restart(); return }
                        c.confirmarOlvidar = ""
                        c.nm(["nmcli", "connection", "delete", filaRed.modelData.uuid])
                    }
                }
            }
        }
    }

    // ===== Red oculta =====
    Process {
        id: pOculta
        property string clave: ""
        property string salidaTexto: ""
        stdinEnabled: true
        stdout: StdioCollector { onStreamFinished: pOculta.salidaTexto = text }
        stderr: StdioCollector { id: errOculta }
        onStarted: { pOculta.write(pOculta.clave + "\n"); pOculta.clave = ""; pOculta.stdinEnabled = false }
        onExited: code => {
            pOculta.stdinEnabled = true
            Qt.callLater(() => {
                if (code === 0) c.raiz.avisar("Conectado a la red oculta.", false)
                else c.raiz.avisar("No se pudo conectar a la red oculta: " + (errOculta.text.trim() || pOculta.salidaTexto.trim() || ("error " + code)), true)
                pGuardadas.running = true
                pDisp.running = true
            })
        }
    }
    Etiqueta { s: c.raiz; tema: c.raiz.tema; texto: "Más opciones" }
    Ancla {
        raiz: c.raiz
        opId: "red.oculta"
        FilaSimple {
            raiz: c.raiz
            t: "Conectar a una red oculta"
            a: "Escribe su nombre y contraseña. La contraseña no se guarda aquí."
        }
        Row {
            width: parent.width
            spacing: 6
            Repeater {
                model: 2
                delegate: Rectangle {
                    required property int index
                    width: (parent.width - 6 - botonOculta.width - 6) / 2
                    height: 34
                    radius: 10
                    color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.07)
                    border.width: 1
                    border.color: c.raiz.alfa(c.raiz.tema.primary, 0.35)
                    TextInput {
                        id: campoO
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        maximumLength: index === 0 ? 32 : 63
                        echoMode: index === 0 ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        inputMethodHints: index === 0 ? Qt.ImhNone : (Qt.ImhSensitiveData | Qt.ImhNoPredictiveText)
                        font.family: c.raiz.fuente
                        font.pixelSize: 12
                        color: c.raiz.tema.surfaceText
                        onTextChanged: { if (index === 0) botonOculta.ssid = text; else botonOculta.clave = text }
                        Connections {
                            target: botonOculta
                            function onVaciar() { if (index === 1) campoO.text = "" }
                        }
                        Text {
                            visible: campoO.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            elide: Text.ElideRight
                            text: index === 0 ? "Nombre de la red" : "Contraseña"
                            font: campoO.font
                            color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.4)
                        }
                    }
                }
            }
            BotonTexto {
                id: botonOculta
                property string ssid: ""
                property string clave: ""
                signal vaciar()
                anchors.verticalCenter: parent.verticalCenter
                tema: c.raiz.tema
                fuente: c.raiz.fuente
                lleno: true
                texto: "Conectar"
                opacity: ssid !== "" ? 1 : 0.4
                onClic: {
                    if (ssid === "" || pOculta.running) return
                    pOculta.clave = clave
                    pOculta.stdinEnabled = true
                    pOculta.command = ["nmcli", "--ask", "device", "wifi", "connect", ssid, "hidden", "yes"]
                    pOculta.running = true
                    vaciar()
                    c.raiz.soltarFoco()
                }
            }
        }
    }
    Ancla {
        raiz: c.raiz
        opId: "red.avanzado"
        FilaSimple {
            raiz: c.raiz
            t: "Avanzado: VPN, IP fija, proxy"
            a: "Abre el editor de conexiones de NetworkManager."
            BotonTexto {
                anchors.verticalCenter: parent.verticalCenter
                tema: c.raiz.tema
                fuente: c.raiz.fuente
                texto: "Abrir"
                onClic: c.raiz.ejecutar(["nm-connection-editor"])
            }
        }
    }

    // ===== Bluetooth: el estado siempre sale de las propiedades de BlueZ =====
    readonly property var adaptador: Bluetooth.defaultAdapter
    readonly property bool hayBt: c.adaptador !== null
    readonly property var emparejados: c.hayBt ? c.adaptador.devices.values.filter(d => d.paired) : []
    property string confirmarQuitar: ""
    Timer { id: finQuitar; interval: 4000; onTriggered: c.confirmarQuitar = "" }

    Etiqueta { s: c.raiz; tema: c.raiz.tema; texto: "Bluetooth" }
    Ancla {
        raiz: c.raiz
        opId: "bt.activo"
        Text {
            visible: !c.hayBt
            width: parent.width
            wrapMode: Text.Wrap
            text: "No hay ningún adaptador Bluetooth disponible."
            font.family: c.raiz.fuente
            font.pixelSize: 12
            color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.6)
        }
        FilaSimple {
            visible: c.hayBt
            raiz: c.raiz
            t: "Bluetooth"
            a: c.hayBt ? c.adaptador.name : ""
            Interruptor {
                tema: c.raiz.tema
                activo: c.hayBt && c.adaptador.enabled
                onCambiado: v => {
                    c.raiz.registrar("Bluetooth", [{ clave: "ext.bt", antes: c.adaptador.enabled }])
                    c.adaptador.enabled = v
                }
            }
        }
        FilaSimple {
            visible: c.hayBt && c.adaptador.enabled
            raiz: c.raiz
            t: "Visible para otros dispositivos"
            a: "Se apaga sola al cabo de un rato."
            Interruptor {
                tema: c.raiz.tema
                activo: c.hayBt && c.adaptador.discoverable
                onCambiado: v => {
                    c.raiz.registrar("Bluetooth visible", [{ clave: "ext.btVisible", antes: c.adaptador.discoverable }])
                    c.adaptador.discoverable = v
                }
            }
        }
        FilaSimple {
            visible: c.hayBt && c.adaptador.enabled
            raiz: c.raiz
            t: "Buscar y emparejar"
            a: "Se abre en el panel de la barra, donde aparece el código."
            BotonTexto {
                anchors.verticalCenter: parent.verticalCenter
                tema: c.raiz.tema
                fuente: c.raiz.fuente
                texto: "Abrir"
                onClic: c.raiz.ejecutar(["qs", "-c", "hola", "ipc", "call", "hola", "pagina", "bluetooth"])
            }
        }
    }
    Ancla {
        visible: c.hayBt && c.adaptador.enabled
        raiz: c.raiz
        opId: "bt.dispositivos"
        Text {
            visible: c.emparejados.length === 0
            width: parent.width
            wrapMode: Text.Wrap
            text: "No hay dispositivos emparejados."
            font.family: c.raiz.fuente
            font.pixelSize: 12
            color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.6)
        }
        Repeater {
            model: c.emparejados
            delegate: Column {
                id: filaBt
                required property var modelData
                readonly property bool conectado: filaBt.modelData.connected && filaBt.modelData.paired
                width: parent ? parent.width : 300
                spacing: 4
                FilaSimple {
                    raiz: c.raiz
                    t: filaBt.modelData.name || filaBt.modelData.deviceName || "Dispositivo"
                    a: c.confirmarQuitar === filaBt.modelData.address ? "Habrá que emparejarlo otra vez. Esto no se puede deshacer."
                        : (filaBt.conectado ? "Conectado" : "Desconectado")
                            + (filaBt.modelData.batteryAvailable ? " · batería " + Math.round(filaBt.modelData.battery * 100) + " %" : "")
                    BotonTexto {
                        anchors.verticalCenter: parent.verticalCenter
                        tema: c.raiz.tema
                        fuente: c.raiz.fuente
                        lleno: !filaBt.conectado
                        texto: filaBt.conectado ? "Desconectar" : "Conectar"
                        onClic: { if (filaBt.conectado) filaBt.modelData.disconnect(); else filaBt.modelData.connect() }
                    }
                    BotonTexto {
                        anchors.verticalCenter: parent.verticalCenter
                        tema: c.raiz.tema
                        fuente: c.raiz.fuente
                        peligro: c.confirmarQuitar === filaBt.modelData.address
                        texto: c.confirmarQuitar === filaBt.modelData.address ? "¿Seguro?" : "Olvidar"
                        onClic: {
                            if (c.confirmarQuitar !== filaBt.modelData.address) { c.confirmarQuitar = filaBt.modelData.address; finQuitar.restart(); return }
                            c.confirmarQuitar = ""
                            filaBt.modelData.forget()
                        }
                    }
                }
                FilaSimple {
                    raiz: c.raiz
                    t: "De confianza"
                    a: "Se conecta sin preguntar."
                    Interruptor {
                        tema: c.raiz.tema
                        activo: filaBt.modelData.trusted
                        onCambiado: v => {
                            c.raiz.registrar("Confianza: " + (filaBt.modelData.name || "dispositivo"), [{ clave: "ext.btConfianza", mac: filaBt.modelData.address, antes: filaBt.modelData.trusted }])
                            filaBt.modelData.trusted = v
                        }
                    }
                }
            }
        }
    }
}
