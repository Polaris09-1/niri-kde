//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import QtQuick

// App de Ajustes: una ventana normal de niri (flotante, ver window-rule en config.kdl). Solo corre mientras
// está abierta: se abre con ~/.local/bin/ajustes-abrir.sh (Mod+S, engranaje del panel, cajón).
// - Catalogo.qml declara secciones y opciones; de ahí salen la pantalla, el buscador y "Restablecer".
// - ajustes.json: solo lo que difiere de los valores de fábrica; "hola" y demás módulos lo leen en vivo.
// - Claves niri./infinito.: generan ~/.config/niri/ajustes.kdl, que ajustes-niri.sh valida antes de usar.
// - Cada cambio entra en el historial (~/.local/state/ajustes/historial.json) y se puede deshacer.
// - NO se recarga sola (watchFiles = false): matugen reescribe Colors.qml y perdería lo que estás haciendo.
ShellRoot {
    id: root

    Component.onCompleted: {
        Quickshell.watchFiles = false
        var s = Quickshell.env("AJUSTES_SECCION") || ""
        if (s !== "") root.irASeccion(s)
    }

    Catalogo { id: catalogo }
    readonly property var secciones: catalogo.secciones
    readonly property var opciones: catalogo.opciones

    // ===== Estilo =====
    readonly property string fuente: "JetBrainsMono Nerd Font"
    function alfa(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function ic(cp) { return String.fromCodePoint(cp) }
    function rutaIcono(n) { return Quickshell.iconPath(n, "audio-x-generic") }
    function ejecutar(cmd) { Quickshell.execDetached(cmd) }
    function refrescarWifi() {}      // la barra refresca el suyo sola
    QtObject {
        id: colores
        property color surface: "#1f0f0c"
        property color surfaceText: "#fddbd6"
        property color primary: "#ffb4a8"
        property color primaryText: "#690000"
    }
    readonly property alias tema: colores
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/hola/Colors.qml"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var t = text()
            for (var nombre of ["surface", "surfaceText", "primary", "primaryText"]) {
                var m = new RegExp("property color " + nombre + "\\s*:\\s*\"(#[0-9a-fA-F]{6,8})\"").exec(t)
                if (m) colores[nombre] = m[1]
            }
        }
    }

    // ===== Valores =====
    readonly property string carpeta: Quickshell.env("HOME") + "/.config/quickshell/ajustes"
    property var estado: ({})        // solo lo que difiere de fábrica
    property bool cargado: false
    function opcionDe(id) { return root.opciones.find(o => o.id === id) || (id === "niri.principal" ? { t: "Monitor principal" } : null) }
    function fabrica(id) { var o = root.opcionDe(id); return o ? o.def : undefined }
    function valor(id) {
        var e = root.estado
        return e[id] !== undefined ? e[id] : root.fabrica(id)
    }

    FileView {
        id: archivo
        path: root.carpeta + "/ajustes.json"
        printErrors: false
        onLoaded: {
            try {
                var d = JSON.parse(text())
                if (d && typeof d === "object" && !Array.isArray(d)) root.estado = d
            } catch (e) {
                Quickshell.execDetached(["cp", "-f", "--", archivo.path, archivo.path + ".corrupto"])
                root.avisar("ajustes.json estaba dañado: se guardó una copia y se usan los valores de fábrica.", true)
            }
            root.cargado = true
        }
        onLoadFailed: root.cargado = true
    }

    // ===== Cambios =====
    // cambios: { clave: valor }; undefined = volver a fábrica. Las claves "sonido." no pasan por aquí.
    property bool aplicando: false
    property var pendiente: null
    function esNiri(k) { return k.indexOf("niri.") === 0 || k.indexOf("infinito.") === 0 }

    function cambiar(id, v) {
        var o = root.opcionDe(id)
        if (!o) return
        var c = {}
        c[id] = v
        root.aplicar(c, o.t)
    }
    function aplicar(cambios, titulo, sinHistorial) {
        var antes = []
        var nuevo = Object.assign({}, root.estado)
        var tocaNiri = false
        for (var k in cambios) {
            var v = cambios[k]
            if (JSON.stringify(v) === JSON.stringify(root.valor(k))) continue
            antes.push({ clave: k, antes: root.estado[k] === undefined ? null : root.estado[k] })
            if (v === undefined || v === null || JSON.stringify(v) === JSON.stringify(root.fabrica(k))) delete nuevo[k]
            else nuevo[k] = v
            if (root.esNiri(k)) tocaNiri = true
        }
        if (antes.length === 0) return
        var paso = { estado: nuevo, titulo: titulo, antes: antes, sinHistorial: !!sinHistorial }
        if (!tocaNiri) { root.confirmar(paso); return }
        // niri primero: si no lo acepta, nada cambia
        if (pNiri.running) { root.pendiente = paso; return }
        root.lanzarNiri(paso)
    }
    function lanzarNiri(paso) {
        root.aplicando = true
        pNiri.paso = paso
        pNiri.stdinEnabled = true
        pNiri.running = true
    }
    Process {
        id: pNiri
        property var paso: null
        property string errorTexto: ""
        command: [Quickshell.env("HOME") + "/.local/bin/ajustes-niri.sh"]
        stdinEnabled: true
        onStarted: {
            pNiri.write(root.generarKdl(pNiri.paso.estado))
            pNiri.stdinEnabled = false
        }
        stdout: StdioCollector { onStreamFinished: pNiri.errorTexto = text }
        onExited: code => {
            root.aplicando = false
            // El texto llega justo después de exited: se resuelve en la vuelta siguiente
            Qt.callLater(() => {
                if (code === 0) root.confirmar(pNiri.paso)
                else root.avisar("niri no aceptó el cambio y no se aplicó: " + (pNiri.errorTexto.trim() || ("error " + code)), true)
                if (root.pendiente) { var p = root.pendiente; root.pendiente = null; root.lanzarNiri(p) }
            })
        }
    }
    function confirmar(paso) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/ajustes-respaldo.sh", archivo.path])
        root.estado = paso.estado
        archivo.setText(JSON.stringify(paso.estado, null, 2) + "\n")
        if (!paso.sinHistorial) root.registrar(paso.titulo, paso.antes)
        else root.avisar("Deshecho: " + paso.titulo, false)
    }

    // ===== Generar ajustes.kdl =====
    function kdlTexto(t) { return '"' + String(t).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"' }
    function generarKdl(e) {
        function v(id) { return e[id] !== undefined ? e[id] : root.fabrica(id) }
        function bloque(prefijo) {
            var l = []
            if (v(prefijo + ".natural")) l.push("natural-scroll")
            if (v(prefijo + ".speed") !== 0) l.push("accel-speed " + v(prefijo + ".speed"))
            if (v(prefijo + ".perfil") !== "adaptive") l.push("accel-profile " + root.kdlTexto(v(prefijo + ".perfil")))
            if (v(prefijo + ".scroll") !== 1) l.push("scroll-factor " + v(prefijo + ".scroll"))
            return l
        }
        var t = ["// Lo genera la app de Ajustes (ajustes-niri.sh lo valida antes de usarlo). No lo edites a mano: cambia desde Ajustes.", ""]
        t.push("input {", "    keyboard {")
        var xkb = []
        if (v("niri.kb.layout") !== "") xkb.push("            layout " + root.kdlTexto(v("niri.kb.layout")))
        if (v("niri.kb.options") !== "") xkb.push("            options " + root.kdlTexto(v("niri.kb.options")))
        if (xkb.length) t.push("        xkb {", ...xkb, "        }")
        t.push("        repeat-delay " + v("niri.kb.delay"), "        repeat-rate " + v("niri.kb.rate"))
        if (v("niri.kb.numlock")) t.push("        numlock")
        t.push("    }", "    touchpad {")
        if (v("niri.tp.tap")) t.push("        tap")
        if (v("niri.tp.dwt")) t.push("        dwt")
        if (v("niri.tp.externo")) t.push("        disabled-on-external-mouse")
        bloque("niri.tp").forEach(l => t.push("        " + l))
        t.push("    }", "    mouse {")
        if (v("niri.mouse.zurdo")) t.push("        left-handed")
        bloque("niri.mouse").forEach(l => t.push("        " + l))
        t.push("    }", "}", "")

        // Salidas: una por bloque (niri no las mezcla)
        var porSalida = {}
        Object.keys(e).forEach(k => {
            var m = /^niri\.output\.(.+)\.([a-z]+)$/.exec(k)
            if (!m) return
            if (!porSalida[m[1]]) porSalida[m[1]] = {}
            porSalida[m[1]][m[2]] = e[k]
        })
        var ppal = e["niri.principal"]
        if (ppal && !porSalida[ppal]) porSalida[ppal] = {}
        Object.keys(porSalida).sort().forEach(n => {
            var o = porSalida[n]
            t.push("output " + root.kdlTexto(n) + " {")
            if (n === ppal) t.push("    focus-at-startup")
            if (o.off) t.push("    off")
            if (o.mode) t.push("    mode " + root.kdlTexto(o.mode))
            if (o.scale) t.push("    scale " + o.scale)
            if (o.transform) t.push("    transform " + root.kdlTexto(o.transform))
            if (o.position) t.push("    position x=" + o.position[0] + " y=" + o.position[1])
            if (o.vrr) t.push("    variable-refresh-rate")
            t.push("}", "")
        })

        var binds = []
        if (!v("infinito.workspaces")) binds.push(
            'Mod+Page_Down { focus-workspace-down; }', 'Mod+Page_Up { focus-workspace-up; }',
            'Mod+U { focus-workspace-down; }', 'Mod+I { focus-workspace-up; }',
            'Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }', 'Mod+WheelScrollUp cooldown-ms=150 { focus-workspace-up; }',
            'Mod+TouchpadScrollDown cooldown-ms=300 { focus-workspace-down; }', 'Mod+TouchpadScrollUp cooldown-ms=300 { focus-workspace-up; }')
        if (!v("infinito.columnas")) binds.push(
            'Mod+Left { focus-column-left; }', 'Mod+Right { focus-column-right; }', 'Mod+H { focus-column-left; }', 'Mod+L { focus-column-right; }',
            'Mod+Down { focus-window-down; }', 'Mod+Up { focus-window-up; }', 'Mod+J { focus-window-down; }', 'Mod+K { focus-window-up; }',
            'Mod+WheelScrollRight { focus-column-right; }', 'Mod+WheelScrollLeft { focus-column-left; }',
            'Mod+Shift+WheelScrollDown { focus-column-right; }', 'Mod+Shift+WheelScrollUp { focus-column-left; }',
            'Mod+TouchpadScrollRight cooldown-ms=200 { focus-column-right; }', 'Mod+TouchpadScrollLeft cooldown-ms=200 { focus-column-left; }')
        if (binds.length) {
            t.push("binds {")
            binds.forEach(b => t.push("    " + b))
            t.push("}", "")
        }
        return t.join("\n")
    }

    // ===== Historial =====
    property var historial: []       // [{ ts, titulo, antes: [{ clave, antes }] }], lo más nuevo primero
    readonly property string carpetaEstado: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ajustes"
    FileView {
        id: archivoHistorial
        path: root.carpetaEstado + "/historial.json"
        printErrors: false
        onLoaded: { try { root.historial = JSON.parse(text()) } catch (e) {} }
    }
    function guardarHistorial() {
        Quickshell.execDetached(["mkdir", "-p", root.carpetaEstado])
        archivoHistorial.setText(JSON.stringify(root.historial) + "\n")
    }
    function registrar(titulo, antes) {
        // Varios cambios seguidos de lo mismo cuentan como uno: Deshacer vuelve al valor de antes de empezar
        var ult = root.historial[0]
        var mismo = ult && ult.titulo === titulo && Date.now() - ult.ts < 5000
            && JSON.stringify(ult.antes.map(a => a.clave)) === JSON.stringify(antes.map(a => a.clave))
        if (mismo) root.historial = [{ ts: Date.now(), titulo: titulo, antes: ult.antes }].concat(root.historial.slice(1))
        else root.historial = [{ ts: Date.now(), titulo: titulo, antes: antes }].concat(root.historial).slice(0, 100)
        root.guardarHistorial()
        root.avisar("Cambiado: " + titulo, false, true)
    }
    function deshacer(i) {
        var h = root.historial[i]
        if (!h) return
        root.historial = root.historial.filter((x, n) => n !== i)
        root.guardarHistorial()
        var normales = {}
        var hay = false
        h.antes.forEach(a => {
            if (a.clave.indexOf("sonido.") === 0 || a.clave.indexOf("ext.") === 0) root.deshacerExterno(a)
            else { normales[a.clave] = a.antes; hay = true }
        })
        if (hay) root.aplicar(normales, h.titulo, true)
        else root.avisar("Deshecho: " + h.titulo, false)
    }

    // ===== Restablecer =====
    function restablecer(seccion) {
        var sec = root.secciones.find(s => s.id === seccion)
        if (!sec) return
        if (seccion === "sonido") { root.restablecerSonido(); return }
        var c = {}
        root.opciones.filter(o => o.s === seccion && o.tipo !== "libre").forEach(o => c[o.id] = undefined)
        if (seccion === "pantalla") Object.keys(root.estado).filter(k => k.indexOf("niri.output.") === 0 || k === "niri.principal").forEach(k => c[k] = undefined)
        root.aplicar(c, "Restablecer " + sec.t)
    }

    // ===== Sonido =====
    readonly property var nodosAudio: Pipewire.nodes.values
    // Varios flujos pueden llamarse igual (dos de Firefox): los volúmenes van por id. Los dispositivos, por nombre,
    // porque su id cambia al reconectarlos.
    function nodoPorNombre(n) { return root.nodosAudio.find(x => x.name === n) || null }
    function nodoDe(a) { return a.id !== undefined ? (root.nodosAudio.find(x => x.id === a.id) || null) : root.nodoPorNombre(a.nodo) }
    property var volumenAntes: ({})
    property string volumenTitulo: ""
    function ponerVolumen(n, v, titulo) {
        if (!n || !n.audio) return
        if (root.volumenAntes[n.id] === undefined) root.volumenAntes[n.id] = n.audio.volume
        root.volumenTitulo = titulo
        n.audio.muted = false
        n.audio.volume = Math.max(0, Math.min(1, v))
        registrarVolumen.restart()
    }
    Timer {
        id: registrarVolumen
        interval: 800
        onTriggered: {
            var a = []
            for (var id in root.volumenAntes) a.push({ clave: "sonido.volumen", id: Number(id), antes: root.volumenAntes[id] })
            root.volumenAntes = ({})
            if (a.length) root.registrar(root.volumenTitulo, a)
        }
    }
    function alternarMudo(n, titulo) {
        if (!n || !n.audio) return
        root.registrar(titulo, [{ clave: "sonido.mudo", id: n.id, antes: n.audio.muted }])
        n.audio.muted = !n.audio.muted
    }
    function ponerDispositivo(clave, n, titulo) {
        var actual = clave === "sonido.salida" ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
        if (actual === n) return
        root.registrar(titulo, [{ clave: clave, nodo: actual ? actual.name : "" }])
        if (clave === "sonido.salida") Pipewire.preferredDefaultAudioSink = n
        else Pipewire.preferredDefaultAudioSource = n
    }
    // Lo que no vive en ajustes.json: va a su dueño (PipeWire, hola, bloqueo, NetworkManager, BlueZ)
    function deshacerExterno(a) {
        var hola = ["qs", "-c", "hola", "ipc", "call", "hola"]
        if (a.clave === "ext.brillo") root.ejecutar(["brightnessctl", "-q", "set", a.antes + "%"])
        else if (a.clave === "ext.luzModo") root.ejecutar(hola.concat(["luzNocturna", a.antes]))
        else if (a.clave === "ext.luzTemp") root.ejecutar(hola.concat(["temperaturaNocturna", String(a.antes)]))
        else if (a.clave === "ext.luzUbic") root.ejecutar(hola.concat(["ubicacionNocturna", String(a.lat), String(a.lon)]))
        else if (a.clave === "ext.perfil") root.ponerPerfil(a.antes)
        else if (a.clave === "ext.limite") root.ejecutar(hola.concat(["bateriaLimite", a.antes ? "si" : "no"]))
        else if (a.clave === "ext.cafeina") root.ejecutar(["qs", "-c", "bloqueo", "ipc", "call", "bloqueo", "cafeina", a.antes ? "si" : "no"])
        else if (a.clave === "ext.redAuto") root.ejecutar(["nmcli", "connection", "modify", a.uuid, "connection.autoconnect", a.antes ? "yes" : "no"])
        else if (a.clave === "ext.bt") { if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = a.antes }
        else if (a.clave === "ext.btVisible") { if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discoverable = a.antes }
        else if (a.clave === "ext.btConfianza") {
            var d = Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices.values.find(x => x.address === a.mac) : null
            if (d) d.trusted = a.antes
            else root.avisar("Ese dispositivo ya no está.", true)
        }
        else root.deshacerSonido(a)
    }
    function ponerPerfil(v) {
        PowerProfiles.profile = v === "ahorro" ? PowerProfile.PowerSaver : v === "rendimiento" ? PowerProfile.Performance : PowerProfile.Balanced
    }

    // ===== Pantalla: se prueba sin guardar; si no confirmas en 15 s, vuelve sola =====
    // Quién revierte de verdad es ajustes-pantalla.sh (proceso aparte): funciona aunque esta app se cierre.
    signal pantallaResuelta()
    property var pantalla: null       // { ops: [{ salida, id, clave, valor, args, volver }], titulo }
    property int cuentaPantalla: 15
    readonly property string scriptPantalla: Quickshell.env("HOME") + "/.local/bin/ajustes-pantalla.sh"
    // Solo pruebas: monitores inventados; nada llega a niri ni a la config
    property var salidasSimuladas: null
    property var ultimaSimulada: null
    function listaOps(ops, campo) {
        var l = []
        ops.forEach(o => { l = l.concat(["@", o.salida], o[campo]) })
        return l
    }
    function probarPantalla(ops, titulo) {
        if (root.pantalla || pPantalla.running) return
        if (root.salidasSimuladas) {
            root.pantalla = { ops: ops, titulo: titulo }
            root.cuentaPantalla = 15
            relojPantalla.restart()
            return
        }
        pPantalla.previsto = { ops: ops, titulo: titulo }
        pPantalla.command = [root.scriptPantalla, "probar"].concat(root.listaOps(ops, "args"), ["--"], root.listaOps(ops, "volver"))
        pPantalla.running = true
    }
    Process {
        id: pPantalla
        property var previsto: null
        property string salidaTexto: ""
        stdout: StdioCollector { onStreamFinished: pPantalla.salidaTexto = text }
        onExited: code => {
            Qt.callLater(() => {
                if (code === 0) {
                    root.pantalla = pPantalla.previsto
                    root.cuentaPantalla = 15
                    relojPantalla.restart()
                } else root.avisar("niri no aceptó ese cambio: " + (pPantalla.salidaTexto.trim() || ("error " + code)), true)
                root.pantallaResuelta()
            })
        }
    }
    Timer {
        id: relojPantalla
        interval: 1000
        repeat: true
        onTriggered: {
            root.cuentaPantalla--
            if (root.cuentaPantalla <= 0) root.revertirPantalla()
        }
    }
    function revertirPantalla() {
        if (!root.pantalla) return
        relojPantalla.stop()
        if (!root.salidasSimuladas) root.ejecutar([root.scriptPantalla, "revertir"].concat(root.listaOps(root.pantalla.ops, "volver")))
        root.avisar("Se volvió a la configuración anterior de la pantalla.", false)
        root.pantalla = null
        resolverLuego.restart()
    }
    function conservarPantalla() {
        if (!root.pantalla) return
        relojPantalla.stop()
        var p = root.pantalla
        root.pantalla = null
        if (root.salidasSimuladas) {
            root.ultimaSimulada = p
            root.salidasSimuladas = root.salidasSimuladas.map(o => {
                var r = p.ops.find(x => x.salida === o.name && x.clave === "position")
                return r ? Object.assign({}, o, { logical: Object.assign({}, o.logical, { x: r.valor[0], y: r.valor[1] }) }) : o
            })
            return
        }
        root.ejecutar([root.scriptPantalla, "conservar"])
        var c = {}
        p.ops.forEach(o => {
            // Lo que coincide con lo normal no se guarda
            var nada = o.valor === false || o.valor === "normal"
            c["niri.output." + o.id + "." + o.clave] = nada ? undefined : o.valor
        })
        root.aplicar(c, p.titulo)
        resolverLuego.restart()
    }
    Timer { id: resolverLuego; interval: 500; onTriggered: root.pantallaResuelta() }
    function deshacerSonido(a) {
        var n = root.nodoDe(a)
        if (!n) { root.avisar("Esa aplicación o dispositivo ya no está.", true); return }
        if (a.clave === "sonido.volumen" && n.audio) n.audio.volume = a.antes
        else if (a.clave === "sonido.mudo" && n.audio) n.audio.muted = a.antes
        else if (a.clave === "sonido.salida") Pipewire.preferredDefaultAudioSink = n
        else if (a.clave === "sonido.entrada") Pipewire.preferredDefaultAudioSource = n
    }
    function restablecerSonido() {
        var a = []
        root.nodosAudio.filter(n => n.audio && n.isStream && n.isSink).forEach(n => {
            if (n.audio.volume !== 1) a.push({ clave: "sonido.volumen", id: n.id, antes: n.audio.volume })
            if (n.audio.muted) a.push({ clave: "sonido.mudo", id: n.id, antes: true })
            n.audio.muted = false
            n.audio.volume = 1
        })
        if (a.length) root.registrar("Restablecer Sonido", a)
        else root.avisar("Las aplicaciones ya están al 100 %.", false)
    }

    // ===== Navegación =====
    property string seccion: "entrada"     // "cambios" = cambios recientes
    property string resaltada: ""
    property var filas: ({})
    function registrarFila(id, item) { root.filas[id] = item }
    function quitarFila(id, item) { if (root.filas[id] === item) delete root.filas[id] }
    function irASeccion(s) {
        if (s === "cambios" || root.secciones.some(x => x.id === s)) root.seccion = s
        else if (s !== "") root.avisar("No existe la sección «" + s + "».", true)
    }
    Timer { id: quitarResalte; interval: 1800; onTriggered: root.resaltada = "" }
    function irAOpcion(id) {
        var o = root.opcionDe(id)
        if (!o) { root.irASeccion(id); return }
        root.seccion = o.s
        root.resaltada = id
        quitarResalte.restart()
        desplazar.objetivo = id
        desplazar.restart()
    }
    Timer {
        id: desplazar
        property string objetivo: ""
        interval: 60      // deja que la sección se construya
        onTriggered: root.verFila(objetivo)
    }
    signal verFila(string id)
    function soltarFoco() { raizVentana.forceActiveFocus() }

    // ===== Buscador =====
    property string consulta: ""
    function normal(t) { return String(t || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase() }
    readonly property var resultados: {
        var q = root.normal(root.consulta).trim()
        if (q === "") return []
        var partes = q.split(/\s+/)
        var l = []
        root.opciones.forEach(o => {
            var sec = root.secciones.find(s => s.id === o.s)
            var todo = root.normal([o.t, o.a, o.p, o.g, sec ? sec.t : ""].join(" "))
            if (!partes.every(p => todo.indexOf(p) >= 0)) return
            var tit = root.normal(o.t)
            l.push({ id: o.id, t: o.t, s: (sec ? sec.t : "") + (o.g ? " · " + o.g : ""), ic: sec ? sec.ic : 0xF0493,
                     peso: tit.indexOf(q) === 0 ? 0 : tit.indexOf(q) >= 0 ? 1 : 2 })
        })
        root.secciones.forEach(s => {
            if (partes.every(p => root.normal(s.t).indexOf(p) >= 0))
                l.push({ id: s.id, t: s.t, s: s.fase ? "Sección · llega en la fase " + s.fase : "Sección", ic: s.ic, peso: -1 })
        })
        return l.sort((a, b) => a.peso - b.peso).slice(0, 8)
    }
    property int elegido: 0
    onResultadosChanged: root.elegido = 0
    function abrirResultado(i) {
        var r = root.resultados[i]
        if (!r) return
        root.consulta = ""
        campoBuscar.text = ""
        root.soltarFoco()
        root.irAOpcion(r.id)
    }

    // ===== Avisos dentro de la ventana =====
    property string avisoTexto: ""
    property bool avisoError: false
    property bool avisoDeshacer: false
    function avisar(t, error, conDeshacer) {
        root.avisoTexto = t
        root.avisoError = !!error
        root.avisoDeshacer = !!conDeshacer
        // Un error se queda hasta cerrarlo: hay que poder leerlo
        if (error) quitarAviso.stop(); else quitarAviso.restart()
    }
    Timer { id: quitarAviso; interval: 6000; onTriggered: root.avisoTexto = "" }

    // ===== Ventana =====
    FloatingWindow {
        id: ventana
        title: "Ajustes"
        visible: true
        implicitWidth: 1040
        implicitHeight: 700
        minimumSize: Qt.size(760, 480)
        color: "transparent"
        onVisibleChanged: if (!visible) Qt.quit()

        Rectangle {
            id: raizVentana
            anchors.fill: parent
            focus: true
            color: root.alfa(colores.surface, 0.86)
            Keys.onEscapePressed: { if (root.pantalla) root.revertirPantalla(); else Qt.quit() }
            Keys.onPressed: e => {
                if (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier)) { campoBuscar.forceActiveFocus(); e.accepted = true }
            }

            // ----- ¿Conservar la pantalla? (encima de todo) -----
            Rectangle {
                visible: !!root.pantalla
                anchors.fill: parent
                z: 100
                color: Qt.rgba(0, 0, 0, 0.55)
                MouseArea { anchors.fill: parent; hoverEnabled: true }
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(440, parent.width - 48)
                    height: colPantalla.implicitHeight + 40
                    radius: 18
                    color: Qt.tint(colores.surface, root.alfa(colores.primary, 0.08))
                    border.width: 1.5
                    border.color: root.alfa(colores.primary, 0.6)
                    Column {
                        id: colPantalla
                        x: 20
                        y: 20
                        width: parent.width - 40
                        spacing: 10
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "¿Conservar este cambio?"
                            font.family: root.fuente
                            font.pixelSize: 16
                            font.bold: true
                            color: colores.surfaceText
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: (root.pantalla ? root.pantalla.titulo + ". " : "") + "Vuelve a como estaba en " + root.cuentaPantalla + " s."
                            textFormat: Text.PlainText
                            font.family: root.fuente
                            font.pixelSize: 12
                            color: root.alfa(colores.surfaceText, 0.8)
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: 8
                            BotonTexto { tema: colores; fuente: root.fuente; texto: "Revertir"; onClic: root.revertirPantalla() }
                            BotonTexto { tema: colores; fuente: root.fuente; lleno: true; texto: "Conservar"; onClic: root.conservarPantalla() }
                        }
                    }
                }
            }

            // ----- Barra lateral -----
            Rectangle {
                id: lateral
                width: 244
                height: parent.height
                color: root.alfa(colores.primary, 0.05)

                Text {
                    id: tituloApp
                    x: 18
                    y: 16
                    text: "Ajustes"
                    font.family: root.fuente
                    font.pixelSize: 18
                    font.bold: true
                    color: colores.surfaceText
                }
                Boton {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: tituloApp.verticalCenter
                    tema: colores
                    fuente: root.fuente
                    icono: root.ic(0xF0156)
                    onClic: Qt.quit()
                }
                Flickable {
                    anchors.top: tituloApp.bottom
                    anchors.topMargin: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    x: 8
                    width: parent.width - 16
                    contentHeight: listaSecciones.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: listaSecciones
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: root.secciones.concat([{ id: "cambios", t: "Cambios recientes", ic: 0xF02DA }])
                            delegate: Rectangle {
                                id: filaSec
                                required property var modelData
                                readonly property bool actual: root.seccion === filaSec.modelData.id
                                width: listaSecciones.width
                                height: 36
                                radius: 12
                                color: filaSec.actual ? root.alfa(colores.primary, 0.22)
                                    : root.alfa(colores.primary, maSec.containsMouse ? 0.1 : 0)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    id: icSec
                                    x: 10
                                    width: 20
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.ic(filaSec.modelData.ic)
                                    font.family: root.fuente
                                    font.pixelSize: 15
                                    color: colores.primary
                                    opacity: filaSec.modelData.fase ? 0.5 : 1
                                }
                                Text {
                                    anchors.left: icSec.right
                                    anchors.leftMargin: 10
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: filaSec.modelData.t
                                    font.family: root.fuente
                                    font.pixelSize: 12
                                    font.bold: filaSec.actual
                                    color: root.alfa(colores.surfaceText, filaSec.modelData.fase ? 0.55 : 1)
                                }
                                MouseArea {
                                    id: maSec
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.irASeccion(filaSec.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            // ----- Contenido -----
            Item {
                id: zona
                anchors.left: lateral.right
                anchors.right: parent.right
                height: parent.height

                readonly property var sec: root.secciones.find(s => s.id === root.seccion) || null
                readonly property var grupos: {
                    var l = []
                    root.opciones.filter(o => o.s === root.seccion && o.tipo !== "libre").forEach(o => {
                        var g = l.find(x => x.g === o.g)
                        if (!g) { g = { g: o.g, ops: [] }; l.push(g) }
                        g.ops.push(o)
                    })
                    return l
                }

                // Buscador
                Rectangle {
                    id: cajaBuscar
                    x: 22
                    y: 14
                    width: parent.width - 44
                    height: 38
                    radius: 19
                    color: root.alfa(colores.surfaceText, 0.07)
                    border.width: 1.5
                    border.color: campoBuscar.activeFocus ? colores.primary : root.alfa(colores.primary, 0.35)
                    Text {
                        id: icBuscar
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.ic(0xF0349)
                        font.family: root.fuente
                        font.pixelSize: 15
                        color: colores.primary
                    }
                    TextInput {
                        id: campoBuscar
                        anchors.left: icBuscar.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        selectByMouse: true
                        focus: true
                        font.family: root.fuente
                        font.pixelSize: 13
                        color: colores.surfaceText
                        selectionColor: colores.primary
                        selectedTextColor: colores.primaryText
                        onTextChanged: root.consulta = text
                        Keys.onDownPressed: root.elegido = Math.min(root.resultados.length - 1, root.elegido + 1)
                        Keys.onUpPressed: root.elegido = Math.max(0, root.elegido - 1)
                        onAccepted: root.abrirResultado(root.elegido)
                        Keys.onEscapePressed: { if (text !== "") text = ""; else if (root.pantalla) root.revertirPantalla(); else Qt.quit() }
                        Text {
                            visible: campoBuscar.text === ""
                            width: parent.width
                            elide: Text.ElideRight
                            text: "Buscar cualquier ajuste…"
                            font: campoBuscar.font
                            color: root.alfa(colores.surfaceText, 0.45)
                        }
                    }
                }

                // Sección
                Flickable {
                    id: desplazable
                    anchors.top: cajaBuscar.bottom
                    anchors.topMargin: 14
                    anchors.bottom: pieAviso.visible ? pieAviso.top : parent.bottom
                    anchors.bottomMargin: 8
                    x: 22
                    width: parent.width - 44
                    contentHeight: colSeccion.implicitHeight + 12
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Connections {
                        target: root
                        function onVerFila(id) {
                            var f = root.filas[id]
                            if (!f) return
                            var y = f.mapToItem(colSeccion, 0, 0).y
                            desplazable.contentY = Math.max(0, Math.min(desplazable.contentHeight - desplazable.height, y - 40))
                        }
                    }
                    Connections {
                        target: root
                        function onSeccionChanged() { desplazable.contentY = 0; confirmarReset.activo = false }
                    }

                    Column {
                        id: colSeccion
                        width: parent.width
                        spacing: 8

                        // Cabecera: título, descripción y Restablecer
                        Item {
                            width: parent.width
                            height: Math.max(cabecera.implicitHeight, 34)
                            Column {
                                id: cabecera
                                width: parent.width - (botonReset.visible ? botonReset.width + 16 : 0)
                                spacing: 2
                                Text {
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: root.seccion === "cambios" ? "Cambios recientes" : zona.sec ? zona.sec.t : ""
                                    font.family: root.fuente
                                    font.pixelSize: 20
                                    font.bold: true
                                    color: colores.surfaceText
                                }
                                Text {
                                    visible: text !== ""
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: root.seccion === "cambios" ? "Puedes deshacer cada uno. Se guardan los últimos 100."
                                        : confirmarReset.activo && zona.sec && zona.sec.restablece ? zona.sec.restablece
                                        : zona.sec && zona.sec.d ? zona.sec.d : ""
                                    font.family: root.fuente
                                    font.pixelSize: 11
                                    color: root.alfa(colores.surfaceText, 0.65)
                                }
                            }
                            BotonTexto {
                                id: botonReset
                                visible: !!zona.sec && !zona.sec.fase && !zona.sec.sinRestablecer
                                anchors.right: parent.right
                                tema: colores
                                fuente: root.fuente
                                peligro: confirmarReset.activo
                                texto: confirmarReset.activo ? "¿Seguro? Toca otra vez" : "Restablecer"
                                onClic: {
                                    if (!confirmarReset.activo) { confirmarReset.activo = true; return }
                                    confirmarReset.activo = false
                                    root.restablecer(root.seccion)
                                }
                            }
                            Timer {
                                id: confirmarReset
                                property bool activo: false
                                interval: 4000
                                running: activo
                                onTriggered: activo = false
                            }
                        }

                        // Parte con pantalla propia
                        Loader {
                            active: ["sonido", "pantalla", "energia", "red"].indexOf(root.seccion) >= 0
                            visible: active
                            width: parent.width
                            sourceComponent: root.seccion === "sonido" ? compSonido : root.seccion === "pantalla" ? compPantalla
                                : root.seccion === "energia" ? compEnergia : root.seccion === "red" ? compRed : null
                        }
                        Component { id: compSonido; SeccionSonido { raiz: root } }
                        Component { id: compPantalla; SeccionPantalla { raiz: root } }
                        Component { id: compEnergia; SeccionEnergia { raiz: root } }
                        Component { id: compRed; SeccionRed { raiz: root } }

                        // Sección generada desde el catálogo
                        Repeater {
                            model: zona.grupos
                            delegate: Column {
                                id: grupo
                                required property var modelData
                                width: colSeccion.width
                                spacing: 6
                                topPadding: 6
                                Etiqueta { s: root; tema: colores; texto: grupo.modelData.g || "" }
                                Repeater {
                                    model: grupo.modelData.ops
                                    delegate: FilaAjuste {
                                        required property var modelData
                                        op: modelData
                                        raiz: root
                                        width: grupo.width
                                    }
                                }
                            }
                        }

                        // Pendiente
                        Column {
                            visible: !!zona.sec && !!zona.sec.fase
                            width: parent.width
                            spacing: 4
                            topPadding: 18
                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: zona.sec ? "Esta sección llega en la fase " + zona.sec.fase + "." : ""
                                font.family: root.fuente
                                font.pixelSize: 13
                                color: root.alfa(colores.surfaceText, 0.65)
                            }
                        }

                        // Cambios recientes
                        Text {
                            visible: root.seccion === "cambios" && root.historial.length === 0
                            width: parent.width
                            wrapMode: Text.Wrap
                            topPadding: 18
                            text: "Aún no has cambiado nada desde aquí."
                            font.family: root.fuente
                            font.pixelSize: 13
                            color: root.alfa(colores.surfaceText, 0.65)
                        }
                        Repeater {
                            model: root.seccion === "cambios" ? root.historial : []
                            delegate: Rectangle {
                                id: filaCambio
                                required property var modelData
                                required property int index
                                width: colSeccion.width
                                height: Math.max(textosCambio.implicitHeight, 32) + 20
                                radius: 14
                                color: root.alfa(colores.primary, 0.07)
                                Column {
                                    id: textosCambio
                                    x: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 28 - botonDeshacer.width - 12
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.Wrap
                                        text: filaCambio.modelData.titulo
                                        textFormat: Text.PlainText
                                        font.family: root.fuente
                                        font.pixelSize: 13
                                        color: colores.surfaceText
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: new Date(filaCambio.modelData.ts).toLocaleString(Qt.locale("es_EC"), "d MMM, HH:mm")
                                        font.family: root.fuente
                                        font.pixelSize: 10
                                        color: root.alfa(colores.surfaceText, 0.6)
                                    }
                                }
                                BotonTexto {
                                    id: botonDeshacer
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    tema: colores
                                    fuente: root.fuente
                                    texto: "Deshacer"
                                    onClic: root.deshacer(filaCambio.index)
                                }
                            }
                        }
                    }
                }

                // Resultados del buscador (encima de la sección)
                Rectangle {
                    visible: root.consulta.trim() !== ""
                    x: cajaBuscar.x
                    y: cajaBuscar.y + cajaBuscar.height + 6
                    width: cajaBuscar.width
                    height: colResultados.implicitHeight + 12
                    radius: 16
                    color: Qt.tint(colores.surface, root.alfa(colores.primary, 0.08))
                    border.width: 1.5
                    border.color: root.alfa(colores.primary, 0.5)
                    z: 10
                    Column {
                        id: colResultados
                        x: 6
                        y: 6
                        width: parent.width - 12
                        spacing: 2
                        Text {
                            visible: root.resultados.length === 0
                            width: parent.width
                            leftPadding: 10
                            topPadding: 8
                            bottomPadding: 8
                            wrapMode: Text.Wrap
                            text: "Nada coincide con «" + root.consulta + "»"
                            textFormat: Text.PlainText
                            font.family: root.fuente
                            font.pixelSize: 12
                            color: root.alfa(colores.surfaceText, 0.65)
                        }
                        Repeater {
                            model: root.resultados
                            delegate: Rectangle {
                                id: filaRes
                                required property var modelData
                                required property int index
                                width: colResultados.width
                                height: 42
                                radius: 12
                                color: root.alfa(colores.primary, root.elegido === filaRes.index ? 0.22 : 0)
                                Text {
                                    id: icRes
                                    x: 10
                                    width: 20
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.ic(filaRes.modelData.ic)
                                    font.family: root.fuente
                                    font.pixelSize: 15
                                    color: colores.primary
                                }
                                Column {
                                    anchors.left: icRes.right
                                    anchors.leftMargin: 10
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: filaRes.modelData.t
                                        font.family: root.fuente
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: colores.surfaceText
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: filaRes.modelData.s
                                        font.family: root.fuente
                                        font.pixelSize: 10
                                        color: root.alfa(colores.surfaceText, 0.6)
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.elegido = filaRes.index
                                    onClicked: root.abrirResultado(filaRes.index)
                                }
                            }
                        }
                    }
                }

                // Aviso abajo: último cambio con Deshacer, o el error de niri
                Rectangle {
                    id: pieAviso
                    visible: root.avisoTexto !== ""
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    x: 22
                    width: parent.width - 44
                    height: Math.max(textoAviso.implicitHeight, 32) + 16
                    radius: 14
                    color: root.avisoError ? Qt.rgba(1, 0.33, 0.33, 0.22) : root.alfa(colores.primary, 0.16)
                    Text {
                        id: textoAviso
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28 - accionesAviso.width - 10
                        wrapMode: Text.Wrap
                        maximumLineCount: 8
                        elide: Text.ElideRight
                        text: root.avisoTexto
                        textFormat: Text.PlainText
                        font.family: root.fuente
                        font.pixelSize: 12
                        color: root.avisoError ? "#ff8a80" : colores.surfaceText
                    }
                    Row {
                        id: accionesAviso
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        BotonTexto {
                            visible: root.avisoDeshacer
                            tema: colores
                            fuente: root.fuente
                            texto: "Deshacer"
                            onClic: { root.avisoTexto = ""; root.deshacer(0) }
                        }
                        BotonTexto {
                            visible: root.avisoError
                            tema: colores
                            fuente: root.fuente
                            texto: "Cerrar"
                            onClic: root.avisoTexto = ""
                        }
                    }
                }
            }
        }
    }

    // ===== IPC: qs -c ajustes ipc call ajustes <función> =====
    IpcHandler {
        target: "ajustes"
        function abrir(seccion: string): void { if (seccion !== "") root.irASeccion(seccion) }
        function cerrar(): void { Qt.quit() }
        function ir(id: string): void { root.irAOpcion(id) }
        function buscar(t: string): string {
            root.consulta = t
            campoBuscar.text = t
            return JSON.stringify(root.resultados.map(r => r.id))
        }
        function valor(id: string): string { return JSON.stringify(root.valor(id)) }
        function poner(id: string, jsonValor: string): void { root.cambiar(id, JSON.parse(jsonValor)) }
        function restablecerSeccion(s: string): void { root.restablecer(s) }
        function deshacerUltimo(): void { root.deshacer(0) }
        function info(): string {
            return JSON.stringify({ seccion: root.seccion, aplicando: root.aplicando, resaltada: root.resaltada,
                aviso: root.avisoTexto, error: root.avisoError, cambios: root.historial.length, estado: root.estado })
        }
        function kdl(): string { return root.generarKdl(root.estado) }
        function pantallaEstado(): string { return JSON.stringify({ pendiente: root.pantalla, cuenta: root.cuentaPantalla }) }
        function conservar(): void { root.conservarPantalla() }
        function revertir(): void { root.revertirPantalla() }
        function probarEscala(salida: string, id: string, v: real, antes: real): void {
            root.probarPantalla([{ salida: salida, id: id, clave: "scale", valor: v, args: ["scale", String(v)], volver: ["scale", String(antes)] }], "Escala de " + salida + ": " + v)
        }
        // Monitores inventados para probar la vista sin tener otro (JSON como `niri msg -j outputs`, en lista; vacío = reales)
        function simular(base64: string): void { root.salidasSimuladas = base64 === "-" ? null : JSON.parse(Qt.atob(base64)) }
        function simulada(): string { return JSON.stringify(root.ultimaSimulada) }
    }
}
