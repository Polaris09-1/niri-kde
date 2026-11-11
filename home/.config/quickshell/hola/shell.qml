//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris
import Quickshell.Bluetooth
import QtQuick
import Qt.labs.folderlistmodel

// Barra superior (diseño A): workspaces + ventana | hora | bandeja + píldora de estado.
// La píldora abre el panel de estado, la hora el calendario y la campanita las notificaciones; crecen
// desde su botón. Todo lo demás (apps) vive en el dock.
Scope {
    id: root

    // Sin el aviso "Config reloaded": matugen recarga este módulo en cada cambio de fondo.
    // Solo se oculta el de recarga correcta; el de error sigue saliendo.
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }

    // ===== Ajustes =====
    // Paneles al pasar el cursor (hora, campanita y píldora)
    // Los valores de aquí son los de fábrica; la app de Ajustes guarda los cambios en ajustes/ajustes.json
    property var conf: ({})
    function opc(clave, fabrica) { var v = root.conf[clave]; return v !== undefined ? v : fabrica }
    FileView {
        id: archivoConf
        path: Quickshell.env("HOME") + "/.config/quickshell/ajustes/ajustes.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.conf = JSON.parse(text()) || ({}) } catch (e) { root.conf = ({}) } }
    }
    readonly property bool abrirAlPasar: root.opc("barra.abrirAlPasar", true)
    readonly property int esperaAbrir: root.opc("barra.esperaAbrir", 60)      // ms con el cursor sobre el botón antes de abrir
    readonly property int esperaCerrar: root.opc("barra.esperaCerrar", 150)   // ms fuera del botón y del panel antes de cerrar
    readonly property bool verMusica: root.opc("barra.musica", true)
    // Pantalla completa (estilo macOS): la barra se esconde y deja de reservar su espacio; baja al
    // acercar el mouse al borde de arriba (mismos tiempos que los paneles: esperaAbrir/esperaCerrar)
    readonly property bool esconderEnPantallaCompleta: root.opc("barra.esconderPC", true)
    readonly property int altoSensor: root.opc("barra.altoSensor", 3)   // px del borde superior que hacen bajar la barra
    property string fuente: "JetBrainsMono Nerd Font"
    property int altoIsla: 38
    property real opacidadIsla: 0.85
    property string terminal: "alacritty"

    property bool mostrar: true

    // ===== Estado =====
    property var workspaces: []
    property var ventanas: []         // todas las ventanas de niri; cada barra busca la activa de su monitor
    property int cpu: 0
    property int ram: 0
    property int temp: 0
    property int brillo: 0
    property string wifiNombre: ""
    property int wifiSenal: -1
    property var cpuPrevio: [0, 0]

    // Paneles: "" | "estado" | "calendario" | "avisos"
    property string panel: ""
    property rect origenEstado: Qt.rect(0, 0, 0, 0)
    property rect origenCal: Qt.rect(0, 0, 0, 0)
    property rect origenAvisos: Qt.rect(0, 0, 0, 0)
    // Qué muestra el panel de la hora; no se borra al cerrar para que no cambie mientras se encoge
    property string modoReloj: "calendario"
    readonly property bool relojAbierto: root.panel === "calendario" || root.panel === "avisos"
    property date mesVista: new Date()

    // Audio (PipeWire) y batería (UPower)
    property var sink: Pipewire.defaultAudioSink
    property int volumen: (sink && sink.audio) ? Math.round(sink.audio.volume * 100) : 0
    property bool silencio: (sink && sink.audio) ? sink.audio.muted : false
    property var bat: UPower.displayDevice
    property real bateriaRaw: bat ? bat.percentage : 0
    property int bateria: Math.round(bateriaRaw > 1 ? bateriaRaw : bateriaRaw * 100)
    property bool cargando: bat ? bat.state === UPowerDeviceState.Charging : false

    // Reproductor activo (MPRIS) y píldora de música: todo el estado está en Reproduciendo.qml
    Reproduciendo {
        id: rep
        audio: root.audioActivo
        pausarOndas: root.todasOcultas || root.sesionBloqueada || !root.verMusica
        ondasReales: root.opc("musica.ondasReales", true)
        esperaOcultar: root.opc("musica.esperaOcultar", 10) * 1000
        retener: root.cursorEnMusica
        salida: root.sink
    }
    readonly property var jugador: rep.jugador

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    Colors { id: tema }

    SystemClock {
        id: reloj
        precision: root.panel === "calendario" ? SystemClock.Seconds : SystemClock.Minutes
    }

    // ===== Utilidades =====
    function ic(cp) { return String.fromCodePoint(cp) }
    function ejecutar(cmd) { Quickshell.execDetached(cmd) }
    function enTerminal(programa) { ejecutar([root.terminal, "-e", programa]) }
    function alfa(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    function iconoVolumen() {
        if (root.silencio || root.volumen === 0) return ic(0xF075F)
        if (root.volumen < 34) return ic(0xF057F)
        if (root.volumen < 67) return ic(0xF0580)
        return ic(0xF057E)
    }

    function iconoWifi() {
        if (root.wifiSenal < 0) return ic(0xF092D)
        if (root.wifiSenal < 25) return ic(0xF091F)
        if (root.wifiSenal < 50) return ic(0xF0922)
        if (root.wifiSenal < 75) return ic(0xF0925)
        return ic(0xF0928)
    }

    function iconoBateria() {
        if (root.cargando) return ic(0xF0084)
        var n = Math.min(10, Math.max(1, Math.round(root.bateria / 10)))
        return n === 10 ? ic(0xF0079) : ic(0xF007A + n - 1)
    }

    function tiempoBateria() {
        if (!root.bat) return ""
        // Con el límite de carga, al llegar al tope queda enchufada sin cargar
        if (limite.activo && (root.bat.state === UPowerDeviceState.PendingCharge
                || root.bat.state === UPowerDeviceState.FullyCharged))
            return "Enchufada · tope " + limite.fin + " %"
        var s = root.cargando ? root.bat.timeToFull : root.bat.timeToEmpty
        if (!s || s <= 0) return root.cargando ? "Cargando" : "En batería"
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        var t = h + "h " + (m < 10 ? "0" : "") + m + "m"
        if (root.cargando && limite.activo) return "Cargando hasta el " + limite.fin + " %"
        return root.cargando ? t + " para llenarse" : t + " restantes"
    }

    function iconoApp(id) {
        if (id === "") return ""
        var e = DesktopEntries.applications.values.find(a => a.id.toLowerCase() === id.toLowerCase())
        return Quickshell.iconPath(e ? e.icon : id.toLowerCase(), "application-x-executable")
    }

    // ===== Acciones (las usan los clics y el IPC) =====
    function silenciar() {
        if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
    }

    function ponerVolumen(v) {
        if (!root.sink || !root.sink.audio) return
        root.sink.audio.muted = false
        root.sink.audio.volume = Math.max(0, Math.min(1, v))
    }

    function cambiarVolumen(d) {
        if (root.sink && root.sink.audio) ponerVolumen(root.sink.audio.volume + d)
    }

    // ===== Brillo en vivo =====
    // Mientras arrastras, un Timer de 50 ms aplica el último valor pendiente
    // (throttle: como mucho ~20 llamadas/s). Un solo Process en serie evita que
    // una llamada vieja termine después de la nueva. Al soltar se aplica el valor exacto.
    property int brilloPedido: -1
    property int brilloAplicado: -1
    property bool simulandoArrastre: false
    readonly property bool arrastrandoBrillo: deslBrillo.arrastrando || root.simulandoArrastre

    function ponerBrillo(v) {
        root.brilloPedido = Math.max(1, Math.min(100, Math.round(v * 100)))
        root.brillo = root.brilloPedido
        if (!aplicarBrillo.running) {
            root.aplicarBrilloPendiente()   // el primer cambio se nota al instante
            aplicarBrillo.start()
        }
    }

    function soltarBrillo(v) {
        root.brilloPedido = Math.max(1, Math.min(100, Math.round(v * 100)))
        root.brillo = root.brilloPedido
        root.aplicarBrilloPendiente()
    }

    function aplicarBrilloPendiente() {
        if (pBrillo.running) return          // al terminar, onExited aplica lo que quede
        if (root.brilloPedido < 1 || root.brilloPedido === root.brilloAplicado) return
        root.brilloAplicado = root.brilloPedido
        pBrillo.command = ["brightnessctl", "-q", "set", root.brilloPedido + "%"]
        pBrillo.running = true
    }

    Process {
        id: pBrillo
        onExited: {
            root.aplicarBrilloPendiente()
            if (!root.arrastrandoBrillo) actualizarBrillo.restart()
        }
    }

    Timer {
        id: aplicarBrillo
        interval: 50
        repeat: true
        onTriggered: {
            root.aplicarBrilloPendiente()
            if (!root.arrastrandoBrillo) stop()
        }
    }

    // Prueba sin mouse: arrastre simulado de "desde" a "hasta" en ~800 ms
    property real simDesde: 0
    property real simHasta: 0
    property int simPaso: 0
    Timer {
        id: simArrastre
        interval: 16
        repeat: true
        onTriggered: {
            root.simPaso++
            var t = Math.min(1, root.simPaso / 50)
            var v = root.simDesde + (root.simHasta - root.simDesde) * t
            if (t < 1) root.ponerBrillo(v)
            else {
                stop()
                root.simulandoArrastre = false
                root.soltarBrillo(v)
            }
        }
    }

    function refrescarWifi() { pWifi.running = true }
    function moverMes(d) { root.mesVista = new Date(root.mesVista.getFullYear(), root.mesVista.getMonth() + d, 1) }

    // Páginas del panel de estado: inicio | wifi | bluetooth | audio | sistema | energia
    property string pagina: "inicio"
    readonly property var paginas: ["inicio", "wifi", "bluetooth", "audio", "sistema", "energia", "capturas", "nocturna"]

    // ===== Energía: luz nocturna (wlsunset), límite de carga (UPower) y modos (power-profiles-daemon) =====
    LuzNocturna { id: luz }
    LimiteCarga { id: limite }

    // Mantener despierto: el estado lo lleva el módulo "bloqueo" y lo publica en este archivo
    property bool cafeina: false
    property var mediosActivos: []
    property var audioActivo: []         // apps con audio (para la píldora de música)
    property bool sesionBloqueada: false
    FileView {
        id: archivoDespierto
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/bloqueo-despierto.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var d = JSON.parse(text())
                root.cafeina = d.cafeina === true
                root.mediosActivos = d.medios || []
                root.audioActivo = d.audio || []
                root.sesionBloqueada = d.bloqueado === true
            } catch (e) {}
        }
        onLoadFailed: reintentarDespierto.restart()     // "bloqueo" aún no ha arrancado
    }
    Timer {
        id: reintentarDespierto
        interval: 3000
        onTriggered: archivoDespierto.reload()
    }
    function alternarCafeina() {
        Quickshell.execDetached(["qs", "-c", "bloqueo", "ipc", "call", "bloqueo", "cafeina", "alternar"])
    }
    function textoPerfil() {
        return PowerProfiles.profile === PowerProfile.PowerSaver ? "ahorro"
            : PowerProfiles.profile === PowerProfile.Performance ? "rendimiento" : "equilibrado"
    }
    function ponerPerfil(nombre) {
        var p = { ahorro: PowerProfile.PowerSaver, equilibrado: PowerProfile.Balanced, rendimiento: PowerProfile.Performance }[nombre]
        if (p === undefined) return false
        if (p === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile) return false
        PowerProfiles.profile = p
        return true
    }

    // ===== Capturas y grabación =====
    // ===== Clic en la píldora de música: ir a la ventana de la app que suena =====
    // Candidatas: app_id parecido al .desktop o al nombre del reproductor (en flatpak, como Zen, el MPRIS lo
    // publica un proxy con otro PID) o mismo PID que el dueño del MPRIS (apps normales). Entre varias, la que
    // lleva el título de la canción en el suyo (la pestaña que suena), si no la usada más hace poco.
    // Si no hay ninguna, no hace nada: nunca abre el calendario (eso es solo la hora).
    property string musicaVentana: ""        // resultado del último clic, para el IPC
    function enfocarMusica() {
        if (pMusicaVentana.running) return
        var j = rep.activo
        var nombres = j ? [j.desktopEntry || "", j.identity || "", rep.nombreApp || ""]
                        : rep.audioConfirmado.concat([rep.nombreApp || ""])
        pMusicaVentana.nombres = nombres.filter(n => n !== "")
        pMusicaVentana.cancion = j && j.trackTitle ? String(j.trackTitle).trim() : ""
        pMusicaVentana.command = ["sh", "-c", 'if [ -n "$1" ]; then gdbus call --session --dest org.freedesktop.DBus '
            + '--object-path /org/freedesktop/DBus --method org.freedesktop.DBus.GetConnectionUnixProcessID "$1" 2>/dev/null; fi; '
            + 'echo; niri msg -j windows', "sh", j ? (j.dbusName || "") : ""]
        pMusicaVentana.running = true
    }
    Process {
        id: pMusicaVentana
        property var nombres: []
        property string cancion: ""
        stdout: StdioCollector { id: salidaMusicaVentana }
        onExited: {
            var partes = salidaMusicaVentana.text.split("\n")
            var m = /uint32 (\d+)/.exec(partes[0] || "")
            var pid = m ? parseInt(m[1]) : -1
            var l = []
            try { l = JSON.parse(partes.slice(1).join("\n")) } catch (e) {}
            var c = l.filter(w => w.pid === pid || avisos.coincide(w.app_id, pMusicaVentana.nombres))
            var t = pMusicaVentana.cancion.toLowerCase()
            var puntos = w => (t !== "" && (w.title || "").toLowerCase().indexOf(t) >= 0 ? 2e12 : 0)
                + (w.focus_timestamp ? w.focus_timestamp.secs * 1000 + w.focus_timestamp.nanos / 1e6 : 0)
            c.sort((a, b) => puntos(b) - puntos(a))
            if (c.length === 0) { root.musicaVentana = "ninguna"; return }
            root.musicaVentana = c[0].id + " " + c[0].app_id
            Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(c[0].id)])
        }
    }

    Grabadora { id: grabadora }
    AvisosSistema {
        id: avisosSistema
        bateria: root.bateria
        cargando: root.cargando
        wifi: root.wifiNombre
        adaptador: root.btAdaptador
    }

    property int cuentaCaptura: 0
    property string capturaPendiente: ""

    // Cierra el panel (para que no salga en la imagen) y captura con la herramienta de niri
    function capturar(tipo, retraso) {
        root.panel = ""
        root.capturaPendiente = tipo
        root.cuentaCaptura = retraso
        if (retraso > 0) cuentaAtras.restart()
        else disparoCaptura.restart()
    }

    Timer {
        id: cuentaAtras
        interval: 1000
        repeat: true
        onTriggered: {
            root.cuentaCaptura--
            if (root.cuentaCaptura <= 0) { stop(); disparoCaptura.restart() }
        }
    }

    Timer {
        id: disparoCaptura
        interval: 400
        onTriggered: {
            var accion = { area: "screenshot", pantalla: "screenshot-screen", ventana: "screenshot-window" }[root.capturaPendiente]
            if (accion) root.ejecutar(["niri", "msg", "action", accion])
        }
    }

    property string modoGrabPendiente: "pantalla"
    property string audioGrabPendiente: "no"
    function grabar(modo, audio) {
        root.panel = ""
        root.modoGrabPendiente = modo
        root.audioGrabPendiente = audio
        inicioGrab.restart()
    }

    Timer {
        id: inicioGrab
        interval: 400
        onTriggered: grabadora.iniciar(root.modoGrabPendiente, root.audioGrabPendiente)
    }

    function avisoCaptura(texto) {
        root.ejecutar(["notify-send", "-a", "Capturas", "-i", "camera-photo", "-t", "2500", texto])
    }

    // Abre el panel de estado directo en una página (desde la barra, el dock o el IPC)
    function abrirPagina(nombre, b) {
        if (root.paginas.indexOf(nombre) < 0) nombre = "inicio"
        var destino = b || (root.panel !== "" ? root.barraActual : root.barraEnfocada)
        if (root.panel !== "estado" || destino !== root.barraActual) {
            if (destino === root.barraActual) root.panel = ""
            root.abrirEn("estado", null, destino, true)
        }
        if (root.mudanza) root.mudanza.pagina = nombre
        else root.pagina = nombre
    }

    // Bluetooth: resumen para la tarjeta de inicio
    property var btAdaptador: Bluetooth.defaultAdapter
    // Conectado de verdad = emparejado + conectado (no el enlace temporal al emparejar)
    property var btConectado: root.btAdaptador ? root.btAdaptador.devices.values.find(d => d.connected && d.paired) || null : null

    // Agente de emparejamiento: siempre activo; si llega un código, abre el panel
    AgenteBluetooth {
        id: agenteBt
        onPidioAtencion: root.abrirPagina("bluetooth")
    }
    function textoBluetooth() {
        if (!root.btAdaptador) return "No instalado"
        if (!root.btAdaptador.enabled) return "Apagado"
        if (root.btConectado) return root.btConectado.name + (root.btConectado.batteryAvailable ? " · " + Math.round(root.btConectado.battery * 100) + "%" : "")
        return "Encendido"
    }

    // ===== Notificaciones (reemplaza a mako) =====
    Avisos {
        id: avisos
        historialVisible: root.panel === "avisos"
        // Al llevar a su destino, el panel de avisos se cierra solo
        onHecho: clave => { if (root.panel === "avisos") root.panel = "" }
        onIrAPagina: nombre => root.abrirPagina(nombre)
        emergentesVisibles: root.panel !== "avisos"
        // En pantalla completa los avisos normales no salen como popup (van al historial); los urgentes sí
        callarPantallaCompleta: root.pantallaCompleta
        modoPantallaCompleta: root.opc("avisos.pantallaCompleta", "campanita")
    }
    CampanitaAvisos {
        id: campanitaAvisos
        s: root
        tema: tema
        av: avisos
    }
    Emergentes {
        s: root
        tema: tema
        av: avisos
        ahora: reloj.date
        // Con el panel de notificaciones abierto ya se ven en la lista
        oculto: root.panel === "avisos"
    }

    // ===== Abrir/cerrar al pasar el cursor =====
    // porClic: abierto con clic/IPC/dock → se queda hasta clic fuera o Esc (como siempre).
    // Abierto al pasar el cursor → se cierra solo al salir del botón y del panel.
    property bool porClic: false
    property string simCursor: ""        // solo para pruebas por IPC: hora|campana|pildora|panel|""
    readonly property string botonBajoCursor:
        root.simCursor === "hora" ? "calendario"
        : root.simCursor === "campana" ? "avisos"
        : root.simCursor === "pildora" ? "estado" : root.botonReal
    readonly property bool cursorEnPanel: root.simCursor === "panel"
        || (root.panel === "estado" && (panelEstado.encima || panelEstado.pulsado || root.cursorEnGracia))
        || (root.relojAbierto && (panelCal.encima || panelCal.pulsado))
    // Diálogos de confirmación abiertos (no cerrar aunque el cursor salga)
    readonly property bool hayDialogo: agenteBt.solicitud !== null
        || (root.panel === "estado" && (pagWifi.confirmarOlvidar !== "" || pagSistema.confirmar >= 0
            || pagEnergia.pendiente !== "" || pagCapturas.confirmarBorrar))
    readonly property bool escribiendo: raizCapa.escribiendo
    readonly property bool retener: root.escribiendo || root.hayDialogo
    readonly property bool debeCerrar: root.abrirAlPasar && root.panel !== "" && !root.porClic
        && !root.cursorEnPanel && root.botonBajoCursor === "" && !root.retener

    onDebeCerrarChanged: debeCerrar ? timerCerrar.restart() : timerCerrar.stop()
    // Cambiar de página NO deja el panel fijo (solo retienen: escribir, arrastrar o un diálogo).
    // Pero la página nueva puede ser más baja y dejar el cursor fuera de la caja: mientras el cursor
    // siga dentro del rectángulo que ocupaba el panel antes del cambio ("zona de gracia") cuenta como
    // dentro; al salir de esa zona (o al cerrarse el panel) la gracia se acaba y cierra como siempre.
    property bool enGracia: false
    property rect zonaGracia: Qt.rect(0, 0, 0, 0)
    readonly property bool cursorEnZona: cursorCapa.hovered
        && cursorCapa.point.position.x >= root.zonaGracia.x
        && cursorCapa.point.position.x <= root.zonaGracia.x + root.zonaGracia.width
        && cursorCapa.point.position.y >= root.zonaGracia.y
        && cursorCapa.point.position.y <= root.zonaGracia.y + root.zonaGracia.height
    readonly property bool cursorEnGracia: root.enGracia && root.cursorEnZona
    onCursorEnZonaChanged: if (!root.cursorEnZona) root.enGracia = false
    onPaginaChanged: {
        if (root.panel !== "estado") return
        // altoFinal tiene Behavior: aquí todavía vale el alto de la página anterior
        root.zonaGracia = Qt.rect(panelEstado.xFinal, panelEstado.arriba, panelEstado.anchoFinal,
            Math.max(panelEstado.altoFinal, 36 + colEstado.implicitHeight))
        root.enGracia = true
    }
    onPanelChanged: { if (root.panel === "") { root.porClic = false; root.enGracia = false } root.tPanel = Date.now() }

    // Suelta el foco de un campo de texto (vuelve a la capa: Esc sigue funcionando) para que el
    // panel deje de retenerse en cuanto terminas de escribir
    function soltarFoco() { raizCapa.forceActiveFocus() }
    // Clic dentro de un panel: si hay un campo de texto con foco y el clic no fue en su marco
    // (el campo + su ojito), el foco se suelta
    function revisarFoco(pos) {
        var f = raizCapa.Window.activeFocusItem
        if (!f || f === raizCapa || f.cursorPosition === undefined) return
        var marco = f.parent || f
        var q = marco.mapFromItem(null, pos.x, pos.y)
        if (q.x < 0 || q.y < 0 || q.x > marco.width || q.y > marco.height) root.soltarFoco()
    }
    // Solo para medir por IPC (hola hover): momento del último cursor simulado y del último cambio de panel
    property real tCursor: 0
    property real tPanel: 0
    // Tras un clic en la campanita de pantalla completa la barra baja bajo el cursor: no debe cambiar de panel por eso
    property real ignorarAbrirHasta: 0
    // ¿Hay que abrir otro panel, o el mismo en otro monitor?
    readonly property bool quiereAbrir: root.botonBajoCursor !== "" && (root.botonBajoCursor !== root.panel
        || (root.barraEncima !== null && root.barraEncima !== root.barraActual))
    onQuiereAbrirChanged: revisarAbrir()
    onBotonBajoCursorChanged: revisarAbrir()
    onBarraEncimaChanged: revisarAbrir()
    function revisarAbrir() {
        if (root.abrirAlPasar && root.quiereAbrir) timerAbrir.restart()
        else timerAbrir.stop()
    }
    Timer {
        id: timerAbrir
        interval: root.esperaAbrir
        // Si estás escribiendo o hay una confirmación, no cambia de panel
        onTriggered: if (root.quiereAbrir && !root.retener && Date.now() >= root.ignorarAbrirHasta)
            root.abrirAlPasarSobre(root.botonBajoCursor, root.barraEncima)
    }
    Timer {
        id: timerCerrar
        interval: root.esperaCerrar
        onTriggered: if (root.debeCerrar) root.panel = ""
    }
    // ===== Monitores: aviso al conectar o desconectar =====
    // Quickshell avisa de cambios en las pantallas; niri dice cuáles siguen conectadas (una apagada sigue en su lista,
    // así que apagarla desde Ajustes no cuenta como desconectar).
    property var monitores: null         // { conector: "Marca Modelo" }; null = aún sin leer (arrancar no avisa)
    // Red de seguridad: hay monitores conectados y ninguno encendido (se desconectó el único encendido, o la interna
    // está guardada como apagada). Devuelve cuál encender: la interna, o el primero. "" si no hace falta.
    function pantallaARescatar(d) {
        var nombres = Object.keys(d)
        if (nombres.length === 0 || nombres.some(k => d[k].logical)) return ""
        return nombres.find(k => /^(eDP|LVDS|DSI)/.test(k)) || nombres.sort()[0]
    }
    Connections {
        target: Quickshell
        function onScreensChanged() { leerMonitores.restart() }
    }
    Timer { id: leerMonitores; interval: 800; onTriggered: pMonitores.running = true }   // un monitor tarda en aparecer
    Process {
        id: pMonitores
        command: ["niri", "msg", "-j", "outputs"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var d
                try { d = JSON.parse(text) } catch (e) { return }
                var rescatar = root.pantallaARescatar(d)
                if (rescatar !== "") {
                    Quickshell.execDetached(["niri", "msg", "output", rescatar, "on"])
                    root.ejecutar(["notify-send", "-a", "Pantalla", "-i", "video-display",
                                   "-h", "string:x-hola-destino:ajustes:pantalla", "--", "Pantalla encendida",
                                   "No quedaba ninguna encendida: se encendió " + rescatar + "."])
                }
                var ahora = {}
                Object.keys(d).forEach(k => {
                    var n = [d[k].make, d[k].model].filter(x => x && x !== "Unknown").join(" ")
                    ahora[k] = n || (/^Virtual/i.test(k) ? "Monitor virtual" : k)
                })
                // Reflejar otra vez lo que estaba reflejado (no hace nada si no hay modo recordado o ya corre)
                root.ejecutar([Quickshell.env("HOME") + "/.local/bin/espejo.sh", "reanudar"])
                var antes = root.monitores
                root.monitores = ahora
                if (!antes) return
                var script = Quickshell.env("HOME") + "/.local/bin/ajustes-monitor-aviso.sh"
                Object.keys(ahora).filter(k => !(k in antes)).forEach(k =>
                    root.ejecutar([script, "Monitor conectado", ahora[k] + " (" + k + ")"]))
                Object.keys(antes).filter(k => !(k in ahora)).forEach(k =>
                    root.ejecutar([script, "Monitor desconectado", antes[k] + " (" + k + ")"]))
            }
        }
    }

    // ===== Pantalla completa: barra escondida que baja con el cursor =====
    // ===== Pantalla completa =====
    PantallaCompleta { id: pcompleta }
    // simPantallaCompleta: solo pruebas por IPC ("si"|"no"|"" = lo que diga niri). Afecta a todas las barras
    property string simPantallaCompleta: ""

    // ===== Lo que depende de las barras =====
    function barraDe(salida) {
        var l = barras.instances
        for (var i = 0; i < l.length; i++) if (l[i].salida === salida) return l[i]
        return null
    }
    readonly property var barraPrincipal: {
        var l = barras.instances
        var n = Principal.pantalla ? Principal.pantalla.name : ""
        for (var i = 0; i < l.length; i++) if (l[i].salida === n) return l[i]
        return l.length > 0 ? l[0] : null
    }
    // Monitor enfocado: lo dicen los workspaces, sin preguntar a niri cada vez
    readonly property string salidaEnfocada: {
        var w = root.workspaces.find(x => x.is_focused)
        return w ? w.output : ""
    }
    readonly property var barraEnfocada: root.barraDe(root.salidaEnfocada) || root.barraPrincipal
    // La barra de los paneles: la que tiene el botón del que nacen. Solo hay un panel y una capa, en un monitor a la vez
    property string salidaPanel: ""
    readonly property var barraActual: root.barraDe(root.salidaPanel) || root.barraPrincipal
    // Si el monitor del panel desaparece, el panel se cierra
    Connections {
        target: barras
        function onInstancesChanged() {
            if (root.salidaPanel !== "" && !root.barraDe(root.salidaPanel)) {
                root.panel = ""
                root.salidaPanel = ""
                root.mudanza = null
            }
        }
    }
    readonly property string salidaBarra: root.barraActual ? root.barraActual.salida : ""
    // Pantalla completa en el monitor enfocado: solo entonces se callan los avisos normales
    readonly property bool pantallaCompleta: root.barraEnfocada ? root.barraEnfocada.pantallaCompleta : false
    readonly property rect rIzq: root.barraActual ? root.barraActual.rIzq : Qt.rect(0, 0, 0, 0)
    readonly property rect rReloj: root.barraActual ? root.barraActual.rReloj : Qt.rect(0, 0, 0, 0)
    readonly property rect rMusica: root.barraActual ? root.barraActual.rMusica : Qt.rect(0, 0, 0, 0)
    readonly property rect rDer: root.barraActual ? root.barraActual.rDer : Qt.rect(0, 0, 0, 0)
    // Botón bajo el cursor, en cualquier barra
    readonly property var barraEncima: {
        var l = barras.instances
        for (var i = 0; i < l.length; i++) if (l[i].botonEncima !== "") return l[i]
        return null
    }
    readonly property string botonReal: root.barraEncima ? root.barraEncima.botonEncima : ""
    readonly property bool cursorEnMusica: {
        var l = barras.instances
        for (var i = 0; i < l.length; i++) if (l[i].musica.cursorDentro) return true
        return false
    }
    // Las ondas de música solo se paran si no se ve ninguna barra
    readonly property bool todasOcultas: {
        var l = barras.instances
        if (l.length === 0) return false
        for (var i = 0; i < l.length; i++) if (!l[i].barraOculta) return false
        return true
    }

    function abrirAlPasarSobre(nombre, b) {
        b = b || root.barraActual
        if (root.panel === nombre && b === root.barraActual) return
        root.abrirEn(nombre, null, b, false)
    }

    // Abrir en la barra b. Cambiar la capa de monitor la recrea y cortaría la animación: si hay algo a la vista en el
    // otro monitor, primero se cierra y luego se abre aquí. En el mismo monitor sigue transformándose como siempre.
    property var mudanza: null            // { nombre, desde, salida, fijo, pagina }
    function abrirEn(nombre, desde, b, fijo) {
        b = b || root.barraActual
        if (!b) return
        if (b !== root.barraActual && (root.panel !== "" || panelEstado.vivo || panelCal.vivo)) {
            root.mudanza = { nombre: nombre, desde: desde, salida: b.salida, fijo: fijo, pagina: "" }
            root.panel = ""
            timerMudanza.restart()
            return
        }
        root.mudanza = null
        timerMudanza.stop()
        root.salidaPanel = b.salida
        if (root.panel === nombre) { root.porClic = fijo; return }
        root.mostrarPanel(nombre, desde)
        root.porClic = fijo
    }
    Timer {
        id: timerMudanza
        interval: 130     // lo que tarda en cerrarse (120 ms)
        onTriggered: {
            var m = root.mudanza
            root.mudanza = null
            if (!m || !root.barraDe(m.salida)) return
            root.salidaPanel = m.salida
            root.mostrarPanel(m.nombre, m.desde)
            root.porClic = m.fijo
            if (m.pagina !== "") root.pagina = m.pagina
        }
    }

    // Clic en un botón, IPC o dock: abre/cierra como siempre.
    // Si ya estaba abierto al pasar el cursor, el clic lo deja fijo (no lo cierra).
    // b: la barra del botón pulsado. Sin ella (IPC, atajos), el monitor enfocado si no hay nada abierto.
    function alternar(nombre, desde, b) {
        timerAbrir.stop()
        if (b && b !== root.barraActual && root.panel !== "") { root.abrirEn(nombre, desde, b, true); return }
        if (root.panel === nombre && !root.porClic) { root.porClic = true; return }
        if (root.panel === "") { root.abrirEn(nombre, desde, b || root.barraEnfocada, true); return }
        root.mostrarPanel(nombre, desde)
        root.porClic = root.panel !== ""
    }

    // Abre/cierra un panel guardando desde qué botón nace
    function mostrarPanel(nombre, desde) {
        if (root.panel === nombre) { root.panel = ""; return }
        // Cada panel nace de su botón (la hora y la campanita son botones distintos)
        var item = desde || (root.barraActual ? root.barraActual.botonDe(nombre) : null)
        if (!item) return
        var pt = item.mapToItem(null, 0, 0)
        var r = Qt.rect(pt.x, pt.y, item.width, item.height)
        if (nombre === "estado") {
            root.origenEstado = r
            root.pagina = "inicio"
        } else if (nombre === "avisos") {
            root.origenAvisos = r
            root.modoReloj = "avisos"
            avisos.sinLeer = 0
            avisos.nuevosPC = 0
        } else {
            root.origenCal = r
            root.modoReloj = "calendario"
            var h = new Date()
            root.mesVista = new Date(h.getFullYear(), h.getMonth(), 1)
        }
        root.panel = nombre
    }

    function procesarSistema(t) {
        var l = t.trim().split("\n")
        // CPU: diferencia entre dos lecturas de /proc/stat
        var c = l[0].trim().split(/\s+/).slice(1).map(Number)
        var total = c.reduce((a, b) => a + b, 0)
        var idle = c[3] + (c[4] || 0)
        var dt = total - root.cpuPrevio[0]
        var di = idle - root.cpuPrevio[1]
        if (root.cpuPrevio[0] > 0 && dt > 0) root.cpu = Math.round(100 * (1 - di / dt))
        root.cpuPrevio = [total, idle]
        // RAM
        var mt = parseInt(l[1].split(/\s+/)[1])
        var ma = parseInt(l[2].split(/\s+/)[1])
        root.ram = Math.round(100 * (1 - ma / mt))
        // Temperatura (en milésimas de grado)
        root.temp = Math.round(parseInt(l[3]) / 1000)
        // Brillo: "dispositivo,clase,actual,porcentaje%,max"
        // No pisar el valor mientras arrastras o hay un cambio en camino
        if (l[4] && !root.arrastrandoBrillo && !aplicarBrillo.running && !pBrillo.running)
            root.brillo = parseInt(l[4].split(",")[3])
    }

    // ===== IPC: qs -c hola ipc call hola <función> =====
    IpcHandler {
        target: "hola"
        function estado(): string { root.alternar("estado"); return root.panel }
        function calendario(): string { root.alternar("calendario"); return root.panel }
        // Panel de notificaciones (como el clic en la campanita)
        function campana(): string { root.alternar("avisos"); return root.panel }
        // Lo que la barra está usando de la app de Ajustes
        function ajustes(): string {
            return JSON.stringify({ conf: root.conf, esperaAbrir: root.esperaAbrir, esperaCerrar: root.esperaCerrar,
                altoSensor: root.altoSensor, abrirAlPasar: root.abrirAlPasar, verMusica: root.verMusica,
                islaIzq: root.barraActual ? root.barraActual.verIslaIzq : false, campana: root.barraActual ? root.barraActual.verCampana : false, esperaOcultar: rep.esperaOcultar })
        }
        // Estado de la píldora de música
        // Lo mismo que el clic en la píldora: enfoca la ventana que suena (o nada) y dice cuál eligió
        function clicMusica(): void { root.enfocarMusica() }
        function musicaVentana(): string { return root.musicaVentana }
        function musica(): string {
            return JSON.stringify({ presente: rep.presente, sonando: rep.sonando, expandida: root.barraActual ? root.barraActual.musica.expandida : false,
                ancho: root.barraActual ? root.barraActual.musica.width : 0, titulo: rep.titulo, cancion: rep.cancion, artista: rep.artista, app: rep.nombreApp, conControles: !!rep.activo,
                giro: root.barraActual ? Math.round(root.barraActual.musica.velocidad * 10) / 10 : 0,
                brazo: root.barraActual ? root.barraActual.musica.brazoApoyado : false,
                audio: rep.audioConfirmado, quiereOndas: rep.quiereOndas, cavaFallo: rep.cavaFallo, niveles: rep.niveles })
        }
        // Simula dónde está el cursor (hora|campana|pildora|musica|panel|fuera) para probar sin mouse
        function cursor(donde: string): string {
            root.simCursor = donde === "fuera" ? "" : donde
            root.tCursor = Date.now()
            return JSON.stringify({ panel: root.panel, porClic: root.porClic, bajoCursor: root.botonBajoCursor,
                enPanel: root.cursorEnPanel, retener: root.retener })
        }
        function hover(): string {
            return JSON.stringify({ panel: root.panel, salida: root.salidaPanel, enfocada: root.salidaEnfocada,
                porClic: root.porClic, bajoCursor: root.botonBajoCursor,
                enPanel: root.cursorEnPanel, escribiendo: root.escribiendo, dialogo: root.hayDialogo,
                gracia: root.enGracia, pulsado: panelEstado.pulsado || panelCal.pulsado,
                abriendo: timerAbrir.running, cerrando: timerCerrar.running,
                msCursorAPanel: root.tPanel >= root.tCursor ? root.tPanel - root.tCursor : -1 })
        }
        function cerrar(): void { root.panel = "" }
        // Estado de la pantalla completa (lo que dice niri y lo que hace la barra)
        function pantallaCompleta(): string {
            return JSON.stringify({ salida: root.salidaEnfocada, pantallaCompleta: root.pantallaCompleta,
                niri: pcompleta.porSalida, ventana: pcompleta.ventanaPorSalida, vistaGeneral: pcompleta.vistaGeneral,
                simulada: root.simPantallaCompleta, revelada: root.barraEnfocada ? root.barraEnfocada.barraRevelada : false,
                oculta: root.barraEnfocada ? root.barraEnfocada.barraOculta : false,
                cursorArriba: root.barraEnfocada ? root.barraEnfocada.cursorArriba : false, zona: root.barraEnfocada ? root.barraEnfocada.zona : 0,
                avisosCallados: avisos.callarPC, modoAvisos: avisos.modoPantallaCompleta,
                campanita: { activa: campanitaAvisos.activa, salida: campanitaAvisos.salida, encima: campanitaAvisos.encima,
                             numero: avisos.nuevosPC, titulo: avisos.tituloPC } })
        }
        // Para probar la red de seguridad con datos inventados: qué pantalla encendería (no enciende nada)
        function rescatePantalla(salidas: string): string { return root.pantallaARescatar(JSON.parse(salidas)) }
        // Cada barra: su monitor, workspaces, ventana activa y pantalla completa
        function barras(): string {
            var r = []
            var l = barras.instances
            for (var i = 0; i < l.length; i++) r.push({ salida: l[i].salida, principal: root.barraPrincipal === l[i], conPanel: l[i].conPanel,
                workspaces: l[i].workspaces.map(w => (w.is_active ? "*" : "") + w.idx), ventana: l[i].appVentana,
                conTitulo: l[i].tituloVentana !== "", pantallaCompleta: l[i].pantallaCompleta, oculta: l[i].barraOculta,
                cursorArriba: l[i].cursorArriba, zona: l[i].zona, musica: l[i].musica.visible })
            return JSON.stringify(r)
        }
        // si | no | auto (para probar sin una ventana a pantalla completa)
        function simularPantallaCompleta(v: string): string {
            root.simPantallaCompleta = v === "auto" ? "" : v
            return root.pantallaCompleta ? "si" : "no"
        }
        // ----- Notificaciones -----
        // qs -c hola ipc call hola notificaciones   → estado + historial (JSON)
        function notificaciones(): string {
            var l = []
            for (var i = 0; i < avisos.historial.count; i++) {
                var f = avisos.historial.get(i)
                l.push({ i: i, app: f.app, resumen: f.resumen, cuerpo: f.cuerpo, icono: f.icono, imagen: f.imagen,
                    urgencia: f.urgencia, duracion: f.duracion, acciones: JSON.parse(f.acciones), vivo: f.vivo,
                    destino: f.destino, botones: JSON.parse(f.botones || "[]"), entrada: f.entrada, nota: f.nota })
            }
            var e = []
            for (var j = 0; j < avisos.emergentes.count; j++) e.push(avisos.emergentes.get(j).resumen)
            return JSON.stringify({ noMolestar: avisos.noMolestar, sinLeer: avisos.sinLeer,
                emergentes: e, historial: l }, null, 1)
        }
        // si | no | alternar
        function noMolestar(v: string): string {
            avisos.ponerNoMolestar(v === "alternar" ? !avisos.noMolestar : v === "si")
            return avisos.noMolestar ? "si" : "no"
        }
        function limpiarAvisos(): void { avisos.limpiar() }
        // i = posición en el historial (0 = la más nueva)
        function accionAviso(i: int, id: string): string {
            if (i < 0 || i >= avisos.historial.count) return "no existe"
            if (id.startsWith("hola:")) { avisos.activar(avisos.historial.get(i).clave, id); return "ok" }
            return avisos.invocar(avisos.historial.get(i).clave, id) ? "ok" : "sin esa acción"
        }
        function descartarAviso(i: int): string {
            if (i < 0 || i >= avisos.historial.count) return "no existe"
            avisos.descartar(avisos.historial.get(i).clave)
            return "ok"
        }
        function clicAviso(i: int): string {
            if (i < 0 || i >= avisos.historial.count) return "no existe"
            avisos.clicCuerpo(avisos.historial.get(i).clave)
            return "ok"
        }
        // qs -c hola ipc call hola pagina wifi|bluetooth|audio|sistema|energia|inicio
        function pagina(nombre: string): string { root.abrirPagina(nombre); return root.pagina }
        // Desde el dock: en el monitor del dock que recibió el clic
        function paginaEn(nombre: string, salida: string): string { root.abrirPagina(nombre, root.barraDe(salida)); return root.pagina }
        // Grabar pantalla: inicia (pantalla completa, último audio elegido) o detiene
        function grabar(): string { if (grabadora.grabando) grabadora.detener(); else root.grabar("pantalla", grabadora.audio); return grabadora.grabando ? "deteniendo" : "iniciando" }
        function grabacion(): string { return JSON.stringify({ grabando: grabadora.grabando, procesando: grabadora.procesando, segundos: grabadora.segundos, ruta: grabadora.ruta, error: grabadora.error }) }
        function capturar(tipo: string, retraso: int): void { root.capturar(tipo, retraso) }
        function grabarCon(modo: string, audio: string): void { root.grabar(modo, audio) }
        function info(): string {
            return JSON.stringify({ panel: root.panel, volumen: root.volumen, silencio: root.silencio,
                brillo: root.brillo, cpu: root.cpu, ram: root.ram, temp: root.temp,
                wifi: root.wifiNombre, senal: root.wifiSenal, bateria: root.bateria,
                cargando: root.cargando, tiempo: root.tiempoBateria(),
                mes: Qt.formatDate(root.mesVista, "yyyy-MM"), bandeja: SystemTray.items.values.length,
                jugador: root.jugador ? (root.jugador.trackTitle || "?") : "",
                btAgente: agenteBt.registrado, btSolicitud: agenteBt.solicitud, btOperacion: agenteBt.operacion,
                btAviso: agenteBt.aviso })
        }
        // ----- Energía -----
        // Luz nocturna: si | no | alternar | sol | siempre | apagada | info
        function luzNocturna(v: string): string {
            if (v === "si") luz.ponerModo(luz.ultimoModo || "sol")
            else if (v === "no") luz.ponerModo("apagada")
            else if (v === "alternar") luz.alternar()
            else if (v !== "info" && v !== "") luz.ponerModo(v)
            return JSON.stringify(luz.info())
        }
        function ubicacionNocturna(lat: real, lon: real): string { luz.ponerUbicacion(lat, lon); return "ok" }
        function temperaturaNocturna(k: int): string { luz.ponerTemperatura(k); return String(luz.temperatura) }
        // Límite de carga: si | no | info
        function bateriaLimite(v: string): string {
            if (v === "si" || v === "no") limite.poner(v === "si")
            return JSON.stringify(limite.info())
        }
        // Modo de energía: ahorro | equilibrado | rendimiento | info
        function perfilEnergia(v: string): string {
            if (v !== "info" && v !== "" && !root.ponerPerfil(v)) return "no disponible: " + v
            return root.textoPerfil()
        }
        // Mismas funciones que llaman los clics, para probarlas sin mouse
        // Avisos de batería, Wi-Fi y Bluetooth con valores inventados: bateria 16,15 · wifi Casa, · bt Auriculares,
        function probarAvisoSistema(tipo: string, valor: string): string { return avisosSistema.probar(tipo, valor) }
        function probar(accion: string, valor: real): string {
            if (accion === "silenciar") root.silenciar()
            else if (accion === "volumen") root.ponerVolumen(valor)
            else if (accion === "brillo") root.soltarBrillo(valor)
            else if (accion === "arrastre") {
                root.simDesde = root.brillo / 100
                root.simHasta = valor
                root.simPaso = 0
                root.simulandoArrastre = true
                simArrastre.restart()
            }
            else if (accion === "mes") root.moverMes(valor)
            else if (accion === "dialogo") pagCapturas.confirmarBorrar = valor > 0
            else return "acción desconocida"
            return accion + " ok"
        }
    }

    // ===== niri: escucha eventos y refresca al instante =====
    Process {
        id: eventos
        command: ["niri", "msg", "-j", "event-stream"]
        running: true
        stdout: SplitParser {
            onRead: data => refrescoNiri.restart()
        }
        onExited: reinicioEventos.start()
    }

    Timer {
        id: reinicioEventos
        interval: 2000
        onTriggered: eventos.running = true
    }

    Timer {
        id: refrescoNiri
        interval: 60
        onTriggered: {
            pWorkspaces.running = true
            pVentanas.running = true
        }
    }

    Process {
        id: pWorkspaces
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.workspaces = JSON.parse(text).sort((a, b) => a.idx - b.idx) } catch (e) {}
            }
        }
    }

    Process {
        id: pVentanas
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.ventanas = JSON.parse(text) } catch (e) {}
            }
        }
    }

    // ===== Sistema (CPU, RAM, temperatura, brillo) cada 2 s =====
    Process {
        id: pSistema
        command: ["sh", "-c", "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; cat /sys/class/thermal/thermal_zone0/temp; brightnessctl -m"]
        stdout: StdioCollector {
            onStreamFinished: root.procesarSistema(text)
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: pSistema.running = true
    }

    Timer {
        id: actualizarBrillo
        interval: 150
        onTriggered: pSistema.running = true
    }

    // ===== Wifi cada 10 s =====
    Process {
        id: pWifi
        command: ["sh", "-c", "nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi list --rescan no | grep '^yes'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var s = text.trim()
                if (s === "") {
                    root.wifiNombre = ""
                    root.wifiSenal = -1
                    return
                }
                var p = s.split("\n")[0].split(":")
                root.wifiSenal = parseInt(p[p.length - 1])
                root.wifiNombre = p.slice(1, p.length - 1).join(":")
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: pWifi.running = true
    }

    Component.onCompleted: refrescoNiri.start()

    // ===== La barra =====
    // ===== Las barras =====
    // Una por monitor. Lo de cada barra (workspaces, ventana activa, pantalla completa, botones, máscara) vive en su
    // "barra"; lo demás es común y está en root. La capa de paneles sigue a root.barraActual.
    // Dentro de Variants no hace falta Principal.lista: cada pantalla crea y destruye sus propias ventanas.
    Variants {
        id: barras
        model: Principal.pantallas
        delegate: Scope {
            id: barra
            required property var modelData
            readonly property string salida: modelData.name
            // Dentro de un delegado, "tema: tema" se enlazaría consigo mismo: las piezas usan estos dos
            readonly property var colores: tema
            readonly property var repro: rep

            // ----- Workspaces y ventana activa de este monitor -----
            readonly property bool conPanel: root.barraActual === barra
            readonly property var workspaces: root.workspaces.filter(w => w.output === barra.salida)
            readonly property var ventanaActiva: {
                var w = barra.workspaces.find(x => x.is_active)
                return w && w.active_window_id !== null ? root.ventanas.find(v => v.id === w.active_window_id) || null : null
            }
            readonly property string tituloVentana: barra.ventanaActiva ? (barra.ventanaActiva.title || "") : ""
            readonly property string appVentana: barra.ventanaActiva ? (barra.ventanaActiva.app_id || "") : ""
            // focus-workspace actúa sobre el monitor enfocado: primero hay que enfocar este
            function irAWorkspace(idx) {
                root.ejecutar(["sh", "-c", 'niri msg action focus-monitor "$1" && niri msg action focus-workspace "$2"', "sh", barra.salida, String(idx)])
            }

            // ----- Pantalla completa: barra escondida que baja con el cursor -----
            readonly property bool pantallaCompleta: root.esconderEnPantallaCompleta
                && (root.simPantallaCompleta !== "" ? root.simPantallaCompleta === "si" : pcompleta.en(barra.salida))
            property bool barraRevelada: false
            readonly property bool barraOculta: barra.pantallaCompleta && !barra.barraRevelada
            // El cursor está en el sensor o en la franja de la barra (o simulado por IPC), o hay un panel
            readonly property bool mantenerBarra: hoverBarra.hovered || root.simCursor !== "" || (barra.conPanel && root.panel !== "")
            onPantallaCompletaChanged: barra.revisarBarra()
            onMantenerBarraChanged: barra.revisarBarra()
            function revisarBarra() {
                if (!barra.pantallaCompleta) { timerRevelar.stop(); timerEsconder.stop(); barra.barraRevelada = false; return }
                if (barra.mantenerBarra) { timerEsconder.stop(); if (!barra.barraRevelada) timerRevelar.restart() }
                else { timerRevelar.stop(); if (barra.barraRevelada) timerEsconder.restart() }
            }
            Timer {
                id: timerRevelar
                // Un panel abierto por IPC/atajo/dock (sin cursor) baja la barra al instante
                interval: root.panel !== "" ? 0 : root.esperaAbrir
                onTriggered: if (barra.pantallaCompleta && barra.mantenerBarra) barra.barraRevelada = true
            }
            Timer {
                id: timerEsconder
                interval: root.esperaCerrar
                onTriggered: if (!barra.mantenerBarra) barra.barraRevelada = false
            }

            // ----- Lo que necesitan root y la capa de paneles -----
            readonly property string botonEncima: botonReloj.encima ? "calendario"
                : campana.encima ? "avisos"
                : maPildora.containsMouse ? "estado" : ""
            function botonDe(nombre) { return nombre === "estado" ? pildora : nombre === "avisos" ? campana : botonReloj }
            readonly property var musica: pildoraMusica
            readonly property bool cursorArriba: hoverBarra.hovered
            readonly property int zona: ventana.exclusiveZone
            readonly property bool verIslaIzq: islaIzq.visible
            readonly property bool verCampana: campana.visible
            // Posición final de las islas (la capa de paneles las deja fuera de su máscara)
            readonly property rect rIzq: Qt.rect(islaIzq.x, islaIzq.y, islaIzq.visible ? islaIzq.width : 0, islaIzq.height)
            readonly property rect rReloj: Qt.rect(islaReloj.x, islaReloj.y, islaReloj.width, islaReloj.height)
            readonly property rect rMusica: Qt.rect(pildoraMusica.x, pildoraMusica.y, rep.presente && root.verMusica ? pildoraMusica.width : 0, pildoraMusica.height)
            readonly property rect rDer: Qt.rect(islaDer.x, islaDer.y, islaDer.width, islaDer.height)

            PanelWindow {
                screen: barra.modelData
                id: ventana
                anchors {
                    top: true
                    left: true
                    right: true
                }
                implicitHeight: root.altoIsla + 20
                // En pantalla completa no reserva espacio (la ventana ocupa todo y la barra baja encima)
                exclusionMode: barra.pantallaCompleta ? ExclusionMode.Ignore : ExclusionMode.Normal
                exclusiveZone: barra.pantallaCompleta ? 0 : root.altoIsla + 12
                color: "transparent"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "hola"

                // Normal: las islas son lo único clicable; el resto deja pasar el mouse.
                // Pantalla completa escondida: solo el sensor fino del borde de arriba.
                // Pantalla completa bajada: toda la franja (pasar de una isla a otra no la esconde).
                mask: barra.pantallaCompleta ? (barra.barraRevelada ? regionFranja : regionSensor) : regionIslas
                // Coordenadas explícitas, NO `Region { item: … }`: con `item` Quickshell mide la isla con sus
                // transformaciones (Translate de entrada y de pantalla completa) y solo vuelve a medir cuando
                // cambian su x/y/ancho/alto, no cuando termina la animación. Al salir de pantalla completa la
                // medía aún escondida arriba (fuera de la ventana) y la barra se quedaba sin recibir el cursor.
                // Así la máscara está siempre en la posición final de las islas, también durante la bajada.
                property Region regionIslas: Region {
                    Region { x: islaIzq.x; y: islaIzq.y; width: islaIzq.visible ? islaIzq.width : 0; height: islaIzq.height }
                    Region { x: islaReloj.x; y: islaReloj.y; width: islaReloj.width; height: islaReloj.height }
                    Region { x: pildoraMusica.x; y: pildoraMusica.y; width: rep.presente && root.verMusica ? pildoraMusica.width : 0; height: pildoraMusica.height }
                    Region { x: islaDer.x; y: islaDer.y; width: islaDer.width; height: islaDer.height }
                }
                property Region regionSensor: Region { x: 0; y: 0; width: ventana.width; height: root.altoSensor }
                property Region regionFranja: Region { x: 0; y: 0; width: ventana.width; height: ventana.height }

                Item {
                    anchors.fill: parent

                    // No se desplaza: así cubre el sensor aunque las islas estén escondidas arriba
                    HoverHandler { id: hoverBarra }

                    // Entrada con rebote al arrancar
                    Item {
                        anchors.fill: parent
                        opacity: root.mostrar ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: 250 }
                        }
                        transform: [
                            Translate {
                                y: root.mostrar ? 0 : -(root.altoIsla + 30)
                                Behavior on y {
                                    NumberAnimation { duration: 400; easing.type: Easing.OutBack }
                                }
                            },
                            // Pantalla completa: sube y baja (sin rebote: 150 ms al bajar, 120 al subir)
                            Translate {
                                y: barra.barraOculta ? -(root.altoIsla + 20) : 0
                                Behavior on y {
                                    NumberAnimation {
                                        duration: barra.barraOculta ? 120 : 150
                                        easing.type: barra.barraOculta ? Easing.InCubic : Easing.OutCubic
                                    }
                                }
                            }
                        ]

                        // ---------- Isla izquierda: workspaces + ventana activa ----------
                        Rectangle {
                            id: islaIzq
                            visible: root.opc("barra.islaIzq", true)
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            height: root.altoIsla
                            width: filaIzq.width + 16
                            radius: root.altoIsla / 2
                            color: root.alfa(tema.surface, root.opacidadIsla)
                            border.color: root.alfa(tema.primary, 0.5)
                            border.width: 1.5
                            Behavior on width {
                                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                            }

                            Row {
                                id: filaIzq
                                anchors.centerIn: parent
                                spacing: 6

                                // Workspaces como pastillas
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    leftPadding: 6
                                    rightPadding: 4

                                    Repeater {
                                        model: barra.workspaces.length

                                        delegate: Rectangle {
                                            id: pill
                                            required property int index
                                            property var ws: barra.workspaces[pill.index] || ({})
                                            property bool activo: pill.ws.is_active === true

                                            anchors.verticalCenter: parent.verticalCenter
                                            height: 10
                                            width: pill.activo ? 30 : (maWs.containsMouse ? 16 : 10)
                                            radius: 5
                                            color: pill.activo ? tema.primary
                                                : root.alfa(tema.surfaceText, maWs.containsMouse ? 0.6 : 0.3)
                                            Behavior on width {
                                                NumberAnimation { duration: 300; easing.type: Easing.OutBack }
                                            }
                                            Behavior on color {
                                                ColorAnimation { duration: 200 }
                                            }

                                            MouseArea {
                                                id: maWs
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: barra.irAWorkspace(pill.ws.idx)
                                            }
                                        }
                                    }
                                }

                                // Ventana activa: clic abre la vista general de niri
                                Boton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: barra.tituloVentana !== "" && root.opc("barra.titulo", true)
                                    tema: barra.colores
                                    imagen: root.iconoApp(barra.appVentana)
                                    texto: barra.tituloVentana
                                    anchoMaxTexto: 320
                                    onClic: root.ejecutar(["niri", "msg", "action", "toggle-overview"])
                                }
                            }
                        }

                        // ---------- Reproduciendo ahora: a la izquierda de la hora, crece hacia la izquierda ----------
                        PildoraMusica {
                            id: pildoraMusica
                            anchors.right: islaReloj.left
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            rep: barra.repro
                            s: root
                            tema: barra.colores
                            simEncima: root.simCursor === "musica"
                            disponible: islaReloj.x - 8 - (islaIzq.visible ? islaIzq.x + islaIzq.width + 8 : 10)
                            habilitada: root.verMusica
                            onAbrir: root.enfocarMusica()
                        }

                        // ---------- Isla central: hora (abre el calendario) ----------
                        Rectangle {
                            id: islaReloj
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            height: root.altoIsla
                            width: filaReloj.width + 16
                            radius: root.altoIsla / 2
                            color: root.alfa(tema.surface, root.opacidadIsla)
                            border.color: root.alfa(tema.primary, 0.5)
                            border.width: 1.5
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }

                            // Dos botones con su propio fondo: hora/fecha → calendario · campanita → notificaciones
                            Row {
                                id: filaReloj
                                anchors.centerIn: parent
                                spacing: 4
                                Boton {
                                    id: botonReloj
                                    tema: barra.colores
                                    activo: barra.conPanel && root.panel === "calendario"
                                    icono: Qt.formatDateTime(reloj.date, "hh:mm")
                                    texto: root.opc("barra.fecha", true) ? reloj.date.toLocaleDateString(Qt.locale("es_EC"), "ddd d MMM") : ""
                                    onClic: root.alternar("calendario", null, barra)
                                }
                                // Campanita (siempre visible): tachada = No molestar; con número = avisos sin ver
                                Boton {
                                    id: campana
                                    visible: root.opc("barra.campana", true)
                                    tema: barra.colores
                                    activo: barra.conPanel && root.panel === "avisos"
                                    icono: root.ic(avisos.noMolestar ? 0xF009B : avisos.sinLeer > 0 ? 0xF116B : 0xF009C)
                                    colorIcono: avisos.noMolestar ? root.alfa(tema.surfaceText, 0.6) : tema.primary
                                    texto: avisos.sinLeer > 0 ? String(Math.min(avisos.sinLeer, 99)) : ""
                                    onClic: root.alternar("avisos", null, barra)
                                }
                            }
                        }

                        // ---------- Isla derecha: bandeja + píldora de estado ----------
                        Rectangle {
                            id: islaDer
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            height: root.altoIsla
                            width: filaDer.width + 12
                            radius: root.altoIsla / 2
                            color: root.alfa(tema.surface, root.opacidadIsla)
                            border.color: root.alfa(tema.primary, 0.5)
                            border.width: 1.5
                            Behavior on width {
                                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                            }

                            Row {
                                id: filaDer
                                anchors.centerIn: parent
                                spacing: 4

                                // Extras locales (opcional, no van en el repositorio): cada .qml que haya en
                                // ~/.local/share/hola/extras se muestra aquí, al inicio de la isla derecha.
                                // Si existen, se les dan: tema (colores de matugen), s (la barra: alfa, fuente,
                                // altoIsla…) y principal (true solo en la barra del monitor principal, para que
                                // algo único, como un IpcHandler, no se repita en cada monitor).
                                // Sin la carpeta o vacía: no hay nada y la barra sigue igual.
                                // Si la carpeta se crea con la barra ya abierta, hace falta reiniciarla una vez.
                                Repeater {
                                    model: FolderListModel {
                                        folder: "file://" + Quickshell.env("HOME") + "/.local/share/hola/extras"
                                        nameFilters: ["*.qml"]
                                        showDirs: false
                                        sortField: FolderListModel.Name
                                    }
                                    delegate: Loader {
                                        required property url fileUrl
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: fileUrl
                                        onLoaded: {
                                            if ("tema" in item) item.tema = Qt.binding(() => tema)
                                            if ("s" in item) item.s = root
                                            if ("principal" in item) item.principal = Qt.binding(() => root.barraPrincipal === barra)
                                        }
                                    }
                                }

                                // Bandeja del sistema (solo si hay iconos)
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: SystemTray.items.values.length > 0 && root.opc("barra.bandeja", true)
                                    spacing: 2
                                    leftPadding: 4

                                    Repeater {
                                        model: SystemTray.items

                                        delegate: Item {
                                            id: icBandeja
                                            required property var modelData
                                            width: 26
                                            height: 26

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: width / 2
                                                color: tema.primary
                                                opacity: maBandeja.containsMouse ? 0.18 : 0
                                                Behavior on opacity {
                                                    NumberAnimation { duration: 150 }
                                                }
                                            }

                                            Image {
                                                anchors.centerIn: parent
                                                width: 16
                                                height: 16
                                                sourceSize.width: 32
                                                sourceSize.height: 32
                                                source: icBandeja.modelData.icon
                                            }

                                            MouseArea {
                                                id: maBandeja
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: m => {
                                                    var it = icBandeja.modelData
                                                    if (m.button === Qt.MiddleButton) it.secondaryActivate()
                                                    else if (m.button === Qt.RightButton || it.onlyMenu) {
                                                        if (it.hasMenu) {
                                                            var pt = icBandeja.mapToItem(null, 0, icBandeja.height + 8)
                                                            it.display(ventana, pt.x, pt.y)
                                                        }
                                                    } else it.activate()
                                                }
                                            }
                                        }
                                    }
                                }

                                // Grabando (● 00:12, clic detiene) o cuenta atrás de captura
                                Rectangle {
                                    id: indicadorGrab
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: grabadora.grabando || grabadora.procesando || root.cuentaCaptura > 0
                                    height: 30
                                    width: filaGrab.width + 20
                                    radius: height / 2
                                    color: grabadora.grabando ? Qt.rgba(1, 0.33, 0.33, maGrab.containsMouse ? 0.4 : 0.25) : root.alfa(tema.primary, 0.2)
                                    Row {
                                        id: filaGrab
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Rectangle {
                                            visible: grabadora.grabando
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 9
                                            height: 9
                                            radius: 4.5
                                            color: "#ff5555"
                                            SequentialAnimation on opacity {
                                                running: grabadora.grabando
                                                loops: Animation.Infinite
                                                NumberAnimation { to: 0.25; duration: 600 }
                                                NumberAnimation { to: 1; duration: 600 }
                                            }
                                        }
                                        Text {
                                            text: grabadora.grabando ? (maGrab.containsMouse ? "Detener" : grabadora.tiempo())
                                                : grabadora.procesando ? "Procesando…"
                                                : root.ic(0xF0100) + "  " + root.cuentaCaptura
                                            font.family: root.fuente
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: tema.surfaceText
                                        }
                                    }
                                    MouseArea {
                                        id: maGrab
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: grabadora.grabando ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: if (grabadora.grabando) grabadora.detener()
                                    }
                                }

                                // Cafeína encendida: taza; clic la apaga
                                Rectangle {
                                    id: indicadorCafeina
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.cafeina && root.opc("barra.cafeina", true)
                                    width: 30
                                    height: 30
                                    radius: 15
                                    color: root.alfa(tema.primary, maCafeinaBarra.containsMouse ? 0.35 : 0.2)
                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.ic(0xF0176)
                                        font.family: root.fuente
                                        font.pixelSize: 15
                                        color: tema.primary
                                    }
                                    MouseArea {
                                        id: maCafeinaBarra
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.alternarCafeina()
                                    }
                                }

                                // Píldora de estado: clic abre el panel, rueda cambia el volumen
                                Rectangle {
                                    id: pildora
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 30
                                    width: filaPildora.width + 22
                                    radius: height / 2
                                    color: barra.conPanel && root.panel === "estado" ? root.alfa(tema.primary, 0.28)
                                        : root.alfa(tema.primary, maPildora.containsMouse ? 0.18 : 0.08)
                                    Behavior on color {
                                        ColorAnimation { duration: 180 }
                                    }

                                    Row {
                                        id: filaPildora
                                        anchors.centerIn: parent
                                        spacing: 12
                                        scale: maPildora.pressed ? 0.9 : 1
                                        Behavior on scale {
                                            NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                                        }

                                        Text {
                                            visible: root.opc("barra.iconoWifi", true)
                                            text: root.iconoWifi()
                                            font.family: root.fuente
                                            font.pixelSize: 15
                                            color: tema.primary
                                        }
                                        Text {
                                            visible: root.opc("barra.iconoVolumen", true)
                                            text: root.iconoVolumen()
                                            font.family: root.fuente
                                            font.pixelSize: 15
                                            color: tema.primary
                                        }
                                        Text {
                                            visible: root.opc("barra.iconoBateria", true)
                                            text: root.iconoBateria()
                                            font.family: root.fuente
                                            font.pixelSize: 15
                                            color: (root.bateria <= 15 && !root.cargando) ? "#ff5555" : tema.primary
                                        }
                                    }

                                    MouseArea {
                                        id: maPildora
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: m => m.button === Qt.RightButton ? root.abrirPagina("audio", barra) : root.alternar("estado", null, barra)
                                        onWheel: w => root.cambiarVolumen(w.angleDelta.y > 0 ? 0.02 : -0.02)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ===== Capa de paneles (calendario y estado) =====
    PanelWindow {
        screen: Principal.porNombre(root.salidaPanel) || Principal.pantalla
        id: capa
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        visible: Principal.lista && (root.panel !== "" || panelEstado.vivo || panelCal.vivo)
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hola-paneles"
        // Abierto con clic: teclado exclusivo (como siempre). Abierto al pasar el cursor: el teclado
        // solo viene al panel si haces clic dentro (pasar por la hora no roba lo que escribes).
        // OnDemand solo con el cursor en el panel o escribiendo: con el cursor en un botón de la barra, un clic le daba el
        // foco a esta capa y Qt cancelaba la pulsación del botón (pressed + canceled, sin clicked).
        WlrLayershell.keyboardFocus: root.panel === "" ? WlrKeyboardFocus.None
            : root.porClic ? WlrKeyboardFocus.Exclusive
            : (root.cursorEnPanel || root.escribiendo) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // Las islas de la barra quedan fuera de esta capa: así el cursor y los clics llegan
        // a sus botones aunque haya un panel abierto encima
        mask: Region {
            item: raizCapa
            Region { x: root.rIzq.x; y: root.rIzq.y; width: root.rIzq.width; height: root.rIzq.height; intersection: Intersection.Subtract }
            Region { x: root.rReloj.x; y: root.rReloj.y; width: root.rReloj.width; height: root.rReloj.height; intersection: Intersection.Subtract }
            Region { x: root.rMusica.x; y: root.rMusica.y; width: root.rMusica.width; height: root.rMusica.height; intersection: Intersection.Subtract }
            Region { x: root.rDer.x; y: root.rDer.y; width: root.rDer.width; height: root.rDer.height; intersection: Intersection.Subtract }
        }

        Item {
            id: raizCapa
            anchors.fill: parent
            focus: true
            // Posición del cursor en toda la capa (para la zona de gracia al cambiar de página)
            HoverHandler { id: cursorCapa }
            // ¿Hay un campo de texto con el cursor de escritura? (contraseña wifi, PIN bluetooth…)
            readonly property bool escribiendo: {
                var f = Window.activeFocusItem
                return !!f && f !== raizCapa && f.cursorPosition !== undefined && f.visible && !f.readOnly
            }
            // Esc: en una subpágina vuelve a inicio; en inicio cierra
            Keys.onEscapePressed: {
                if (root.panel === "estado" && root.pagina !== "inicio") root.pagina = "inicio"
                else root.panel = ""
            }

            // Clic fuera de un panel: cerrar
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: root.panel = ""
            }

            // ---------- Panel de estado ----------
            Panel {
                id: panelEstado
                anchors.fill: parent
                tema: tema
                onPresion: pos => root.revisarFoco(pos)
                abierto: root.panel === "estado"
                origen: root.origenEstado
                anchoFinal: 380
                // El alto sigue a la página visible (con animación al cambiar de página)
                altoFinal: 36 + (root.pagina === "wifi" ? pagWifi.implicitHeight
                    : root.pagina === "bluetooth" ? pagBt.implicitHeight
                    : root.pagina === "audio" ? pagAudio.implicitHeight
                    : root.pagina === "sistema" ? pagSistema.implicitHeight
                    : root.pagina === "energia" ? pagEnergia.implicitHeight
                    : root.pagina === "capturas" ? pagCapturas.implicitHeight
                    : root.pagina === "nocturna" ? pagNocturna.implicitHeight
                    : colEstado.implicitHeight)
                Behavior on altoFinal {
                    enabled: panelEstado.p > 0.98
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }

                // ---------- Página: inicio ----------
                Column {
                    id: colEstado
                    property bool activa: root.pagina === "inicio"
                    x: 18 + (activa ? 0 : -40)
                    y: 18
                    width: parent.width - 36
                    spacing: 14
                    opacity: activa ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on x {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 120 }
                    }

                    // Batería + botones de sesión
                    Item {
                        width: parent.width
                        height: 44

                        Text {
                            id: icBat
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.iconoBateria()
                            font.family: root.fuente
                            font.pixelSize: 30
                            color: (root.bateria <= 15 && !root.cargando) ? "#ff5555" : tema.primary
                        }
                        Column {
                            anchors.left: icBat.right
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: root.bateria + "%"
                                font.family: root.fuente
                                font.pixelSize: 18
                                font.bold: true
                                color: tema.surfaceText
                            }
                            Text {
                                text: root.tiempoBateria()
                                font.family: root.fuente
                                font.pixelSize: 11
                                color: root.alfa(tema.surfaceText, 0.65)
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            // Engranaje: app de Ajustes · cámara: capturas y grabación · ⏻: energía
                            Boton {
                                tema: tema; icono: root.ic(0xF0493)
                                onClic: { root.panel = ""; root.ejecutar([Quickshell.env("HOME") + "/.local/bin/ajustes-abrir.sh"]) }
                            }
                            Boton { tema: tema; icono: root.ic(0xF0100); onClic: root.pagina = "capturas" }
                            Boton { tema: tema; icono: root.ic(0xF0425); onClic: root.pagina = "energia" }
                        }
                    }

                    // Volumen
                    Row {
                        width: parent.width
                        spacing: 10
                        Boton {
                            id: btnVol
                            anchors.verticalCenter: parent.verticalCenter
                            tema: tema
                            icono: root.iconoVolumen()
                            onClic: root.silenciar()
                            onClicDerecho: root.pagina = "audio"
                        }
                        // Volumen: PipeWire aguanta cada movimiento, va directo sin limitar
                        Deslizador {
                            id: deslVol
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - btnVol.width - txtVol.width - btnAudio.width - 30
                            tema: tema
                            valor: root.silencio ? 0 : root.volumen / 100
                            onMovido: v => root.ponerVolumen(v)
                            onSoltado: v => root.ponerVolumen(v)
                        }
                        Text {
                            id: txtVol
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            horizontalAlignment: Text.AlignRight
                            text: deslVol.arrastrando ? Math.round(deslVol.vista * 100) + "%"
                                : (root.silencio ? "mudo" : root.volumen + "%")
                            font.family: root.fuente
                            font.pixelSize: 12
                            color: tema.surfaceText
                        }
                        // › abre la página de audio
                        Boton {
                            id: btnAudio
                            anchors.verticalCenter: parent.verticalCenter
                            tema: tema
                            icono: root.ic(0xF0142)
                            onClic: root.pagina = "audio"
                        }
                    }

                    // Brillo
                    Row {
                        width: parent.width
                        spacing: 10
                        Boton {
                            id: btnBrillo
                            anchors.verticalCenter: parent.verticalCenter
                            tema: tema
                            icono: root.ic(0xF00E0)
                            onClic: root.soltarBrillo(root.brillo >= 100 ? 0.25 : Math.min(1, (Math.floor(root.brillo / 25) + 1) * 0.25))
                        }
                        // Brillo: en vivo con throttle de 50 ms; al soltar, valor exacto
                        Deslizador {
                            id: deslBrillo
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - btnBrillo.width - txtBrillo.width - btnAudio.width - 30
                            tema: tema
                            valor: root.brillo / 100
                            onMovido: v => root.ponerBrillo(v)
                            onSoltado: v => root.soltarBrillo(v)
                        }
                        Text {
                            id: txtBrillo
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            horizontalAlignment: Text.AlignRight
                            text: (deslBrillo.arrastrando ? Math.max(1, Math.round(deslBrillo.vista * 100)) : root.brillo) + "%"
                            font.family: root.fuente
                            font.pixelSize: 12
                            color: tema.surfaceText
                        }
                        // Hueco del ancho del botón › para alinear con el volumen
                        Item { width: btnAudio.width; height: 1 }
                    }

                    // Modos de energía (power-profiles-daemon): Ahorro · Equilibrado · Rendimiento
                    Row {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: [
                                { id: "ahorro", icono: 0xF032A, texto: "Ahorro" },
                                { id: "equilibrado", icono: 0xF05D1, texto: "Equilibrado" },
                                { id: "rendimiento", icono: 0xF04C5, texto: "Rendimiento" }
                            ]
                            delegate: Rectangle {
                                id: perfil
                                required property var modelData
                                readonly property bool elegido: root.textoPerfil() === perfil.modelData.id
                                readonly property bool disponible: perfil.modelData.id !== "rendimiento" || PowerProfiles.hasPerformanceProfile
                                width: (colEstado.width - 12) / 3
                                height: 34
                                radius: 17
                                color: perfil.elegido ? tema.primary : root.alfa(tema.primary, maPerfil.containsMouse ? 0.18 : 0.08)
                                opacity: perfil.disponible ? 1 : 0.4
                                scale: maPerfil.pressed ? 0.95 : 1
                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                                Behavior on scale {
                                    NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                                }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.ic(perfil.modelData.icono)
                                        font.family: root.fuente
                                        font.pixelSize: 14
                                        color: perfil.elegido ? tema.primaryText : tema.primary
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: perfil.modelData.texto
                                        font.family: root.fuente
                                        font.pixelSize: 11
                                        font.bold: perfil.elegido
                                        color: perfil.elegido ? tema.primaryText : tema.surfaceText
                                    }
                                }
                                MouseArea {
                                    id: maPerfil
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: perfil.disponible ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.ponerPerfil(perfil.modelData.id)
                                }
                            }
                        }
                    }

                    // Luz nocturna y límite de carga: el círculo enciende/apaga; el resto abre su página
                    Row {
                        width: parent.width
                        spacing: 10
                        Repeater {
                            model: ["nocturna", "bateria"]
                            delegate: Rectangle {
                                id: rapida
                                required property var modelData
                                readonly property bool esLuz: rapida.modelData === "nocturna"
                                readonly property bool activo: rapida.esLuz ? luz.activa : limite.activo
                                readonly property string titulo: rapida.esLuz ? "Luz nocturna" : "Límite " + limite.fin + " %"
                                readonly property string detalle: rapida.esLuz
                                    ? (!luz.activa ? "Apagada"
                                        : luz.modo === "siempre" ? "Siempre · " + luz.temperatura + " K"
                                        : luz.calida ? "Activa · " + luz.tempActual + " K"
                                        : luz.atardecer !== "" ? "Desde las " + luz.atardecer : "Al atardecer")
                                    : (limite.activo ? "Cuida la batería" : "Carga al 100 %")
                                visible: rapida.esLuz || limite.soportado
                                width: (colEstado.width - 10) / 2
                                height: 56
                                radius: 16
                                color: rapida.activo ? root.alfa(tema.primary, maRapida.containsMouse ? 0.3 : 0.2)
                                    : root.alfa(tema.primary, maRapida.containsMouse ? 0.16 : 0.07)
                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                                MouseArea {
                                    id: maRapida
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pagina = rapida.esLuz ? "nocturna" : "energia"
                                }
                                // Círculo: interruptor rápido
                                Rectangle {
                                    id: circulo
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: rapida.activo ? tema.primary : root.alfa(tema.primary, maCirculo.containsMouse ? 0.25 : 0.12)
                                    scale: maCirculo.pressed ? 0.9 : 1
                                    opacity: !rapida.esLuz && limite.ocupado ? 0.6 : 1
                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                    Behavior on scale {
                                        NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.ic(rapida.esLuz ? 0xF0594 : 0xF008A)
                                        font.family: root.fuente
                                        font.pixelSize: 17
                                        color: rapida.activo ? tema.primaryText : tema.primary
                                    }
                                    MouseArea {
                                        id: maCirculo
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: rapida.esLuz ? luz.alternar() : limite.poner(!limite.activo)
                                    }
                                }
                                Column {
                                    anchors.left: circulo.right
                                    anchors.leftMargin: 9
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: rapida.titulo
                                        font.family: root.fuente
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: tema.surfaceText
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: rapida.detalle
                                        font.family: root.fuente
                                        font.pixelSize: 10
                                        color: root.alfa(tema.surfaceText, 0.65)
                                    }
                                }
                            }
                        }
                    }

                    // Mantener despierto (cafeína): toda la tarjeta es el interruptor
                    Rectangle {
                        id: tarjetaCafeina
                        width: parent.width
                        height: 56
                        radius: 16
                        color: root.cafeina ? root.alfa(tema.primary, maCafeina.containsMouse ? 0.3 : 0.2)
                            : root.alfa(tema.primary, maCafeina.containsMouse ? 0.16 : 0.07)
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        Rectangle {
                            id: circuloCafeina
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 34
                            radius: 17
                            color: root.cafeina ? tema.primary : root.alfa(tema.primary, maCafeina.containsMouse ? 0.25 : 0.12)
                            scale: maCafeina.pressed ? 0.9 : 1
                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }
                            Behavior on scale {
                                NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: root.ic(0xF0176)
                                font.family: root.fuente
                                font.pixelSize: 17
                                color: root.cafeina ? tema.primaryText : tema.primary
                            }
                        }
                        Column {
                            anchors.left: circuloCafeina.right
                            anchors.leftMargin: 9
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: "Mantener despierto"
                                font.family: root.fuente
                                font.pixelSize: 12
                                font.bold: true
                                color: tema.surfaceText
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: root.cafeina ? "No se bloquea ni se suspende solo"
                                    : rep.sonando ? "Reproduciendo: " + rep.titulo
                                    : root.mediosActivos.length ? "Reproduciendo: " + root.mediosActivos.join(", ")
                                    : root.opc("energia.bloquearMin", 10) === 0 ? "No se bloquea solo"
                                    : "Se bloquea tras " + root.opc("energia.bloquearMin", 10) + " min sin uso"
                                font.family: root.fuente
                                font.pixelSize: 10
                                color: root.alfa(tema.surfaceText, 0.65)
                            }
                        }
                        MouseArea {
                            id: maCafeina
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.alternarCafeina()
                        }
                    }

                    // Wi-Fi y Bluetooth (cada tarjeta abre su página)
                    Row {
                        width: parent.width
                        spacing: 10

                        Repeater {
                            // Modelo fijo: si dependiera de la señal o del bluetooth, el Repeater
                            // recrearía las tarjetas en cada sondeo (cada 10 s) y se perdería el clic
                            model: ["wifi", "bluetooth"]
                            delegate: Rectangle {
                                id: tarjeta
                                required property var modelData
                                readonly property bool esWifi: tarjeta.modelData === "wifi"
                                readonly property string pag: tarjeta.modelData
                                readonly property string titulo: tarjeta.esWifi
                                    ? (root.wifiNombre !== "" ? root.wifiNombre : "Wi-Fi") : "Bluetooth"
                                readonly property string detalle: tarjeta.esWifi
                                    ? (root.wifiSenal >= 0 ? "Señal " + root.wifiSenal + "%" : "Sin conexión")
                                    : root.textoBluetooth()
                                readonly property string icono: tarjeta.esWifi ? root.iconoWifi()
                                    : root.ic(root.btConectado ? 0xF00B1 : root.btAdaptador && root.btAdaptador.enabled ? 0xF00AF : 0xF00B2)
                                readonly property bool activo: tarjeta.esWifi ? root.wifiSenal >= 0
                                    : root.btAdaptador !== null && root.btAdaptador.enabled
                                width: (colEstado.width - 10) / 2
                                height: 56
                                radius: 16
                                color: tarjeta.activo ? root.alfa(tema.primary, maTarjeta.containsMouse ? 0.3 : 0.2)
                                    : root.alfa(tema.primary, maTarjeta.containsMouse ? 0.16 : 0.07)
                                scale: maTarjeta.pressed ? 0.96 : 1
                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                                Behavior on scale {
                                    NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                                }
                                Text {
                                    id: icTarjeta
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tarjeta.icono
                                    font.family: root.fuente
                                    font.pixelSize: 20
                                    color: tema.primary
                                }
                                Column {
                                    anchors.left: icTarjeta.right
                                    anchors.leftMargin: 10
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: tarjeta.titulo
                                        font.family: root.fuente
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: tema.surfaceText
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: tarjeta.detalle
                                        font.family: root.fuente
                                        font.pixelSize: 10
                                        color: root.alfa(tema.surfaceText, 0.65)
                                    }
                                }
                                MouseArea {
                                    id: maTarjeta
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pagina = tarjeta.pag
                                }
                            }
                        }
                    }

                    // CPU, RAM y temperatura (clic abre la página de sistema)
                    Rectangle {
                        width: parent.width
                        height: 74
                        radius: 16
                        color: root.alfa(tema.primary, maSis.containsMouse ? 0.2 : 0.1)
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 14

                            Repeater {
                                model: [
                                    { icono: 0xF0EE0, nombre: "CPU", valor: root.cpu, texto: root.cpu + "%" },
                                    { icono: 0xF035B, nombre: "RAM", valor: root.ram, texto: root.ram + "%" },
                                    { icono: 0xF2C9, nombre: "Temp", valor: root.temp, texto: root.temp + "°C" }
                                ]

                                delegate: Column {
                                    id: medidor
                                    required property var modelData
                                    property bool alerta: medidor.modelData.valor >= 85
                                    width: 92
                                    spacing: 6

                                    Row {
                                        spacing: 6
                                        Text {
                                            text: root.ic(medidor.modelData.icono)
                                            font.family: root.fuente
                                            font.pixelSize: 14
                                            color: medidor.alerta ? "#ff5555" : tema.primary
                                        }
                                        Text {
                                            text: medidor.modelData.texto
                                            font.family: root.fuente
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: tema.surfaceText
                                        }
                                    }
                                    Rectangle {
                                        width: parent.width
                                        height: 6
                                        radius: 3
                                        color: root.alfa(tema.surfaceText, 0.15)
                                        Rectangle {
                                            width: Math.max(6, parent.width * Math.min(100, medidor.modelData.valor) / 100)
                                            height: parent.height
                                            radius: 3
                                            color: medidor.alerta ? "#ff5555" : tema.primary
                                            Behavior on width {
                                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                            }
                                        }
                                    }
                                    Text {
                                        text: medidor.modelData.nombre
                                        font.family: root.fuente
                                        font.pixelSize: 10
                                        color: root.alfa(tema.surfaceText, 0.6)
                                    }
                                }
                            }
                        }
                        MouseArea {
                            id: maSis
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pagina = "sistema"
                        }
                    }
                }

                // ---------- Subpáginas (entran deslizándose desde la derecha) ----------
                PaginaWifi {
                    id: pagWifi
                    s: root
                    tema: tema
                    activa: root.panel === "estado" && root.pagina === "wifi"
                    x: 18 + (root.pagina === "wifi" ? 0 : 40)
                    y: 18
                    width: parent.width - 36
                    opacity: root.pagina === "wifi" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    onAtras: root.pagina = "inicio"
                }

                PaginaBluetooth {
                    id: pagBt
                    s: root
                    tema: tema
                    agente: agenteBt
                    activa: root.panel === "estado" && root.pagina === "bluetooth"
                    x: 18 + (root.pagina === "bluetooth" ? 0 : 40)
                    y: 18
                    width: parent.width - 36
                    opacity: root.pagina === "bluetooth" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    onAtras: root.pagina = "inicio"
                }

                PaginaAudio {
                    id: pagAudio
                    s: root
                    tema: tema
                    activa: root.panel === "estado" && root.pagina === "audio"
                    x: 18 + (root.pagina === "audio" ? 0 : 40)
                    y: 18
                    width: parent.width - 36
                    opacity: root.pagina === "audio" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    onAtras: root.pagina = "inicio"
                }

                PaginaSistema {
                    id: pagSistema
                    s: root
                    tema: tema
                    activa: root.panel === "estado" && root.pagina === "sistema"
                    x: 18 + (root.pagina === "sistema" ? 0 : 40)
                    y: 18
                    width: parent.width - 36
                    opacity: root.pagina === "sistema" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    onAtras: root.pagina = "inicio"
                }

                PaginaEnergia {
                    id: pagEnergia
                    s: root
                    tema: tema
                    limite: limite
                    activa: root.panel === "estado" && root.pagina === "energia"
                    x: 18 + (root.pagina === "energia" ? 0 : 40)
                    y: 18
                    width: parent.width - 36
                    opacity: root.pagina === "energia" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    onAtras: root.pagina = "inicio"
                    onHecho: root.panel = ""
                }

                PaginaCapturas {
                    id: pagCapturas
                    s: root
                    tema: tema
                    grabadora: grabadora
                    activa: root.panel === "estado" && root.pagina === "capturas"
                    x: 18 + (root.pagina === "capturas" ? 0 : 40)
                    y: 18
                    width: parent.width - 36
                    opacity: root.pagina === "capturas" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    onAtras: root.pagina = "inicio"
                }
                PaginaNocturna {
                    id: pagNocturna
                    s: root
                    tema: tema
                    luz: luz
                    activa: root.panel === "estado" && root.pagina === "nocturna"
                    x: 18 + (root.pagina === "nocturna" ? 0 : 40)
                    y: 18
                    width: parent.width - 36
                    opacity: root.pagina === "nocturna" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    onAtras: root.pagina = "inicio"
                }
            }

            // ---------- Panel de la hora: calendario o notificaciones ----------
            // Un solo panel: al pasar de uno a otro la caja se desliza/estira y el contenido se funde.
            Panel {
                id: panelCal
                anchors.fill: parent
                tema: tema
                onPresion: pos => root.revisarFoco(pos)
                abierto: root.relojAbierto
                origen: root.modoReloj === "avisos" ? root.origenAvisos : root.origenCal
                anchoFinal: root.modoReloj === "avisos" ? 340 + 36 : 294 + 36
                altoFinal: (root.modoReloj === "avisos" ? colAvisos.height : colCal.implicitHeight) + 36
                Behavior on altoFinal {
                    enabled: panelCal.p > 0.98
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }

                Column {
                    id: colCal
                    property bool activa: root.modoReloj === "calendario"
                    x: 18 + (activa ? 0 : -30)
                    y: 18
                    width: 294
                    spacing: 12
                    opacity: activa ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on x {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 120 }
                    }

                    // Hora grande
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(reloj.date, "hh:mm:ss")
                            font.family: root.fuente
                            font.pixelSize: 34
                            font.bold: true
                            color: tema.primary
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: reloj.date.toLocaleDateString(Qt.locale("es_EC"), "dddd d 'de' MMMM")
                            font.family: root.fuente
                            font.pixelSize: 12
                            color: root.alfa(tema.surfaceText, 0.7)
                        }
                    }

                    // Encabezado del mes
                    Item {
                        width: parent.width
                        height: 30
                        Boton {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            tema: tema
                            icono: root.ic(0xF0141)
                            onClic: root.moverMes(-1)
                        }
                        Text {
                            anchors.centerIn: parent
                            text: {
                                var t = root.mesVista.toLocaleDateString(Qt.locale("es_EC"), "MMMM yyyy")
                                return t.charAt(0).toUpperCase() + t.slice(1)
                            }
                            font.family: root.fuente
                            font.pixelSize: 14
                            font.bold: true
                            color: tema.surfaceText
                        }
                        Boton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            tema: tema
                            icono: root.ic(0xF0142)
                            onClic: root.moverMes(1)
                        }
                    }

                    // Días (lunes primero)
                    Grid {
                        id: rejilla
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 7
                        spacing: 2
                        property int inicio: (new Date(root.mesVista.getFullYear(), root.mesVista.getMonth(), 1).getDay() + 6) % 7

                        Repeater {
                            model: ["L", "M", "X", "J", "V", "S", "D"]
                            delegate: Text {
                                required property var modelData
                                width: 38
                                height: 22
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData
                                font.family: root.fuente
                                font.pixelSize: 11
                                font.bold: true
                                color: root.alfa(tema.primary, 0.8)
                            }
                        }

                        Repeater {
                            model: 42
                            delegate: Rectangle {
                                id: dia
                                required property int index
                                property date fecha: new Date(root.mesVista.getFullYear(), root.mesVista.getMonth(), dia.index - rejilla.inicio + 1)
                                property bool delMes: dia.fecha.getMonth() === root.mesVista.getMonth()
                                property bool hoy: dia.fecha.toDateString() === reloj.date.toDateString()
                                width: 38
                                height: 32
                                radius: 16
                                color: dia.hoy ? tema.primary : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: dia.fecha.getDate()
                                    font.family: root.fuente
                                    font.pixelSize: 12
                                    font.bold: dia.hoy
                                    color: dia.hoy ? tema.primaryText
                                        : root.alfa(tema.surfaceText, dia.delMes ? 0.95 : 0.3)
                                }
                            }
                        }
                    }

                    // Música (solo si hay un reproductor)
                    Rectangle {
                        visible: rep.activo !== null || rep.audioConfirmado.length > 0
                        width: parent.width
                        height: 58
                        radius: 16
                        color: root.alfa(tema.primary, 0.1)

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.right: controles.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: rep.titulo
                                textFormat: Text.PlainText
                                font.family: root.fuente
                                font.pixelSize: 12
                                font.bold: true
                                color: tema.surfaceText
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: rep.activo ? (rep.activo.trackArtist || rep.nombreApp) : rep.nombreApp
                                textFormat: Text.PlainText
                                font.family: root.fuente
                                font.pixelSize: 11
                                color: root.alfa(tema.surfaceText, 0.65)
                            }
                        }
                        Row {
                            id: controles
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            Boton {
                                tema: tema; icono: root.ic(0xF04AE)
                                enabled: !!rep.activo; opacity: enabled ? 1 : 0.35
                                onClic: rep.activo.previous()
                            }
                            Boton {
                                tema: tema
                                icono: rep.activo && rep.activo.isPlaying ? root.ic(0xF03E4) : root.ic(0xF040A)
                                enabled: !!rep.activo; opacity: enabled ? 1 : 0.35
                                onClic: rep.activo.togglePlaying()
                            }
                            Boton {
                                tema: tema; icono: root.ic(0xF04AD)
                                enabled: !!rep.activo; opacity: enabled ? 1 : 0.35
                                onClic: rep.activo.next()
                            }
                        }
                    }

                }
                // ---------- Notificaciones ----------
                // Alto según la lista (con tope); si no cabe, la lista tiene su propio scroll.
                Item {
                    id: colAvisos
                    property bool activa: root.modoReloj === "avisos"
                    readonly property real altoZona: avisos.historial.count === 0 ? 210
                        : Math.max(90, Math.min(listaAvisos.contentHeight, 440))
                    x: 18 + (activa ? 0 : 30)
                    y: 18
                    width: 340
                    height: 30 + 10 + altoZona + (avisos.historial.count > 0 ? 10 + 32 : 0)
                    opacity: activa ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on x {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 120 }
                    }

                    // Cabecera fija: título + contador · No molestar
                    Item {
                        id: cabAvisos
                        width: parent.width
                        height: 30
                        Etiqueta {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            s: root
                            tema: tema
                            topPadding: 0
                            texto: "NOTIFICACIONES"
                        }
                        // Contador en pastilla
                        Rectangle {
                            x: 122
                            anchors.verticalCenter: parent.verticalCenter
                            visible: avisos.historial.count > 0
                            width: Math.max(20, numAvisos.implicitWidth + 12)
                            height: 20
                            radius: 10
                            color: root.alfa(tema.primary, 0.2)
                            Text {
                                id: numAvisos
                                anchors.centerIn: parent
                                text: avisos.historial.count
                                font.family: root.fuente
                                font.pixelSize: 11
                                font.bold: true
                                color: tema.primary
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.ic(0xF009B) + " No molestar"
                                font.family: root.fuente
                                font.pixelSize: 11
                                color: root.alfa(tema.surfaceText, avisos.noMolestar ? 0.95 : 0.6)
                            }
                            Interruptor {
                                anchors.verticalCenter: parent.verticalCenter
                                tema: tema
                                activo: avisos.noMolestar
                                onCambiado: v => avisos.ponerNoMolestar(v)
                            }
                        }
                    }

                    // Zona de la lista (entre la cabecera y "Limpiar todo")
                    Item {
                        id: zonaAvisos
                        anchors.top: cabAvisos.bottom
                        anchors.topMargin: 10
                        anchors.bottom: btnLimpiar.visible ? btnLimpiar.top : parent.bottom
                        anchors.bottomMargin: btnLimpiar.visible ? 10 : 0
                        width: parent.width

                        // Vacío: icono grande + mensaje
                        Column {
                            anchors.centerIn: parent
                            visible: avisos.historial.count === 0
                            spacing: 10
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 72
                                height: 72
                                radius: 36
                                color: root.alfa(tema.primary, 0.1)
                                Text {
                                    anchors.centerIn: parent
                                    text: root.ic(avisos.noMolestar ? 0xF009B : 0xF009C)
                                    font.family: root.fuente
                                    font.pixelSize: 34
                                    color: root.alfa(tema.primary, 0.75)
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: avisos.noMolestar ? "No molestar activado" : "Sin notificaciones"
                                font.family: root.fuente
                                font.pixelSize: 14
                                font.bold: true
                                color: root.alfa(tema.surfaceText, 0.85)
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 260
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                text: avisos.noMolestar ? "Los avisos se guardan aquí sin interrumpirte"
                                    : "Todo al día. Los avisos nuevos aparecerán aquí"
                                font.family: root.fuente
                                font.pixelSize: 11
                                color: root.alfa(tema.surfaceText, 0.5)
                            }
                        }

                        ListView {
                            id: listaAvisos
                            anchors.fill: parent
                            anchors.rightMargin: 8      // sitio para la barrita de scroll
                            visible: avisos.historial.count > 0
                            clip: true
                            spacing: 8
                            boundsBehavior: Flickable.StopAtBounds
                            model: avisos.historial
                            delegate: Item {
                                id: filaAviso
                                required property var model
                                property var fila: model
                                property real alto: 1
                                width: listaAvisos.width
                                height: tarjetaH.implicitHeight * alto
                                clip: true
                                property bool saliendo: model.saliendo
                                onSaliendoChanged: if (saliendo) salidaH.start()
                                SequentialAnimation {
                                    id: salidaH
                                    ParallelAnimation {
                                        NumberAnimation { target: tarjetaH; property: "x"; to: listaAvisos.width; duration: 140; easing.type: Easing.InCubic }
                                        NumberAnimation { target: tarjetaH; property: "opacity"; to: 0; duration: 140 }
                                    }
                                    NumberAnimation { target: filaAviso; property: "alto"; to: 0; duration: 120; easing.type: Easing.InOutCubic }
                                    ScriptAction { script: avisos.borrarHistorial(filaAviso.fila.clave) }
                                }
                                TarjetaAviso {
                                    id: tarjetaH
                                    width: parent.width
                                    s: root
                                    tema: panelCal.tema   // dentro del delegado "tema" sería la propia propiedad
                                    av: avisos
                                    d: filaAviso.fila
                                    ahora: reloj.date
                                    onCerrar: avisos.descartar(filaAviso.fila.clave)
                                    onAccion: id => {
                                        if (id.startsWith("hola:")) { avisos.activar(filaAviso.fila.clave, id); return }
                                        avisos.invocar(filaAviso.fila.clave, id)
                                        root.panel = ""
                                    }
                                    onClicCuerpo: avisos.clicCuerpo(filaAviso.fila.clave)
                                }
                            }
                        }

                        // Barrita de scroll (solo si la lista no cabe)
                        Rectangle {
                            visible: listaAvisos.visible && listaAvisos.contentHeight > listaAvisos.height + 1
                            anchors.right: parent.right
                            y: listaAvisos.visibleArea.yPosition * listaAvisos.height
                            width: 4
                            height: Math.max(24, listaAvisos.visibleArea.heightRatio * listaAvisos.height)
                            radius: 2
                            color: root.alfa(tema.primary, listaAvisos.moving ? 0.7 : 0.35)
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                    }

                    // "Limpiar todo" fijo abajo
                    BotonTexto {
                        id: btnLimpiar
                        visible: avisos.historial.count > 0
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        tema: tema
                        texto: root.ic(0xF045A) + "  Limpiar todo"
                        onClic: avisos.limpiar()
                    }
                }
            }
        }
    }
}
