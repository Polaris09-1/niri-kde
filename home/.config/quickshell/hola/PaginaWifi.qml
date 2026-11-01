import QtQuick
import Quickshell
import Quickshell.Io

// Página Wi-Fi: redes cercanas, conectar, contraseña, olvidar, encender/apagar.
// Seguridad: la contraseña se pasa a "nmcli --ask" por stdin (nunca como argumento,
// así no aparece en ps), no se guarda en archivos ni se escribe en el log, y el
// campo se vacía tras cada intento. (NetworkManager sí guarda la clave de las redes
// que conectan bien, en su almacén de root, para no volver a pedirla.)
Item {
    id: w

    property var s                 // la barra (fuente, ic, alfa, refrescarWifi)
    property var tema
    property bool activa: false
    signal atras()

    implicitHeight: col.implicitHeight

    // ===== Estado =====
    property bool encendido: true
    property bool cambiandoRadio: false
    property bool escaneando: false
    property var redes: []            // {ssid, senal, segura, empresa, conectada, uuids}
    property var guardadas: ({})      // ssid -> [uuid, ...]
    property string elegida: ""       // fila desplegada
    property string conectando: ""
    property string mensaje: ""
    property string tipoMensaje: ""   // "info" | "ok" | "error"
    property string confirmarOlvidar: ""

    // Para limpiar el perfil a medias si falla una clave nueva
    property string limpiarSsid: ""
    property var uuidsAntes: []

    onActivaChanged: {
        if (activa) {
            w.mensaje = ""
            w.refrescar(false)
        } else {
            w.elegida = ""
            w.confirmarOlvidar = ""
        }
    }

    function refrescar(escanear) {
        pRadio.running = true
        pGuardadas.running = true
        if (!pLista.running) {
            w.escaneando = escanear
            pLista.rescan = escanear
            pLista.running = true
        }
    }

    // Separa una línea "terse" de nmcli respetando "\:" escapados
    function partir(linea) {
        var campos = [], actual = "", esc = false
        for (var i = 0; i < linea.length; i++) {
            var c = linea[i]
            if (esc) { actual += c; esc = false }
            else if (c === "\\") esc = true
            else if (c === ":") { campos.push(actual); actual = "" }
            else actual += c
        }
        campos.push(actual)
        return campos
    }

    function procesarGuardadas(t) {
        var g = {}
        t.split("\n").forEach(l => {
            if (l.trim() === "") return
            var p = l.split("\t")
            var ssid = (p[1] || "").replace(/\\:/g, ":")
            if (ssid === "") return
            if (!g[ssid]) g[ssid] = []
            g[ssid].push(p[0])
        })
        w.guardadas = g

        // Si falló una clave nueva, borra el perfil que nmcli dejó creado
        if (w.limpiarSsid !== "") {
            var nuevos = (g[w.limpiarSsid] || []).filter(u => w.uuidsAntes.indexOf(u) < 0)
            w.limpiarSsid = ""
            if (nuevos.length > 0) {
                pBorrar.command = ["nmcli", "connection", "delete", "uuid"].concat(nuevos)
                pBorrar.running = true
            }
        }
        w.combinar(w.redes)
    }

    function procesarLista(t) {
        var mapa = {}
        t.split("\n").forEach(l => {
            if (l.trim() === "") return
            var c = w.partir(l)
            var ssid = c[1] || ""
            if (ssid === "") return    // redes ocultas
            var seg = c[3] || ""
            var r = {
                ssid: ssid,
                senal: parseInt(c[2]) || 0,
                segura: seg !== "" && seg !== "--",
                empresa: /802\.1X|EAP/i.test(seg),
                conectada: c[0] === "*"
            }
            var prev = mapa[ssid]
            if (!prev) mapa[ssid] = r
            else {
                prev.conectada = prev.conectada || r.conectada
                prev.senal = Math.max(prev.senal, r.senal)
            }
        })
        w.combinar(Object.keys(mapa).map(k => mapa[k]))
    }

    function combinar(lista) {
        var l = lista.map(r => ({
            ssid: r.ssid, senal: r.senal, segura: r.segura, empresa: r.empresa,
            conectada: r.conectada, uuids: w.guardadas[r.ssid] || []
        }))
        l.sort((a, b) => {
            if (a.conectada !== b.conectada) return a.conectada ? -1 : 1
            var ga = a.uuids.length > 0, gb = b.uuids.length > 0
            if (ga !== gb) return ga ? -1 : 1
            return b.senal - a.senal
        })
        w.redes = l
    }

    function iconoSenal(n) {
        if (n < 25) return 0xF091F
        if (n < 50) return 0xF0922
        if (n < 75) return 0xF0925
        return 0xF0928
    }

    function avisar(texto, tipo) {
        w.mensaje = texto
        w.tipoMensaje = tipo
    }

    // Traduce los errores de nmcli a algo entendible
    function traducir(t) {
        if (/psk.*invalid|invalid.*psk|property is invalid/i.test(t)) return "La contraseña debe tener entre 8 y 63 caracteres"
        if (/secrets were required|no secrets|not provided|authentication|4-way|wrong password|802-11-wireless-security/i.test(t)) return "Contraseña incorrecta"
        if (/no network with ssid/i.test(t)) return "La red ya no está al alcance"
        if (/timeout|timed out/i.test(t)) return "Tardó demasiado en responder. Acércate al router e inténtalo otra vez"
        if (/not authorized|insufficient privileges|permission/i.test(t)) return "No tienes permiso para cambiar la red"
        if (/radio|disabled|unavailable|not available/i.test(t)) return "El Wi-Fi está apagado o no está disponible"
        var m = t.match(/Error:\s*(.+)/)
        return m ? "No se pudo conectar: " + m[1].trim() : "No se pudo conectar"
    }

    // ===== Acciones =====
    function alternarRadio(v) {
        w.cambiandoRadio = true
        pRadioCambiar.command = ["nmcli", "radio", "wifi", v ? "on" : "off"]
        pRadioCambiar.running = true
    }

    // Clic en una fila
    function tocar(r) {
        w.confirmarOlvidar = ""
        if (w.conectando !== "") return
        if (r.empresa && r.uuids.length === 0) {
            w.elegida = ""
            w.avisar("Las redes empresariales (usuario + clave) no se pueden configurar aquí", "error")
            return
        }
        // Red abierta y no guardada: conectar directo
        if (!r.segura && r.uuids.length === 0 && !r.conectada) {
            w.elegida = ""
            w.conectar(r, "")
            return
        }
        w.elegida = w.elegida === r.ssid ? "" : r.ssid
    }

    // clave = "" para redes abiertas o guardadas
    function conectar(r, clave) {
        w.conectando = r.ssid
        w.elegida = ""
        w.avisar("Conectando a " + r.ssid + "…", "info")
        if (r.uuids.length > 0 && clave === "") {
            pConectar.clave = ""
            pConectar.command = ["nmcli", "--wait", "30", "connection", "up", "uuid", r.uuids[0]]
        } else if (clave !== "") {
            w.uuidsAntes = r.uuids.slice()
            pConectar.clave = clave
            pConectar.command = ["nmcli", "--ask", "--wait", "30", "device", "wifi", "connect", r.ssid]
        } else {
            pConectar.clave = ""
            pConectar.command = ["nmcli", "--wait", "30", "device", "wifi", "connect", r.ssid]
        }
        pConectar.conClave = clave !== ""
        pConectar.running = true
    }

    function desconectar(r) {
        w.elegida = ""
        if (r.uuids.length === 0) return
        pAccion.command = ["nmcli", "connection", "down", "uuid", r.uuids[0]]
        pAccion.running = true
        w.avisar("Desconectado de " + r.ssid, "ok")
    }

    function olvidar(r) {
        w.confirmarOlvidar = ""
        w.elegida = ""
        if (r.uuids.length === 0) return
        pBorrar.command = ["nmcli", "connection", "delete", "uuid"].concat(r.uuids)
        pBorrar.running = true
        w.avisar("Se olvidó " + r.ssid, "ok")
    }

    // ===== Procesos =====
    Process {
        id: pRadio
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: w.encendido = text.trim() === "enabled"
        }
    }

    Process {
        id: pRadioCambiar
        onExited: {
            w.cambiandoRadio = false
            pRadio.running = true
            esperaRadio.restart()
        }
    }

    Timer {
        id: esperaRadio
        interval: 2500
        onTriggered: { w.refrescar(false); w.s.refrescarWifi() }
    }

    Process {
        id: pLista
        property bool rescan: false
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", rescan ? "yes" : "auto"]
        stdout: StdioCollector {
            onStreamFinished: w.procesarLista(text)
        }
        onExited: w.escaneando = false
    }

    Process {
        id: pGuardadas
        command: ["sh", "-c", "nmcli -t -f UUID,TYPE connection show | while IFS=: read -r u t; do [ \"$t\" = 802-11-wireless ] && printf '%s\\t%s\\n' \"$u\" \"$(nmcli -g 802-11-wireless.ssid connection show uuid \"$u\")\"; done"]
        stdout: StdioCollector {
            onStreamFinished: w.procesarGuardadas(text)
        }
    }

    Process {
        id: pBorrar
        onExited: pGuardadas.running = true
    }

    Process {
        id: pAccion
        onExited: { w.refrescar(false); w.s.refrescarWifi() }
    }

    Process {
        id: pConectar
        property string clave: ""
        property bool conClave: false
        property int codigo: 0
        stdinEnabled: true
        stdout: StdioCollector { id: salidaCon }
        stderr: StdioCollector { id: errorCon }
        onStarted: {
            // La clave solo viaja por stdin y se borra de memoria enseguida
            if (pConectar.clave !== "") pConectar.write(pConectar.clave + "\n")
            pConectar.clave = ""
            pConectar.stdinEnabled = false     // cierra stdin: si la pide otra vez, falla en vez de colgarse
        }
        onExited: (code, status) => {
            pConectar.codigo = code
            pConectar.stdinEnabled = true
            resultado.restart()
        }
    }

    // Espera a que se terminen de leer stdout/stderr
    Timer {
        id: resultado
        interval: 120
        onTriggered: {
            var ssid = w.conectando
            w.conectando = ""
            if (pConectar.codigo === 0) {
                w.avisar("Conectado a " + ssid, "ok")
            } else {
                w.avisar(w.traducir(salidaCon.text + "\n" + errorCon.text), "error")
                if (pConectar.conClave) w.limpiarSsid = ssid
            }
            w.refrescar(false)
            w.s.refrescarWifi()
        }
    }

    // ===== Interfaz =====
    Column {
        id: col
        width: parent.width
        spacing: 10

        Encabezado {
            tema: w.tema
            titulo: "Wi-Fi"
            onAtras: w.atras()

            Boton {
                id: btnEscanear
                anchors.verticalCenter: parent.verticalCenter
                tema: w.tema
                visible: w.encendido
                icono: w.s.ic(0xF0450)
                RotationAnimation on rotation {
                    running: w.escaneando
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                    onStopped: btnEscanear.rotation = 0
                }
                onClic: w.refrescar(true)
            }

            Interruptor {
                anchors.verticalCenter: parent.verticalCenter
                tema: w.tema
                activo: w.encendido
                ocupado: w.cambiandoRadio
                onCambiado: v => w.alternarRadio(v)
            }
        }

        // Aviso: conectando / éxito / error
        Rectangle {
            width: parent.width
            height: w.mensaje !== "" ? txtAviso.implicitHeight + 18 : 0
            visible: height > 0
            radius: 12
            color: w.tipoMensaje === "error" ? Qt.rgba(1, 0.33, 0.33, 0.18) : w.s.alfa(w.tema.primary, 0.14)
            Text {
                id: txtAviso
                anchors.verticalCenter: parent.verticalCenter
                x: 12
                width: parent.width - 24
                wrapMode: Text.Wrap
                text: (w.tipoMensaje === "error" ? "✕  " : w.tipoMensaje === "ok" ? "✓  " : "") + w.mensaje
                font.family: w.s.fuente
                font.pixelSize: 12
                color: w.tipoMensaje === "error" ? "#ff8a80" : w.tema.surfaceText
            }
        }

        Text {
            visible: !w.encendido
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            topPadding: 12
            bottomPadding: 12
            text: "El Wi-Fi está apagado"
            font.family: w.s.fuente
            font.pixelSize: 13
            color: w.s.alfa(w.tema.surfaceText, 0.6)
        }

        Text {
            visible: w.encendido && w.redes.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            topPadding: 12
            bottomPadding: 12
            text: w.escaneando || pLista.running ? "Buscando redes…" : "No se encontraron redes"
            font.family: w.s.fuente
            font.pixelSize: 13
            color: w.s.alfa(w.tema.surfaceText, 0.6)
        }

        // Lista de redes (con scroll)
        Flickable {
            visible: w.encendido && w.redes.length > 0
            width: parent.width
            height: Math.min(listaRedes.implicitHeight, 330)
            contentHeight: listaRedes.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: listaRedes
                width: parent.width
                spacing: 4

                Repeater {
                    model: w.redes

                    delegate: Rectangle {
                        id: fila
                        required property var modelData
                        property bool abierta: w.elegida === fila.modelData.ssid
                        property bool guardada: fila.modelData.uuids.length > 0
                        property bool pideClave: fila.modelData.segura && !fila.guardada && !fila.modelData.conectada
                        property bool verClave: false

                        width: listaRedes.width
                        height: 46 + (fila.abierta ? extra.implicitHeight + 8 : 0)
                        radius: 14
                        clip: true
                        color: fila.modelData.conectada ? w.s.alfa(w.tema.primary, 0.2)
                            : w.s.alfa(w.tema.primary, maFila.containsMouse || fila.abierta ? 0.12 : 0.05)
                        Behavior on height {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }

                        onAbiertaChanged: {
                            if (fila.abierta && fila.pideClave) campoClave.forceActiveFocus()
                            if (!fila.abierta) { campoClave.text = ""; fila.verClave = false }
                        }

                        MouseArea {
                            id: maFila
                            width: parent.width
                            height: 46
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: w.tocar(fila.modelData)
                        }

                        // Señal
                        Text {
                            x: 12
                            y: 13
                            text: w.s.ic(w.iconoSenal(fila.modelData.senal))
                            font.family: w.s.fuente
                            font.pixelSize: 18
                            color: w.tema.primary
                        }

                        Column {
                            x: 44
                            y: 7
                            width: parent.width - 44 - 60
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: fila.modelData.ssid
                                font.family: w.s.fuente
                                font.pixelSize: 13
                                font.bold: fila.modelData.conectada
                                color: w.tema.surfaceText
                            }
                            Text {
                                text: w.conectando === fila.modelData.ssid ? "Conectando…"
                                    : fila.modelData.conectada ? "Conectada"
                                    : fila.guardada ? "Guardada"
                                    : fila.modelData.empresa ? "Empresarial"
                                    : fila.modelData.segura ? "Protegida" : "Abierta"
                                font.family: w.s.fuente
                                font.pixelSize: 10
                                color: w.s.alfa(w.tema.surfaceText, 0.6)
                            }
                        }

                        // Candado y check
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            y: 14
                            spacing: 8
                            Text {
                                visible: fila.modelData.segura
                                text: w.s.ic(0xF033E)
                                font.family: w.s.fuente
                                font.pixelSize: 14
                                color: w.s.alfa(w.tema.surfaceText, 0.6)
                            }
                            Text {
                                visible: fila.modelData.conectada
                                text: w.s.ic(0xF012C)
                                font.family: w.s.fuente
                                font.pixelSize: 15
                                color: w.tema.primary
                            }
                        }

                        // Parte desplegable
                        Item {
                            id: extra
                            x: 10
                            y: 50
                            width: parent.width - 20
                            implicitHeight: fila.pideClave ? 40 : 34
                            visible: fila.abierta

                            // --- Red nueva con clave: campo + ojito + Conectar ---
                            Row {
                                visible: fila.pideClave
                                spacing: 6
                                width: parent.width

                                Rectangle {
                                    width: parent.width - btnConectar.width - 6
                                    height: 36
                                    radius: 12
                                    color: w.s.alfa(w.tema.surface, 0.9)
                                    border.color: campoClave.activeFocus ? w.tema.primary : w.s.alfa(w.tema.primary, 0.4)
                                    border.width: 1.5

                                    TextInput {
                                        id: campoClave
                                        x: 12
                                        width: parent.width - 48
                                        anchors.verticalCenter: parent.verticalCenter
                                        echoMode: fila.verClave ? TextInput.Normal : TextInput.Password
                                        passwordCharacter: "•"
                                        font.family: w.s.fuente
                                        font.pixelSize: 13
                                        color: w.tema.surfaceText
                                        selectionColor: w.tema.primary
                                        clip: true
                                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                                        onAccepted: btnConectar.enviar()

                                        Text {
                                            visible: campoClave.text === ""
                                            text: "Contraseña"
                                            font: campoClave.font
                                            color: w.s.alfa(w.tema.surfaceText, 0.4)
                                        }
                                    }

                                    // Ojito
                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: w.s.ic(fila.verClave ? 0xF0209 : 0xF0208)
                                        font.family: w.s.fuente
                                        font.pixelSize: 16
                                        color: w.tema.primary
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: fila.verClave = !fila.verClave
                                        }
                                    }
                                }

                                Rectangle {
                                    id: btnConectar
                                    width: txtConectar.implicitWidth + 24
                                    height: 36
                                    radius: 12
                                    color: w.tema.primary
                                    opacity: campoClave.text.length > 0 ? (maConectar.pressed ? 0.7 : 1) : 0.4
                                    function enviar() {
                                        if (campoClave.text.length === 0) return
                                        var clave = campoClave.text
                                        campoClave.text = ""
                                        w.conectar(fila.modelData, clave)
                                    }
                                    Text {
                                        id: txtConectar
                                        anchors.centerIn: parent
                                        text: "Conectar"
                                        font.family: w.s.fuente
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: w.tema.primaryText
                                    }
                                    MouseArea {
                                        id: maConectar
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: btnConectar.enviar()
                                    }
                                }
                            }

                            // --- Red guardada o conectada: acciones ---
                            Row {
                                visible: !fila.pideClave
                                spacing: 6

                                BotonTexto {
                                    tema: w.tema
                                    fuente: w.s.fuente
                                    visible: w.confirmarOlvidar !== fila.modelData.ssid
                                    texto: fila.modelData.conectada ? "Desconectar" : "Conectar"
                                    lleno: true
                                    onClic: fila.modelData.conectada ? w.desconectar(fila.modelData) : w.conectar(fila.modelData, "")
                                }
                                BotonTexto {
                                    tema: w.tema
                                    fuente: w.s.fuente
                                    visible: fila.guardada && w.confirmarOlvidar !== fila.modelData.ssid
                                    texto: "Olvidar red"
                                    onClic: w.confirmarOlvidar = fila.modelData.ssid
                                }
                                // Confirmación de "Olvidar"
                                Text {
                                    visible: w.confirmarOlvidar === fila.modelData.ssid
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "¿Olvidar la red?"
                                    font.family: w.s.fuente
                                    font.pixelSize: 12
                                    color: w.tema.surfaceText
                                }
                                BotonTexto {
                                    tema: w.tema
                                    fuente: w.s.fuente
                                    visible: w.confirmarOlvidar === fila.modelData.ssid
                                    texto: "Cancelar"
                                    onClic: w.confirmarOlvidar = ""
                                }
                                BotonTexto {
                                    tema: w.tema
                                    fuente: w.s.fuente
                                    visible: w.confirmarOlvidar === fila.modelData.ssid
                                    texto: "Olvidar"
                                    peligro: true
                                    onClic: w.olvidar(fila.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
