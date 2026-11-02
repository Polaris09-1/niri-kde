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

// Barra superior (diseño A): workspaces + ventana | hora | bandeja + píldora de estado.
// La píldora abre el panel de estado, la hora el calendario y la campanita las notificaciones; crecen
// desde su botón. Todo lo demás (apps) vive en el dock.
Scope {
    id: root

    // ===== Ajustes =====
    // Paneles al pasar el cursor (hora, campanita y píldora)
    property bool abrirAlPasar: true
    property int esperaAbrir: 60         // ms con el cursor sobre el botón antes de abrir
    property int esperaCerrar: 150       // ms fuera del botón y del panel antes de cerrar
    // Pantalla completa (estilo macOS): la barra se esconde y deja de reservar su espacio; baja al
    // acercar el mouse al borde de arriba (mismos tiempos que los paneles: esperaAbrir/esperaCerrar)
    property bool esconderEnPantallaCompleta: true
    property int altoSensor: 3           // px del borde superior que hacen bajar la barra
    property string fuente: "JetBrainsMono Nerd Font"
    property int altoIsla: 38
    property real opacidadIsla: 0.85
    property string terminal: "alacritty"

    property bool mostrar: true

    // ===== Estado =====
    property var workspaces: []
    property string tituloVentana: ""
    property string appVentana: ""
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

    // Reproductor activo (MPRIS)
    property var jugador: {
        var l = Mpris.players.values
        return l.length ? (l.find(j => j.isPlaying) || l[0]) : null
    }

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
    Grabadora { id: grabadora }

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
    function abrirPagina(nombre) {
        if (root.paginas.indexOf(nombre) < 0) nombre = "inicio"
        if (root.panel !== "estado") {
            root.panel = ""
            root.alternar("estado")
        }
        root.pagina = nombre
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
        emergentesVisibles: root.panel !== "avisos"
        // En pantalla completa los avisos normales no salen como popup (van al historial); los urgentes sí
        callarPantallaCompleta: root.pantallaCompleta
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
        root.simCursor === "hora" || botonReloj.encima ? "calendario"
        : root.simCursor === "campana" || campana.encima ? "avisos"
        : root.simCursor === "pildora" || maPildora.containsMouse ? "estado" : ""
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
    readonly property bool cursorEnGracia: root.enGracia && cursorCapa.hovered
        && cursorCapa.point.position.x >= root.zonaGracia.x
        && cursorCapa.point.position.x <= root.zonaGracia.x + root.zonaGracia.width
        && cursorCapa.point.position.y >= root.zonaGracia.y
        && cursorCapa.point.position.y <= root.zonaGracia.y + root.zonaGracia.height
    onCursorEnGraciaChanged: if (!root.cursorEnGracia) root.enGracia = false
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
    onBotonBajoCursorChanged: {
        if (root.abrirAlPasar && root.botonBajoCursor !== "" && root.botonBajoCursor !== root.panel) timerAbrir.restart()
        else timerAbrir.stop()
    }
    Timer {
        id: timerAbrir
        interval: root.esperaAbrir
        // Si estás escribiendo o hay una confirmación, no cambia de panel
        onTriggered: if (root.botonBajoCursor !== "" && root.botonBajoCursor !== root.panel && !root.retener)
            root.abrirAlPasarSobre(root.botonBajoCursor)
    }
    Timer {
        id: timerCerrar
        interval: root.esperaCerrar
        onTriggered: if (root.debeCerrar) root.panel = ""
    }
    // ===== Pantalla completa: barra escondida que baja con el cursor =====
    PantallaCompleta { id: pcompleta }
    readonly property string salidaBarra: ventana.screen ? ventana.screen.name : ""
    // simPantallaCompleta: solo pruebas por IPC ("si"|"no"|"" = lo que diga niri)
    property string simPantallaCompleta: ""
    readonly property bool pantallaCompleta: root.esconderEnPantallaCompleta
        && (root.simPantallaCompleta !== "" ? root.simPantallaCompleta === "si" : pcompleta.en(root.salidaBarra))
    property bool barraRevelada: false
    readonly property bool barraOculta: root.pantallaCompleta && !root.barraRevelada
    // El cursor está en el sensor o en la franja de la barra (o simulado por IPC), o hay un panel
    readonly property bool mantenerBarra: hoverBarra.hovered || root.simCursor !== "" || root.panel !== ""
    onPantallaCompletaChanged: root.revisarBarra()
    onMantenerBarraChanged: root.revisarBarra()
    function revisarBarra() {
        if (!root.pantallaCompleta) { timerRevelar.stop(); timerEsconder.stop(); root.barraRevelada = false; return }
        if (root.mantenerBarra) { timerEsconder.stop(); if (!root.barraRevelada) timerRevelar.restart() }
        else { timerRevelar.stop(); if (root.barraRevelada) timerEsconder.restart() }
    }
    Timer {
        id: timerRevelar
        // Un panel abierto por IPC/atajo/dock (sin cursor) baja la barra al instante
        interval: root.panel !== "" ? 0 : root.esperaAbrir
        onTriggered: if (root.pantallaCompleta && root.mantenerBarra) root.barraRevelada = true
    }
    Timer {
        id: timerEsconder
        interval: root.esperaCerrar
        onTriggered: if (!root.mantenerBarra) root.barraRevelada = false
    }

    function abrirAlPasarSobre(nombre) {
        if (root.panel === nombre) return
        root.mostrarPanel(nombre)
        root.porClic = false
    }

    // Clic en un botón, IPC o dock: abre/cierra como siempre.
    // Si ya estaba abierto al pasar el cursor, el clic lo deja fijo (no lo cierra).
    function alternar(nombre) {
        timerAbrir.stop()
        if (root.panel === nombre && !root.porClic) { root.porClic = true; return }
        root.mostrarPanel(nombre)
        root.porClic = root.panel !== ""
    }

    // Abre/cierra un panel guardando desde qué botón nace
    function mostrarPanel(nombre) {
        if (root.panel === nombre) { root.panel = ""; return }
        // Cada panel nace de su botón (la hora y la campanita son botones distintos)
        var item = nombre === "estado" ? pildora : nombre === "avisos" ? campana : botonReloj
        var pt = item.mapToItem(null, 0, 0)
        var r = Qt.rect(pt.x, pt.y, item.width, item.height)
        if (nombre === "estado") {
            root.origenEstado = r
            root.pagina = "inicio"
        } else if (nombre === "avisos") {
            root.origenAvisos = r
            root.modoReloj = "avisos"
            avisos.sinLeer = 0
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
        // Simula dónde está el cursor (hora|campana|pildora|panel|fuera) para probar sin mouse
        function cursor(donde: string): string {
            root.simCursor = donde === "fuera" ? "" : donde
            root.tCursor = Date.now()
            return JSON.stringify({ panel: root.panel, porClic: root.porClic, bajoCursor: root.botonBajoCursor,
                enPanel: root.cursorEnPanel, retener: root.retener })
        }
        function hover(): string {
            return JSON.stringify({ panel: root.panel, porClic: root.porClic, bajoCursor: root.botonBajoCursor,
                enPanel: root.cursorEnPanel, escribiendo: root.escribiendo, dialogo: root.hayDialogo,
                gracia: root.enGracia, pulsado: panelEstado.pulsado || panelCal.pulsado,
                abriendo: timerAbrir.running, cerrando: timerCerrar.running,
                msCursorAPanel: root.tPanel >= root.tCursor ? root.tPanel - root.tCursor : -1 })
        }
        function cerrar(): void { root.panel = "" }
        // Estado de la pantalla completa (lo que dice niri y lo que hace la barra)
        function pantallaCompleta(): string {
            return JSON.stringify({ salida: root.salidaBarra, pantallaCompleta: root.pantallaCompleta,
                niri: pcompleta.porSalida, ventana: pcompleta.ventanaPorSalida, vistaGeneral: pcompleta.vistaGeneral,
                simulada: root.simPantallaCompleta, revelada: root.barraRevelada, oculta: root.barraOculta,
                cursorArriba: hoverBarra.hovered, zona: ventana.exclusiveZone,
                avisosCallados: avisos.callarPantallaCompleta })
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
                    urgencia: f.urgencia, duracion: f.duracion, acciones: JSON.parse(f.acciones), vivo: f.vivo })
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
        // Grabar pantalla: inicia (pantalla completa, último audio elegido) o detiene
        function grabar(): string { if (grabadora.grabando) grabadora.detener(); else root.grabar("pantalla", grabadora.audio); return grabadora.grabando ? "deteniendo" : "iniciando" }
        function grabacion(): string { return JSON.stringify({ grabando: grabadora.grabando, segundos: grabadora.segundos, ruta: grabadora.ruta, error: grabadora.error }) }
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
            pVentana.running = true
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
        id: pVentana
        command: ["niri", "msg", "-j", "focused-window"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var v = JSON.parse(text)
                    root.tituloVentana = v ? (v.title || "") : ""
                    root.appVentana = v ? (v.app_id || "") : ""
                } catch (e) {}
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
    PanelWindow {
        id: ventana
        anchors {
            top: true
            left: true
            right: true
        }
        implicitHeight: root.altoIsla + 20
        // En pantalla completa no reserva espacio (la ventana ocupa todo y la barra baja encima)
        exclusionMode: root.pantallaCompleta ? ExclusionMode.Ignore : ExclusionMode.Normal
        exclusiveZone: root.pantallaCompleta ? 0 : root.altoIsla + 12
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hola"

        // Normal: las islas son lo único clicable; el resto deja pasar el mouse.
        // Pantalla completa escondida: solo el sensor fino del borde de arriba.
        // Pantalla completa bajada: toda la franja (pasar de una isla a otra no la esconde).
        mask: root.pantallaCompleta ? (root.barraRevelada ? regionFranja : regionSensor) : regionIslas
        // Coordenadas explícitas, NO `Region { item: … }`: con `item` Quickshell mide la isla con sus
        // transformaciones (Translate de entrada y de pantalla completa) y solo vuelve a medir cuando
        // cambian su x/y/ancho/alto, no cuando termina la animación. Al salir de pantalla completa la
        // medía aún escondida arriba (fuera de la ventana) y la barra se quedaba sin recibir el cursor.
        // Así la máscara está siempre en la posición final de las islas, también durante la bajada.
        property Region regionIslas: Region {
            Region { x: islaIzq.x; y: islaIzq.y; width: islaIzq.width; height: islaIzq.height }
            Region { x: islaReloj.x; y: islaReloj.y; width: islaReloj.width; height: islaReloj.height }
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
                        y: root.barraOculta ? -(root.altoIsla + 20) : 0
                        Behavior on y {
                            NumberAnimation {
                                duration: root.barraOculta ? 120 : 150
                                easing.type: root.barraOculta ? Easing.InCubic : Easing.OutCubic
                            }
                        }
                    }
                ]

                // ---------- Isla izquierda: workspaces + ventana activa ----------
                Rectangle {
                    id: islaIzq
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
                                model: root.workspaces.length

                                delegate: Rectangle {
                                    id: pill
                                    required property int index
                                    property var ws: root.workspaces[pill.index] || ({})
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
                                        onClicked: root.ejecutar(["niri", "msg", "action", "focus-workspace", String(pill.ws.idx)])
                                    }
                                }
                            }
                        }

                        // Ventana activa: clic abre la vista general de niri
                        Boton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.tituloVentana !== ""
                            tema: tema
                            imagen: root.iconoApp(root.appVentana)
                            texto: root.tituloVentana
                            anchoMaxTexto: 320
                            onClic: root.ejecutar(["niri", "msg", "action", "toggle-overview"])
                        }
                    }
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
                            tema: tema
                            activo: root.panel === "calendario"
                            icono: Qt.formatDateTime(reloj.date, "hh:mm")
                            texto: reloj.date.toLocaleDateString(Qt.locale("es_EC"), "ddd d MMM")
                            onClic: root.alternar("calendario")
                        }
                        // Campanita (siempre visible): tachada = No molestar; con número = avisos sin ver
                        Boton {
                            id: campana
                            tema: tema
                            activo: root.panel === "avisos"
                            icono: root.ic(avisos.noMolestar ? 0xF009B : avisos.sinLeer > 0 ? 0xF116B : 0xF009C)
                            colorIcono: avisos.noMolestar ? root.alfa(tema.surfaceText, 0.6) : tema.primary
                            texto: avisos.sinLeer > 0 ? String(Math.min(avisos.sinLeer, 99)) : ""
                            onClic: root.alternar("avisos")
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

                        // Bandeja del sistema (solo si hay iconos)
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: SystemTray.items.values.length > 0
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
                            visible: grabadora.grabando || root.cuentaCaptura > 0
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
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (grabadora.grabando) grabadora.detener()
                            }
                        }

                        // Píldora de estado: clic abre el panel, rueda cambia el volumen
                        Rectangle {
                            id: pildora
                            anchors.verticalCenter: parent.verticalCenter
                            height: 30
                            width: filaPildora.width + 22
                            radius: height / 2
                            color: root.panel === "estado" ? root.alfa(tema.primary, 0.28)
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
                                    text: root.iconoWifi()
                                    font.family: root.fuente
                                    font.pixelSize: 15
                                    color: tema.primary
                                }
                                Text {
                                    text: root.iconoVolumen()
                                    font.family: root.fuente
                                    font.pixelSize: 15
                                    color: tema.primary
                                }
                                Text {
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
                                onClicked: m => m.button === Qt.RightButton ? root.abrirPagina("audio") : root.alternar("estado")
                                onWheel: w => root.cambiarVolumen(w.angleDelta.y > 0 ? 0.02 : -0.02)
                            }
                        }
                    }
                }
            }
        }
    }

    // ===== Capa de paneles (calendario y estado) =====
    PanelWindow {
        id: capa
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        visible: root.panel !== "" || panelEstado.vivo || panelCal.vivo
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hola-paneles"
        // Abierto con clic: teclado exclusivo (como siempre). Abierto al pasar el cursor: el teclado
        // solo viene al panel si haces clic dentro (pasar por la hora no roba lo que escribes).
        WlrLayershell.keyboardFocus: root.panel === "" ? WlrKeyboardFocus.None
            : root.porClic ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

        // Las islas de la barra quedan fuera de esta capa: así el cursor y los clics llegan
        // a sus botones aunque haya un panel abierto encima
        mask: Region {
            item: raizCapa
            Region { x: islaIzq.x; y: islaIzq.y; width: islaIzq.width; height: islaIzq.height; intersection: Intersection.Subtract }
            Region { x: islaReloj.x; y: islaReloj.y; width: islaReloj.width; height: islaReloj.height; intersection: Intersection.Subtract }
            Region { x: islaDer.x; y: islaDer.y; width: islaDer.width; height: islaDer.height; intersection: Intersection.Subtract }
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
                            // Cámara: capturas y grabación · ⏻: energía
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
                        visible: root.jugador !== null
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
                                text: root.jugador ? (root.jugador.trackTitle || "Sin título") : ""
                                font.family: root.fuente
                                font.pixelSize: 12
                                font.bold: true
                                color: tema.surfaceText
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: root.jugador ? (root.jugador.trackArtist || root.jugador.identity || "") : ""
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
                            Boton { tema: tema; icono: root.ic(0xF04AE); onClic: if (root.jugador) root.jugador.previous() }
                            Boton {
                                tema: tema
                                icono: root.jugador && root.jugador.isPlaying ? root.ic(0xF03E4) : root.ic(0xF040A)
                                onClic: if (root.jugador) root.jugador.togglePlaying()
                            }
                            Boton { tema: tema; icono: root.ic(0xF04AD); onClic: if (root.jugador) root.jugador.next() }
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
                                    onAccion: id => { avisos.invocar(filaAviso.fila.clave, id); root.panel = "" }
                                    onClicCuerpo: {
                                        if (filaAviso.fila.vivo && JSON.parse(filaAviso.fila.acciones).some(a => a.id === "default")) {
                                            avisos.invocar(filaAviso.fila.clave, "default")
                                            root.panel = ""
                                        }
                                    }
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
