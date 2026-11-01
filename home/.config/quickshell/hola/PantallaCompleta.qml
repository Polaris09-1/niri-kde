import Quickshell
import Quickshell.Io
import QtQuick

// ¿Qué monitores tienen una ventana a pantalla completa? (estado de niri por IPC)
// niri 26.04 no manda "is_fullscreen": una ventana está a pantalla completa cuando es la activa
// del workspace visible de su monitor y su tile mide lo mismo que el monitor. Una maximizada
// (Mod+F) mide menos (deja la barra y los huecos), así que no cuenta.
// Con la vista general abierta no hay pantalla completa (se ven todos los workspaces).
Scope {
    id: pc

    property var porSalida: ({})          // { "eDP-2": true }
    property var ventanaPorSalida: ({})   // { "eDP-2": 12 } id de la ventana a pantalla completa
    property bool vistaGeneral: false

    function en(salida) { return !!pc.porSalida[salida] }

    function calcular(t) {
        var d
        try { d = JSON.parse(t) } catch (e) { return }
        var ventanas = {}
        for (var i = 0; i < d.v.length; i++) ventanas[d.v[i].id] = d.v[i]
        var res = {}, ids = {}
        pc.vistaGeneral = !!(d.g && d.g.is_open)
        for (var j = 0; j < d.w.length; j++) {
            var ws = d.w[j]
            if (!ws.is_active || !ws.output || ws.active_window_id === null) continue
            var v = ventanas[ws.active_window_id]
            var o = d.o[ws.output]
            if (!v || !v.layout || !o || !o.logical) continue
            var t2 = v.layout.tile_size
            var lleno = Math.abs(t2[0] - o.logical.width) < 1 && Math.abs(t2[1] - o.logical.height) < 1
            if (lleno && !pc.vistaGeneral) { res[ws.output] = true; ids[ws.output] = v.id }
        }
        // Solo reasignar si cambió (evita reevaluar los bindings en cada evento)
        if (JSON.stringify(res) !== JSON.stringify(pc.porSalida)) pc.porSalida = res
        if (JSON.stringify(ids) !== JSON.stringify(pc.ventanaPorSalida)) pc.ventanaPorSalida = ids
    }

    Process {
        id: eventos
        command: ["niri", "msg", "-j", "event-stream"]
        running: true
        stdout: SplitParser { onRead: data => espera.restart() }
        onExited: reinicio.start()
    }
    Timer { id: reinicio; interval: 2000; onTriggered: eventos.running = true }

    // Los eventos llegan en ráfagas (abrir, redimensionar…): una sola consulta por ráfaga
    property bool pendiente: false
    Timer {
        id: espera
        interval: 40
        onTriggered: {
            if (consulta.running) pc.pendiente = true
            else consulta.running = true
        }
    }
    Process {
        id: consulta
        command: ["sh", "-c", "printf '{\"w\":'; niri msg -j workspaces; printf ',\"v\":'; niri msg -j windows;"
            + " printf ',\"o\":'; niri msg -j outputs; printf ',\"g\":'; niri msg -j overview-state || echo null; printf '}'"]
        stdout: StdioCollector { onStreamFinished: pc.calcular(text) }
        onExited: if (pc.pendiente) { pc.pendiente = false; consulta.running = true }
    }

    Component.onCompleted: consulta.running = true
}
