import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Agente de emparejamiento Bluetooth + órdenes a bluez, usando bluetoothctl.
//
// - Mantiene vivo "bluetoothctl --agent KeyboardDisplay" registrado como agente por
//   defecto: así bluez nos pregunta el código de 6 dígitos (también cuando el
//   emparejamiento lo inicia el celular).
// - Las preguntas del agente se muestran en el panel (solicitud) y la respuesta
//   se escribe por stdin ("yes"/"no"/PIN).
// - El ESTADO (emparejado/conectado) nunca sale de aquí: sale de las propiedades
//   reales de bluez (Quickshell.Bluetooth, vía D-Bus). Aquí solo se verifica.
Scope {
    id: ag

    property string comando: "bluetoothctl"
    property bool activo: Bluetooth.defaultAdapter !== null
    property bool registrado: false

    // Pregunta pendiente del agente:
    // { tipo: "confirmar"|"autorizar"|"pin"|"mostrar", codigo, mac, nombre, servicio }
    property var solicitud: null
    // Operación en curso: { mac, tipo: "pair"|"connect"|"disconnect"|"remove" }
    property var operacion: null
    // Último aviso para el panel: { mac, texto, error }
    property var aviso: null

    signal pidioAtencion()     // llegó una pregunta: hay que mostrar el panel

    property string bufer: ""
    property string ultimoMac: ""

    // ===== Utilidades =====
    function dispositivo(mac) {
        return Bluetooth.devices.values.find(d => d.address === mac) || null
    }

    function nombre(mac) {
        var d = ag.dispositivo(mac)
        return d ? (d.name || mac) : (mac || "el dispositivo")
    }

    function avisar(mac, texto, error) {
        ag.aviso = { mac: mac, texto: texto, error: error }
    }

    // Quita colores ANSI, marcas de readline y el prompt "[algo]> "
    function limpiar(t) {
        t = t.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").replace(/[\x01\x02]/g, "")
        var i = t.lastIndexOf("\r")
        if (i >= 0) t = t.slice(i + 1)
        return t.replace(/^(\[[^\]\n]*\]>\s*)+/, "").trim()
    }

    // Errores de bluez en lenguaje claro
    function traducir(t) {
        if (/AuthenticationFailed/i.test(t)) return "El emparejamiento falló: el código no coincidió o no se aceptó a tiempo en el celular"
        if (/AuthenticationCanceled/i.test(t)) return "Se canceló el emparejamiento"
        if (/AuthenticationRejected/i.test(t)) return "Se rechazó el emparejamiento (en la laptop o en el celular)"
        if (/AuthenticationTimeout/i.test(t)) return "Se acabó el tiempo para confirmar el código"
        if (/ConnectionAttemptFailed|page.timeout|Host is down|timed? ?out/i.test(t)) return "El dispositivo no respondió. Deja abierta la pantalla de Bluetooth del celular y acércalo"
        if (/AlreadyExists/i.test(t)) return "Ya estaba emparejado"
        if (/InProgress/i.test(t)) return "Ya hay una operación en curso; espera un momento"
        if (/profile.unavailable|NotAvailable/i.test(t)) return "PERFIL"
        if (/NotReady/i.test(t)) return "El Bluetooth no está listo (¿está apagado?)"
        if (/DoesNotExist|not available/i.test(t)) return "El dispositivo ya no está al alcance; vuelve a buscar"
        return "No se pudo completar: " + t
    }

    // ===== Órdenes =====
    function enviar(linea) {
        if (proc.running) proc.write(linea + "\n")
    }

    function empezar(mac, tipo) {
        ag.operacion = { mac: mac, tipo: tipo }
        ag.aviso = null
        vigia.restart()
    }

    function emparejar(mac) { ag.empezar(mac, "pair"); ag.enviar("pair " + mac) }
    function conectar(mac) { ag.empezar(mac, "connect"); ag.enviar("connect " + mac) }
    function desconectar(mac) { ag.empezar(mac, "disconnect"); ag.enviar("disconnect " + mac) }
    function olvidar(mac) { ag.empezar(mac, "remove"); ag.enviar("remove " + mac) }

    // Respuesta a la pregunta del agente (acepta = true/false; pin opcional)
    function responder(acepta, pin) {
        var s = ag.solicitud
        if (!s) return
        ag.solicitud = null
        if (s.tipo === "pin") ag.enviar(acepta ? (pin || "") : "")
        else if (s.tipo !== "mostrar") ag.enviar(acepta ? "yes" : "no")
        if (acepta && s.tipo === "confirmar")
            ag.avisar(s.mac, "Ahora acepta también en tu celular (toca «Vincular»)", false)
        if (!acepta) ag.avisar(s.mac, "Rechazaste el emparejamiento", true)
    }

    function terminar() {
        ag.operacion = null
        vigia.stop()
    }

    // ===== Lectura de la salida de bluetoothctl =====
    function recibir(datos) {
        ag.bufer += datos
        var partes = ag.bufer.split("\n")
        ag.bufer = partes.pop()
        partes.forEach(l => ag.linea(ag.limpiar(l)))
        // Las preguntas del agente no terminan en salto de línea
        var resto = ag.limpiar(ag.bufer)
        if (/\(yes\/no\):?\s*$|Enter (PIN code|passkey).*:\s*$/i.test(resto)) {
            ag.linea(resto)
            ag.bufer = ""
        }
    }

    function nuevaSolicitud(tipo, codigo, servicio) {
        var mac = ag.operacion ? ag.operacion.mac : ag.ultimoMac
        // Si lo inició el celular: el que está emparejándose ahora
        if (!ag.operacion) {
            var d = Bluetooth.devices.values.find(x => x.pairing) || Bluetooth.devices.values.find(x => x.connected && !x.paired)
            if (d) mac = d.address
        }
        ag.solicitud = { tipo: tipo, codigo: codigo || "", mac: mac, nombre: ag.nombre(mac), servicio: servicio || "" }
        ag.pidioAtencion()
    }

    function linea(l) {
        if (l === "") return
        var m = l.match(/Device ([0-9A-F]{2}(?::[0-9A-F]{2}){5})/i)
        if (m) ag.ultimoMac = m[1].toUpperCase()

        if (/Agent registered/.test(l)) { ag.enviar("default-agent"); return }
        if (/Default agent request successful/.test(l)) { ag.registrado = true; return }
        if (/Agent unregistered|Failed to register agent/i.test(l)) { ag.registrado = false; return }

        // --- Preguntas del agente ---
        if ((m = l.match(/Confirm passkey (\d+)/i))) { ag.nuevaSolicitud("confirmar", ("000000" + m[1]).slice(-6)); return }
        if ((m = l.match(/Authorize service (\S+)/i))) { ag.nuevaSolicitud("autorizar", "", m[1]); return }
        if (/Request authorization/i.test(l) && /yes\/no/i.test(l)) { ag.nuevaSolicitud("autorizar", "", ""); return }
        if (/Enter (PIN code|passkey)/i.test(l)) { ag.nuevaSolicitud("pin", "", ""); return }
        if ((m = l.match(/\[agent\] (?:Passkey|PIN code):?\s*(\d+)/i))) { ag.nuevaSolicitud("mostrar", m[1]); return }
        if (/Request canceled/i.test(l)) {
            ag.solicitud = null
            if (ag.operacion && ag.operacion.tipo === "pair") ag.avisar(ag.operacion.mac, "El celular canceló el emparejamiento", true)
            return
        }

        var op = ag.operacion
        // --- Resultados ---
        if (/Pairing successful/i.test(l)) {
            var mp = op ? op.mac : ag.ultimoMac
            ag.enviar("trust " + mp)                 // queda como dispositivo de confianza
            verificar.esperar(mp, "pair")
            return
        }
        if ((m = l.match(/Failed to pair: (.+)/i))) {
            ag.solicitud = null
            var tp = ag.traducir(m[1])
            ag.avisar(op ? op.mac : ag.ultimoMac, tp === "PERFIL" ? "No se pudo emparejar" : tp, true)
            ag.terminar()
            return
        }
        if (/Connection successful/i.test(l)) { verificar.esperar(op ? op.mac : ag.ultimoMac, "connect"); return }
        if ((m = l.match(/Failed to connect: (.+)/i))) {
            var tc = ag.traducir(m[1])
            if (tc === "PERFIL") ag.avisar(op ? op.mac : "", "Está emparejado, pero ahora no hay ningún servicio que conectar (audio, internet). Es normal en celulares: se conecta solo cuando lo usas", false)
            else ag.avisar(op ? op.mac : "", tc, true)
            ag.terminar()
            return
        }
        if (/Successful disconnected/i.test(l)) { verificar.esperar(op ? op.mac : ag.ultimoMac, "disconnect"); return }
        if ((m = l.match(/Failed to disconnect: (.+)/i))) { ag.avisar(op ? op.mac : "", ag.traducir(m[1]), true); ag.terminar(); return }
        if (/Device has been removed/i.test(l)) { ag.avisar(op ? op.mac : "", "Se olvidó " + (op ? ag.nombre(op.mac) : "el dispositivo"), false); ag.terminar(); return }
        if ((m = l.match(/Failed to remove device: (.+)/i))) { ag.avisar(op ? op.mac : "", ag.traducir(m[1]), true); ag.terminar(); return }
        if (/Device ([0-9A-F:]{17}) not available/i.test(l) && op) { ag.avisar(op.mac, ag.traducir("not available"), true); ag.terminar(); return }
    }

    // Comprueba con las propiedades REALES de bluez antes de decir que salió bien
    Timer {
        id: verificar
        property string mac: ""
        property string tipo: ""
        property int intentos: 0
        interval: 700
        repeat: true
        function esperar(m, t) { verificar.mac = m; verificar.tipo = t; verificar.intentos = 0; verificar.restart() }
        onTriggered: {
            var d = ag.dispositivo(verificar.mac)
            var ok = d && (verificar.tipo === "pair" ? d.paired
                : verificar.tipo === "connect" ? (d.connected && d.paired)
                : !d.connected)
            if (ok || ++verificar.intentos >= 6) {
                stop()
                var n = ag.nombre(verificar.mac)
                if (verificar.tipo === "pair") {
                    if (ok) ag.avisar(verificar.mac, "Emparejado con " + n + (d.trusted ? " (de confianza)" : ""), false)
                    else ag.avisar(verificar.mac, "bluetoothctl dijo que se emparejó, pero bluez no lo confirma. Vuelve a intentarlo", true)
                } else if (verificar.tipo === "connect") {
                    if (ok) ag.avisar(verificar.mac, "Conectado a " + n, false)
                    else ag.avisar(verificar.mac, n + " no quedó conectado (el sistema no lo confirma)", true)
                } else {
                    ag.avisar(verificar.mac, ok ? "Desconectado de " + n : "No se pudo desconectar " + n, !ok)
                }
                ag.terminar()
            }
        }
    }

    // Si no pasa nada en 45 s, avisa y suelta la operación
    Timer {
        id: vigia
        interval: 45000
        onTriggered: {
            if (ag.operacion) ag.avisar(ag.operacion.mac, ag.nombre(ag.operacion.mac) + " no respondió a tiempo", true)
            ag.solicitud = null
            ag.operacion = null
        }
    }

    // ===== El proceso del agente =====
    Process {
        id: proc
        command: [ag.comando, "--agent", "KeyboardDisplay"]
        running: ag.activo
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: ""
            onRead: datos => ag.recibir(datos)
        }
        onExited: {
            ag.registrado = false
            ag.solicitud = null
            if (ag.activo) reinicio.restart()
        }
    }

    Timer {
        id: reinicio
        interval: 3000
        onTriggered: if (ag.activo) proc.running = true
    }

    // ===== Perfiles que ofrece un dispositivo (bluetoothctl info) =====
    property var perfiles: ({})      // mac -> [texto, ...]

    function pedirPerfiles(mac) {
        if (pInfo.running) return
        pInfo.mac = mac
        pInfo.command = [ag.comando, "info", mac]
        pInfo.running = true
    }

    Process {
        id: pInfo
        property string mac: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text
                var l = []
                if (/0000110a-/i.test(t)) l.push("Audio: escuchar el celular en la laptop")
                if (/0000111f-|00001112-/i.test(t)) l.push("Llamadas manos libres")
                if (/0000110e-|0000110c-/i.test(t)) l.push("Controles de música")
                if (/00001116-/i.test(t)) l.push("Compartir internet (anclaje Bluetooth)")
                if (/0000110b-/i.test(t)) l.push("Audio: la laptop suena en el dispositivo")
                if (/00001124-|00001812-/i.test(t)) l.push("Teclado / mouse")
                if (/00001105-/i.test(t)) l.push("Archivos (requiere el paquete bluez-obex)")
                var p = Object.assign({}, ag.perfiles)
                p[pInfo.mac] = l
                ag.perfiles = p
            }
        }
    }
}
