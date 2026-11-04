import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Espejo (M4, parte 2): dibuja un monitor en otro, porque niri no tiene espejo. Solo corre mientras se usa.
// No se lanza a mano: lo lanza y lo vigila ~/.local/bin/espejo.sh, que coloca el monitor reflejado y lo devuelve a su
// sitio al terminar, también si esto se cae. Aquí está lo demás:
// - La imagen, entera y con franjas negras si la proporción es otra. El cursor sale en ella.
// - Nada puede quedarse en el reflejado: cursor, foco y ventanas que lleguen vuelven al origen.
// - Si falta uno de los dos monitores, se apaga. `hola` lo vuelve a empezar al reconectarlo.
// La pantalla de bloqueo lo tapa sola: niri solo muestra la superficie de bloqueo de cada salida.
// Barra, dock y fondo no se dibujan en el reflejado: el singleton de la pantalla principal lo quita de su lista.
ShellRoot {
    id: root

    property string origen: ""
    property string destino: ""
    property bool leido: false

    readonly property var pantallaOrigen: Quickshell.screens.find(s => s.name === root.origen) || null
    readonly property var pantallaDestino: Quickshell.screens.find(s => s.name === root.destino) || null
    readonly property bool completos: root.pantallaOrigen !== null && root.pantallaDestino !== null

    Component.onCompleted: Quickshell.watchFiles = false

    // El estado lo escribe espejo.sh antes de lanzarnos; si desaparece, se terminó
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/espejo-activo.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                var d = JSON.parse(text())
                root.origen = d.origen
                root.destino = d.destino
                root.leido = true
            } catch (e) { Qt.quit() }
        }
        onLoadFailed: Qt.quit()
    }

    // Un monitor tarda en aparecer y las pantallas cambian varias veces seguidas: no apagarse por un parpadeo
    onCompletosChanged: if (root.completos) faltaUno.stop(); else if (root.leido) faltaUno.restart()
    onLeidoChanged: if (root.leido && !root.completos) faltaUno.restart()
    Timer { id: faltaUno; interval: 1000; onTriggered: if (!root.completos) Qt.quit() }

    function aOrigen() { Quickshell.execDetached(["niri", "msg", "action", "focus-monitor", root.origen]) }

    // ===== Devolver foco y ventanas =====
    property var salidaDe: ({})      // workspace → monitor
    property var ventanas: ({})      // ventana → workspace

    function revisarVentana(id) {
        if (root.salidaDe[root.ventanas[id]] === root.destino)
            Quickshell.execDetached(["niri", "msg", "action", "move-window-to-monitor", "--id", String(id), root.origen])
    }
    function evento(e) {
        if (e.WorkspacesChanged) {
            var m = {}
            e.WorkspacesChanged.workspaces.forEach(w => {
                m[w.id] = w.output
                if (w.is_focused && w.output === root.destino) root.aOrigen()
            })
            root.salidaDe = m
            Object.keys(root.ventanas).forEach(root.revisarVentana)
        } else if (e.WorkspaceActivated) {
            if (e.WorkspaceActivated.focused && root.salidaDe[e.WorkspaceActivated.id] === root.destino) root.aOrigen()
        } else if (e.WindowsChanged) {
            var v = {}
            e.WindowsChanged.windows.forEach(w => v[w.id] = w.workspace_id)
            root.ventanas = v
            Object.keys(v).forEach(root.revisarVentana)
        } else if (e.WindowOpenedOrChanged) {
            var w = e.WindowOpenedOrChanged.window
            root.ventanas[w.id] = w.workspace_id
            root.revisarVentana(w.id)
        } else if (e.WindowClosed) {
            delete root.ventanas[e.WindowClosed.id]
        }
    }
    Process {
        command: ["niri", "msg", "-j", "event-stream"]
        running: root.leido
        stdout: SplitParser {
            onRead: linea => {
                try { root.evento(JSON.parse(linea)) } catch (e) {}
            }
        }
    }

    // ===== La imagen =====
    PanelWindow {
        id: ventana
        visible: root.completos
        screen: root.pantallaDestino
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "espejo"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "black"

        ScreencopyView {
            id: imagen
            readonly property real k: sourceSize.width > 0 && sourceSize.height > 0
                ? Math.min(ventana.width / sourceSize.width, ventana.height / sourceSize.height) : 1
            anchors.centerIn: parent
            width: sourceSize.width * k
            height: sourceSize.height * k
            captureSource: root.pantallaOrigen
            live: true
            paintCursor: true
        }

        // Normalmente el cursor no llega aquí; si llega, vuelve. focus-monitor lo trae aunque el origen ya tenga el foco
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onContainsMouseChanged: if (containsMouse) root.aOrigen()
        }
    }

    IpcHandler {
        target: "espejo"
        function parar(): void { Qt.quit() }
        function info(): string {
            return JSON.stringify({
                origen: root.origen, destino: root.destino, completos: root.completos,
                imagen: imagen.hasContent, fuente: imagen.sourceSize.width + "x" + imagen.sourceSize.height,
                dibujo: Math.round(imagen.width) + "x" + Math.round(imagen.height),
                ventana: ventana.width + "x" + ventana.height
            })
        }
    }
}
