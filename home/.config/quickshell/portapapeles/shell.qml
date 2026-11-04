//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Historial del portapapeles (cliphist), con el estilo de los paneles.
// Mod+V abre/cierra. Clic o Enter: copia. Supr: borra. Esc: cierra.
// El contenido nunca se pasa como argumento de un comando (solo por stdin);
// las miniaturas de imágenes se guardan en $XDG_RUNTIME_DIR (memoria, se borra al cerrar sesión).
Scope {
    id: root

    // Sin el aviso "Config reloaded": matugen recarga este módulo en cada cambio de fondo.
    // Solo se oculta el de recarga correcta; el de error sigue saliendo.
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }

    property string fuente: "JetBrainsMono Nerd Font"
    property bool abierto: false
    property bool visibleVentana: false
    property var items: []            // { linea, id, texto, imagen, formato, tam }
    property string filtro: ""
    property int sel: 0
    property bool confirmarBorrar: false
    property string aviso: ""
    property string carpetaMini: Quickshell.env("XDG_RUNTIME_DIR") + "/portapapeles"
    property var minis: ({})          // id -> ruta de la miniatura lista

    property var filtrados: {
        var f = root.filtro.toLowerCase()
        return f === "" ? root.items : root.items.filter(i => i.texto.toLowerCase().indexOf(f) >= 0)
    }

    Colors { id: tema }

    function alfa(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function ic(cp) { return String.fromCodePoint(cp) }

    property string salida: ""        // monitor donde se abrió (el enfocado)
    Connections {
        target: Quickshell
        function onScreensChanged() { if (root.abierto) root.cerrar() }
    }
    function abrirEnfocada() { Principal.pedirEnfocada(n => { root.salida = n; root.abrir() }) }

    IpcHandler {
        target: "portapapeles"
        function toggle(): void { root.abierto ? root.cerrar() : root.abrirEnfocada() }
        function abrir(): void { root.abrirEnfocada() }
        function cerrar(): void { root.cerrar() }
        function info(): string {
            return JSON.stringify({ abierto: root.abierto, total: root.items.length, filtrados: root.filtrados.length,
                imagenes: root.items.filter(i => i.imagen).length, minis: Object.keys(root.minis).length, sel: root.sel })
        }
        function buscar(t: string): void { root.filtro = t; campo.text = t }
        function copiar(i: int): string { var it = root.filtrados[i]; if (!it) return "no existe"; root.copiar(it, false); return "copiado " + it.id }
        function pegar(i: int): string { var it = root.filtrados[i]; if (!it) return "no existe"; root.copiar(it, true); return "pegando " + it.id + " en " + root.appFoco }
        function borrar(i: int): string { var it = root.filtrados[i]; if (!it) return "no existe"; root.borrar(it); return "borrado " + it.id }
    }

    function abrir() {
        root.filtro = ""
        campo.text = ""
        root.sel = 0
        root.confirmarBorrar = false
        root.aviso = ""
        cierre.stop()
        root.visibleVentana = true
        root.abierto = true
        root.appFoco = ""
        pFoco.running = true
        pLista.running = true
        campo.forceActiveFocus()
    }

    function cerrar() {
        root.abierto = false
        cierre.restart()
    }

    Timer {
        id: cierre
        interval: 220
        onTriggered: root.visibleVentana = false
    }

    // ===== cliphist =====
    Process {
        id: pLista
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = []
                text.split("\n").forEach(linea => {
                    if (linea === "") return
                    var tab = linea.indexOf("\t")
                    if (tab < 0) return
                    var id = linea.slice(0, tab)
                    var prev = linea.slice(tab + 1)
                    var m = prev.match(/^\[\[ binary data (.+?) (png|jpeg|jpg|gif|bmp|webp) (\d+x\d+) \]\]$/i)
                    l.push({ linea: linea, id: id, texto: m ? "Imagen" : prev,
                             imagen: !!m, formato: m ? m[2].toLowerCase() : "", tam: m ? m[2].toUpperCase() + " · " + m[1] + " · " + m[3] : "" })
                })
                root.items = l
                root.sel = 0
                root.generarMinis()
            }
        }
    }

    // Decodifica las imágenes (las primeras 40) a miniaturas en memoria
    function generarMinis() {
        var ids = root.items.filter(i => i.imagen).slice(0, 40).map(i => i.id + "." + i.formato)
        if (ids.length === 0 || pMinis.running) return
        pMinis.command = ["sh", "-c",
            "umask 077; d=\"$1\"; shift; mkdir -p \"$d\"; for f in \"$@\"; do [ -s \"$d/$f\" ] || cliphist decode \"${f%.*}\" > \"$d/$f\" 2>/dev/null; echo \"$f\"; done",
            "sh", root.carpetaMini].concat(ids)
        pMinis.running = true
    }

    Process {
        id: pMinis
        stdout: StdioCollector {
            onStreamFinished: {
                var m = {}
                text.split("\n").forEach(f => { if (f !== "") m[f.split(".")[0]] = "file://" + root.carpetaMini + "/" + f })
                root.minis = m
            }
        }
    }

    // ===== Copiar y pegar (como Win+V) =====
    // 1) copia con el tipo correcto (imágenes como image/png), 2) cierra la ventana,
    // 3) cuando el foco vuelve a la app, simula Ctrl+V con wtype (Ctrl+Shift+V en terminales).
    // Si no se puede pegar, avisa "Copiado: pulsa Ctrl+V".
    property string appFoco: ""          // app_id de la ventana que tenía el foco al abrir
    property bool pegarDespues: true
    readonly property var terminales: ["alacritty", "kitty", "foot", "footclient", "org.wezfurlong.wezterm",
        "com.mitchellh.ghostty", "org.kde.konsole", "konsole", "xterm", "org.gnome.ptyxis", "org.gnome.console"]

    Process {
        id: pFoco
        command: ["niri", "msg", "-j", "focused-window"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { var v = JSON.parse(text); root.appFoco = v ? (v.app_id || "?") : "" } catch (e) { root.appFoco = "" }
            }
        }
    }

    function tipoMime(it) {
        if (!it.imagen) return ""
        return "image/" + (it.formato === "jpg" ? "jpeg" : it.formato)
    }

    function copiar(it, pegar) {
        if (!it) return
        root.pegarDespues = pegar !== false
        var tipo = root.tipoMime(it)
        pCopiar.command = ["sh", "-c",
            tipo !== "" ? "cliphist decode \"$1\" | wl-copy --type \"$2\"" : "cliphist decode \"$1\" | wl-copy",
            "sh", it.id, tipo]
        pCopiar.running = true
        root.cerrar()
    }

    Process {
        id: pCopiar
        onExited: code => {
            if (code !== 0) { root.avisar("No se pudo copiar"); return }
            if (!root.pegarDespues) { root.avisar("Copiado"); return }
            if (root.appFoco === "") { root.avisar("Copiado: pulsa Ctrl+V"); return }
            pegado.restart()       // espera a que la ventana se cierre y el foco vuelva
        }
    }

    Timer {
        id: pegado
        interval: 320
        onTriggered: {
            var terminal = root.terminales.indexOf(root.appFoco.toLowerCase()) >= 0
            var teclas = terminal ? ["-M", "ctrl", "-M", "shift", "-k", "v", "-m", "shift", "-m", "ctrl"]
                                  : ["-M", "ctrl", "-k", "v", "-m", "ctrl"]
            pPegar.terminal = terminal
            pPegar.command = ["sh", "-c", "command -v wtype >/dev/null || exit 127; exec wtype \"$@\"", "sh"].concat(teclas)
            pPegar.running = true
        }
    }

    Process {
        id: pPegar
        property bool terminal: false
        onExited: code => {
            if (code !== 0) root.avisar(pPegar.terminal ? "Copiado: pulsa Ctrl+Shift+V" : "Copiado: pulsa Ctrl+V")
        }
    }

    function avisar(texto) {
        Quickshell.execDetached(["notify-send", "-a", "Portapapeles", "-i", "edit-paste", "-t", "2500", texto])
    }

    // Borrar una entrada: cliphist delete lee la línea por stdin
    function borrar(it) {
        if (!it || pBorrar.running) return
        pBorrar.linea = it.linea
        pBorrar.running = true
        root.items = root.items.filter(x => x.id !== it.id)
        root.sel = Math.min(root.sel, Math.max(0, root.filtrados.length - 1))
    }

    Process {
        id: pBorrar
        property string linea: ""
        command: ["cliphist", "delete"]
        stdinEnabled: true
        onStarted: {
            pBorrar.write(pBorrar.linea + "\n")
            pBorrar.linea = ""
            pBorrar.stdinEnabled = false
        }
        onExited: pBorrar.stdinEnabled = true
    }

    function borrarTodo() {
        root.confirmarBorrar = false
        pWipe.running = true
    }

    Process {
        id: pWipe
        command: ["sh", "-c", "cliphist wipe && rm -rf \"$1\"", "sh", root.carpetaMini]
        onExited: { root.items = []; root.minis = ({}); root.aviso = "Historial borrado" }
    }

    // ===== Ventana =====
    PanelWindow {
        screen: Principal.porNombre(root.salida) || Principal.pantalla
        visible: Principal.lista && (root.visibleVentana)
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "portapapeles"
        WlrLayershell.keyboardFocus: root.abierto ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // Fondo oscurecido: clic fuera cierra
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: root.abierto ? 0.35 : 0
            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.cerrar()
            }
        }

        Rectangle {
            id: caja
            anchors.centerIn: parent
            width: 560
            height: Math.min(640, parent.height - 120)
            radius: 24
            color: root.alfa(tema.surface, 0.96)
            border.color: root.alfa(tema.primary, 0.5)
            border.width: 1.5
            scale: root.abierto ? 1 : 0.88
            opacity: root.abierto ? 1 : 0
            Behavior on scale {
                NumberAnimation { duration: root.abierto ? 320 : 200; easing.type: root.abierto ? Easing.OutBack : Easing.InCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 180 }
            }

            MouseArea { anchors.fill: parent }   // no cerrar al hacer clic dentro

            Column {
                id: cabeza
                x: 18
                y: 18
                width: parent.width - 36
                spacing: 12

                // Título + Borrar todo
                Item {
                    width: parent.width
                    height: 32
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Text {
                            text: root.ic(0xF014D)
                            font.family: root.fuente
                            font.pixelSize: 20
                            color: tema.primary
                        }
                        Text {
                            text: "Portapapeles"
                            font.family: root.fuente
                            font.pixelSize: 16
                            font.bold: true
                            color: tema.surfaceText
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !root.confirmarBorrar   // deja sitio a la pregunta
                            text: root.items.length > 0 ? root.items.length + " elementos" : ""
                            font.family: root.fuente
                            font.pixelSize: 11
                            color: root.alfa(tema.surfaceText, 0.55)
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Text {
                            visible: root.confirmarBorrar
                            anchors.verticalCenter: parent.verticalCenter
                            text: "¿Borrar todo el historial?"
                            font.family: root.fuente
                            font.pixelSize: 11
                            color: tema.surfaceText
                        }
                        Repeater {
                            model: root.confirmarBorrar ? [ { id: "no", t: "Cancelar" }, { id: "si", t: "Borrar" } ]
                                : (root.items.length > 0 ? [ { id: "pedir", t: "Borrar todo" } ] : [])
                            delegate: Rectangle {
                                id: bb
                                required property var modelData
                                width: tb.implicitWidth + 22
                                height: 28
                                radius: 10
                                color: bb.modelData.id === "si" ? (mb.containsMouse ? "#ff6b6b" : "#e05555")
                                    : root.alfa(tema.primary, mb.containsMouse ? 0.25 : 0.12)
                                Text {
                                    id: tb
                                    anchors.centerIn: parent
                                    text: bb.modelData.t
                                    font.family: root.fuente
                                    font.pixelSize: 11
                                    font.bold: bb.modelData.id === "si"
                                    color: bb.modelData.id === "si" ? "white" : tema.surfaceText
                                }
                                MouseArea {
                                    id: mb
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (bb.modelData.id === "pedir") root.confirmarBorrar = true
                                        else if (bb.modelData.id === "si") root.borrarTodo()
                                        else root.confirmarBorrar = false
                                    }
                                }
                            }
                        }
                    }
                }

                // Buscador
                Rectangle {
                    width: parent.width
                    height: 42
                    radius: 14
                    color: root.alfa(tema.primary, 0.08)
                    border.color: campo.activeFocus ? tema.primary : root.alfa(tema.primary, 0.35)
                    border.width: 1.5
                    Text {
                        id: lupa
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.ic(0xF0349)
                        font.family: root.fuente
                        font.pixelSize: 16
                        color: tema.primary
                    }
                    TextInput {
                        id: campo
                        anchors.left: lupa.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: root.fuente
                        font.pixelSize: 13
                        color: tema.surfaceText
                        selectionColor: tema.primary
                        clip: true
                        onTextChanged: { root.filtro = text; root.sel = 0 }
                        Keys.onEscapePressed: root.cerrar()
                        Keys.onUpPressed: { root.sel = Math.max(0, root.sel - 1); lista.positionViewAtIndex(root.sel, ListView.Contain) }
                        Keys.onDownPressed: { root.sel = Math.min(root.filtrados.length - 1, root.sel + 1); lista.positionViewAtIndex(root.sel, ListView.Contain) }
                        Keys.onReturnPressed: e => root.copiar(root.filtrados[root.sel], !(e.modifiers & Qt.ShiftModifier))
                        Keys.onEnterPressed: e => root.copiar(root.filtrados[root.sel], !(e.modifiers & Qt.ShiftModifier))
                        Keys.onDeletePressed: root.borrar(root.filtrados[root.sel])
                        Text {
                            visible: campo.text === ""
                            text: "Buscar…   Enter pegar · Shift+Enter solo copiar · Supr borrar"
                            font: campo.font
                            color: root.alfa(tema.surfaceText, 0.4)
                        }
                    }
                }
            }

            // Lista
            ListView {
                id: lista
                anchors.top: cabeza.bottom
                anchors.topMargin: 12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                x: 18
                width: parent.width - 36
                clip: true
                spacing: 6
                model: root.filtrados
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: fila
                    required property var modelData
                    required property int index
                    property bool elegida: root.sel === fila.index
                    width: lista.width
                    height: fila.modelData.imagen ? 92 : Math.min(76, Math.max(46, txt.implicitHeight + 24))
                    radius: 14
                    color: fila.elegida ? root.alfa(tema.primary, 0.22) : root.alfa(tema.primary, maFila.containsMouse ? 0.12 : 0.05)
                    border.color: fila.elegida ? root.alfa(tema.primary, 0.6) : "transparent"
                    border.width: 1.5
                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    MouseArea {
                        id: maFila
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.sel = fila.index
                        onClicked: m => root.copiar(fila.modelData, !(m.modifiers & Qt.ShiftModifier))
                    }

                    // Imagen
                    Rectangle {
                        id: marco
                        visible: fila.modelData.imagen
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 120
                        height: 72
                        radius: 10
                        color: root.alfa(tema.surfaceText, 0.06)
                        Image {
                            anchors.fill: parent
                            anchors.margins: 3
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize.width: 240
                            source: fila.modelData.imagen ? (root.minis[fila.modelData.id] || "") : ""
                        }
                    }

                    Text {
                        id: txt
                        anchors.left: fila.modelData.imagen ? marco.right : parent.left
                        anchors.leftMargin: 14
                        anchors.right: btnX.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: fila.modelData.imagen ? fila.modelData.texto + "\n" + fila.modelData.tam : fila.modelData.texto
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: fila.modelData.imagen ? 2 : 3
                        elide: Text.ElideRight
                        font.family: root.fuente
                        font.pixelSize: 12
                        color: tema.surfaceText
                    }

                    // Borrar esta entrada
                    Text {
                        id: btnX
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.ic(0xF0156)
                        font.family: root.fuente
                        font.pixelSize: 15
                        color: "#ff8a80"
                        opacity: maFila.containsMouse || maX.containsMouse || fila.elegida ? 1 : 0
                        MouseArea {
                            id: maX
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.borrar(fila.modelData)
                        }
                    }
                }

                // Vacío
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    visible: root.filtrados.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    text: root.items.length === 0 ? (pLista.running ? "Cargando…" : "Aún no hay nada.\nCopia algo (Ctrl+C) y aparecerá aquí.")
                        : "Nada coincide con «" + root.filtro + "»"
                    font.family: root.fuente
                    font.pixelSize: 13
                    color: root.alfa(tema.surfaceText, 0.55)
                }
            }
        }
    }
}
