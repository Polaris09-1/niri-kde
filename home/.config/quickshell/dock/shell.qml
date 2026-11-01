//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

Scope {
    id: root
    property bool mostrar: false

    // ===== Ajustes (cámbialos a tu gusto) =====
    property int base: 26          // tamaño del icono en reposo (px)
    property int separacion: 8    // espacio entre iconos (px)
    property real aumento: 0.9     // cuánto crece el icono bajo el mouse (0.9 = +90%)
    property real alcance: 45      // qué tan ancha es la "ola" (px)

    property string terminal: "alacritty"

    // Apps fijadas (por nombre, como salen en el cajón); se guardan en fijadas.json
    property var fijadasIniciales: ["Firefox", "Alacritty", "Dolphin", "@sistema", "@audio"]

    FileView {
        id: archivoFijadas
        path: Quickshell.shellDir + "/fijadas.json"
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter() }
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: guardado
            property list<string> fijadas: root.fijadasIniciales
            onFijadasChanged: recalcular.restart()
        }
    }

    // Ventanas abiertas (niri msg -j windows)
    property var ventanas: []

    // Fijadas + apps abiertas sin fijar + botón que abre el cajón
    property var elementos: []
    property string firma: ""

    function entradaPorAppId(id) {
        if (!id) return null
        var l = id.toLowerCase()
        var apps = DesktopEntries.applications.values
        return apps.find(a => a.id.toLowerCase() === l)
            || apps.find(a => (a.startupClass || "").toLowerCase() === l)
            || apps.find(a => a.id.toLowerCase().endsWith("." + l))
            || apps.find(a => a.name.toLowerCase() === l)
            || (DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(id) : null)
            || null
    }

    function reconstruir() {
        var apps = DesktopEntries.applications.values
        var lista = []
        var porClave = {}
        guardado.fijadas.forEach(n => {
            // Accesos especiales a los paneles de la barra: "@sistema", "@audio", "@wifi"...
            if (n.startsWith("@")) {
                var esp = root.especiales[n]
                if (esp && !porClave[n]) {
                    var de = { clave: n, name: esp.nombre, icon: esp.icono, especial: n.slice(1), ventanas: [], enfocada: false, fijada: true }
                    porClave[n] = de
                    lista.push(de)
                }
                return
            }
            var e = apps.find(a => a.name === n)
            if (!e || porClave["e:" + e.id]) return
            var d = { clave: "e:" + e.id, name: e.name, icon: e.icon, entrada: e, ventanas: [], enfocada: false, fijada: true }
            porClave[d.clave] = d
            lista.push(d)
        })
        root.ventanas.slice().sort((a, b) => a.id - b.id).forEach(v => {
            var e = root.entradaPorAppId(v.app_id)
            var k = e ? "e:" + e.id : "a:" + (v.app_id || "?")
            var d = porClave[k]
            if (!d) {
                d = { clave: k, name: e ? e.name : (v.app_id || "?"), icon: e ? e.icon : (v.app_id || "").toLowerCase(),
                      entrada: e, ventanas: [], enfocada: false, fijada: false }
                porClave[k] = d
                lista.push(d)
            }
            d.ventanas.push(v.id)
            if (v.is_focused) d.enfocada = true
        })
        lista.push({ clave: "cajon", name: "Aplicaciones", icon: "view-app-grid", cajon: true, ventanas: [], enfocada: false })
        // Solo reemplaza la lista si cambió algo (evita recrear iconos a cada evento)
        var f = lista.map(d => d.clave + ":" + d.ventanas.join(",") + (d.enfocada ? "*" : "")).join("|")
        if (f !== root.firma) {
            root.firma = f
            root.elementos = lista
        }
    }

    Timer {
        id: recalcular
        interval: 30
        onTriggered: root.reconstruir()
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { recalcular.restart() }
    }

    // ===== niri: escucha eventos y vuelve a pedir las ventanas =====
    Process {
        id: eventos
        command: ["niri", "msg", "-j", "event-stream"]
        running: true
        stdout: SplitParser {
            onRead: data => refresco.restart()
        }
        onExited: reinicioEventos.start()
    }

    Timer {
        id: reinicioEventos
        interval: 2000
        onTriggered: eventos.running = true
    }

    Timer {
        id: refresco
        interval: 40
        onTriggered: pVentanas.running = true
    }

    Process {
        id: pVentanas
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.ventanas = JSON.parse(text) } catch (e) {}
                recalcular.restart()
            }
        }
    }

    Component.onCompleted: refresco.start()

    // Abre una app; las de terminal (btop, etc.) dentro de la terminal
    function lanzar(e) {
        if (!e) return
        // --class hace que la ventana se asocie al icono de la app (no al de la terminal)
        if (e.runInTerminal) Quickshell.execDetached([root.terminal, "--class", e.id, "-e"].concat(e.command))
        else e.execute()
    }

    // Clic: cajón, enfocar (o pasar a la siguiente ventana de la app) o abrir
    // Accesos especiales disponibles (abren una página del panel de la barra)
    readonly property var especiales: ({
        "@sistema": { nombre: "Sistema", icono: "utilities-system-monitor" },
        "@audio": { nombre: "Audio", icono: "multimedia-volume-control" },
        "@wifi": { nombre: "Wi-Fi", icono: "network-wireless" },
        "@bluetooth": { nombre: "Bluetooth", icono: "bluetooth" },
        "@energia": { nombre: "Energía", icono: "system-shutdown" }
    })

    function abrirPagina(p) {
        Quickshell.execDetached(["qs", "-c", "hola", "ipc", "call", "hola", "pagina", p])
    }

    // ===== Menú de clic derecho =====
    property var menu: null           // elemento del dock con el menú abierto
    property real menuX: 0            // centro del icono (coords. de "area")
    property string confirmarCierre: ""

    function abrirMenu(d, item) {
        var pt = item.mapToItem(area, item.width / 2, 0)
        root.menuX = pt.x
        root.confirmarCierre = ""
        root.menu = d
    }

    function cerrarMenu() { root.menu = null }

    function opcionesMenu(d) {
        if (!d) return []
        var o = []
        if (d.entrada) o.push({ id: "nueva", texto: "Nueva ventana", icono: 0xF0415 })
        if (d.ventanas.length > 0) o.push({ id: "cerrar", texto: d.ventanas.length > 1 ? "Cerrar ventanas (" + d.ventanas.length + ")" : "Cerrar ventana", icono: 0xF0156, peligro: true })
        if (!d.cajon) {
            if (d.fijada) o.push({ id: "desfijar", texto: "Quitar del dock", icono: 0xF0931 })
            else if (d.entrada) o.push({ id: "fijar", texto: "Fijar en el dock", icono: 0xF0403 })
        }
        return o
    }

    function elegirOpcion(d, id) {
        if (id === "nueva") { root.lanzar(d.entrada); root.cerrarMenu() }
        else if (id === "cerrar") {
            // Varias ventanas: pide confirmación antes de cerrarlas todas
            if (d.ventanas.length > 1 && root.confirmarCierre !== d.clave) { root.confirmarCierre = d.clave; return }
            d.ventanas.forEach(id => Quickshell.execDetached(["niri", "msg", "action", "close-window", "--id", String(id)]))
            root.cerrarMenu()
        }
        else if (id === "desfijar") {
            var quitar = d.especial ? d.clave : d.name
            guardado.fijadas = guardado.fijadas.filter(n => n !== quitar)
            root.cerrarMenu()
        }
        else if (id === "fijar") {
            if (guardado.fijadas.indexOf(d.name) < 0) guardado.fijadas = guardado.fijadas.concat([d.name])
            root.cerrarMenu()
        }
    }

    function activar(d) {
        if (d.cajon) { abrirCajon.running = true; return "cajón" }
        if (d.especial) { root.abrirPagina(d.especial); return "panel " + d.especial }
        if (d.ventanas.length === 0) { root.lanzar(d.entrada); return "abrir " + d.name }
        var actual = root.ventanas.find(v => v.is_focused)
        var i = actual ? d.ventanas.indexOf(actual.id) : -1
        var id = d.ventanas[(i + 1) % d.ventanas.length]
        Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(id)])
        return "enfocar ventana " + id
    }

    // ===== IPC: qs -c dock ipc call dock <función> =====
    IpcHandler {
        target: "dock"
        function mostrar(): void { root.abrir(); pruebaOcultar.restart() }
        // Para el OSD (2026-11-01): si el dock está a la vista, el OSD sube para no taparlo
        function estaVisible(): string { return root.mostrar ? "si" : "no" }
        function info(): string {
            return JSON.stringify(root.elementos.map(d => ({ nombre: d.name, ventanas: d.ventanas.length, enfocada: d.enfocada })))
        }
        function clic(nombre: string): string {
            var d = root.elementos.find(x => x.name === nombre)
            return d ? root.activar(d) : "no está en el dock"
        }
        // Prueba del menú: abre el de una app (centrado) y devuelve sus opciones
        function menu(nombre: string): string {
            var d = root.elementos.find(x => x.name === nombre)
            if (!d) return "no está en el dock"
            root.abrir()
            pruebaOcultar.restart()
            var i = root.elementos.indexOf(d)
            root.menuX = (area.width - root.anchoReposo) / 2 + i * (root.base + root.separacion) + root.base / 2
            root.menu = d
            return root.opcionesMenu(d).map(o => o.texto).join(", ")
        }
        function opcion(nombre: string, id: string): string {
            var d = root.elementos.find(x => x.name === nombre)
            if (!d) return "no está en el dock"
            root.elegirOpcion(d, id)
            return JSON.stringify(guardado.fijadas)
        }
    }

    Timer {
        id: pruebaOcultar
        interval: 3000
        onTriggered: ocultar.restart()
    }

    // Ancho del dock en reposo
    property real anchoReposo: elementos.length * base + (elementos.length - 1) * separacion

    // Posición X del mouse sobre el dock (-1000 = fuera)
    property real ratonX: (hh.hovered && hh.point.position.y > area.height - 80) ? hh.point.position.x : -1000

    // Tamaño de cada icono según su distancia al mouse (curva de campana)
    function zoomPara(i) {
        var centro = (area.width - root.anchoReposo) / 2 + i * (root.base + root.separacion) + root.base / 2
        var d = root.ratonX - centro
        return 1 + root.aumento * Math.exp(-(d * d) / (2 * root.alcance * root.alcance))
    }

    Colors { id: tema }

    Process {
        id: abrirCajon
        command: ["qs", "-c", "cajon", "ipc", "call", "cajon", "toggle"]
    }

    function abrir() {
        ocultar.stop()
        esconder.stop()
        ventana.visible = true
        root.mostrar = true
    }

    // Espera un poco antes de esconder
    Timer {
        id: ocultar
        interval: 400
        onTriggered: {
            root.cerrarMenu()
            root.mostrar = false
            esconder.restart()
        }
    }

    // Oculta la ventana cuando termina la animación de bajada
    Timer {
        id: esconder
        interval: 350
        onTriggered: ventana.visible = false
    }

    // Oscurece el resto de la pantalla (no bloquea clics)
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Top
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: root.mostrar ? 0.35 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }
    }

    // Sensor invisible en el borde inferior
    PanelWindow {
        anchors {
            bottom: true
            left: true
            right: true
        }
        implicitHeight: 4
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.abrir()
            onExited: ocultar.restart()
        }
    }

    // El dock
    PanelWindow {
        id: ventana
        visible: false
        anchors.bottom: true
        implicitWidth: root.anchoReposo + 400
        // Más alto mientras el menú está abierto, para que quepa sobre el icono
        implicitHeight: root.menu ? 300 : 140
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay

        Item {
            id: area
            anchors.fill: parent

            HoverHandler {
                id: hh
                onHoveredChanged: hovered ? root.abrir() : ocultar.restart()
            }

            // Todo lo que sube y baja con rebote
            Item {
                anchors.fill: parent
                opacity: root.mostrar ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 250 }
                }
                transform: Translate {
                    y: root.mostrar ? 0 : 100
                    Behavior on y {
                        NumberAnimation { duration: 400; easing.type: Easing.OutBack }
                    }
                }

                // Clic en una zona vacía del dock: cierra el menú
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: root.cerrarMenu()
                }

                // ---------- Menú de clic derecho (crece desde el icono) ----------
                Rectangle {
                    id: menuCaja
                    z: 10
                    property var d: null
                    property var ops: root.opcionesMenu(menuCaja.d)
                    property real escala: root.menu ? 1 : 0
                    Behavior on escala {
                        NumberAnimation { duration: root.menu ? 320 : 160; easing.type: root.menu ? Easing.OutBack : Easing.InCubic }
                    }
                    Connections {
                        target: root
                        function onMenuChanged() { if (root.menu) menuCaja.d = root.menu }
                    }

                    visible: escala > 0.01
                    scale: escala
                    opacity: Math.min(1, escala)
                    transformOrigin: Item.Bottom
                    width: 210
                    height: colMenu.implicitHeight + 16
                    x: Math.max(8, Math.min(parent.width - width - 8, root.menuX - width / 2))
                    y: fondo.y - height - 26
                    radius: 16
                    color: Qt.rgba(tema.surface.r, tema.surface.g, tema.surface.b, 0.96)
                    border.color: Qt.rgba(tema.primary.r, tema.primary.g, tema.primary.b, 0.6)
                    border.width: 1.5

                    Column {
                        id: colMenu
                        x: 8
                        y: 8
                        width: parent.width - 16
                        spacing: 2

                        Text {
                            width: parent.width
                            leftPadding: 8
                            bottomPadding: 4
                            elide: Text.ElideRight
                            text: menuCaja.d ? menuCaja.d.name : ""
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.bold: true
                            color: Qt.rgba(tema.primary.r, tema.primary.g, tema.primary.b, 0.85)
                        }

                        Repeater {
                            model: menuCaja.ops
                            delegate: Rectangle {
                                id: op
                                required property var modelData
                                property bool confirmando: op.modelData.id === "cerrar" && menuCaja.d && root.confirmarCierre === menuCaja.d.clave
                                width: colMenu.width
                                height: 34
                                radius: 10
                                color: op.confirmando ? Qt.rgba(1, 0.33, 0.33, 0.25)
                                    : Qt.rgba(tema.primary.r, tema.primary.g, tema.primary.b, maOp.containsMouse ? 0.18 : 0)
                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }
                                Row {
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10
                                    Text {
                                        text: String.fromCodePoint(op.modelData.icono)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 14
                                        color: op.modelData.peligro ? "#ff8a80" : tema.primary
                                    }
                                    Text {
                                        text: op.confirmando ? "¿Seguro? Toca otra vez" : op.modelData.texto
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                        color: tema.surfaceText
                                    }
                                }
                                MouseArea {
                                    id: maOp
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.elegirOpcion(menuCaja.d, op.modelData.id)
                                }
                            }
                        }
                    }
                }

                // Fondo que se estira con la ola
                Rectangle {
                    id: fondo
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: fila.width + 20
                    height: root.base + 16
                    radius: 16
                    color: Qt.rgba(tema.surface.r, tema.surface.g, tema.surface.b, 0.85)
                    border.color: tema.primary
                    border.width: 1.5
                }

                Row {
                    id: fila
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: fondo.bottom
                    anchors.bottomMargin: 8
                    spacing: root.separacion

                    Repeater {
                        model: root.elementos

                        delegate: Item {
                            id: ic
                            required property var modelData
                            required property int index

                            property real zoom: root.zoomPara(ic.index)
                            property real cerca: (zoom - 1) / root.aumento   // 0 = lejos, 1 = encima

                            width: root.base * zoom
                            height: root.base * (1 + root.aumento)

                            Image {
                                id: img
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                height: parent.width
                                sourceSize.width: 128
                                sourceSize.height: 128
                                source: Quickshell.iconPath(ic.modelData.icon, "application-x-executable")
                                transform: Translate { id: salto }

                                // Teñido con tu color; se quita y brilla al acercarte
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 0.8 * (1 - ic.cerca)
                                    colorizationColor: tema.primary
                                    shadowEnabled: true
                                    shadowColor: tema.primary
                                    shadowBlur: 1.0
                                    shadowOpacity: 0.9 * ic.cerca
                                }
                            }

                            // Etiqueta flotante con el nombre
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: img.top
                                anchors.bottomMargin: 8
                                width: etiqueta.width + 18
                                height: 24
                                radius: 12
                                color: tema.primary
                                opacity: ic.cerca > 0.9 && !root.menu ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation { duration: 150 }
                                }

                                Text {
                                    id: etiqueta
                                    anchors.centerIn: parent
                                    text: ic.modelData.name
                                    color: tema.primaryText
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            // Puntito: app abierta (largo si tiene el foco)
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom
                                anchors.topMargin: 2
                                visible: ic.modelData.ventanas.length > 0
                                width: ic.modelData.enfocada ? 14 : 5
                                height: 5
                                radius: 2.5
                                color: tema.primary
                                opacity: ic.modelData.enfocada ? 1 : 0.6
                                Behavior on width {
                                    NumberAnimation { duration: 250; easing.type: Easing.OutBack }
                                }
                            }

                            // Izquierdo: enfocar/abrir · Medio: nueva ventana · Derecho: menú
                            MouseArea {
                                anchors.fill: img
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: m => {
                                    if (m.button === Qt.RightButton) {
                                        if (root.menu && root.menu.clave === ic.modelData.clave) root.cerrarMenu()
                                        else root.abrirMenu(ic.modelData, img)
                                        return
                                    }
                                    root.cerrarMenu()
                                    rebote.start()
                                    if (m.button === Qt.MiddleButton && ic.modelData.entrada) root.lanzar(ic.modelData.entrada)
                                    else root.activar(ic.modelData)
                                }
                            }

                            // Rebote al hacer clic
                            SequentialAnimation {
                                id: rebote
                                NumberAnimation { target: salto; property: "y"; to: -16; duration: 150; easing.type: Easing.OutQuad }
                                NumberAnimation { target: salto; property: "y"; to: 0; duration: 400; easing.type: Easing.OutBounce }
                            }
                        }
                    }
                }
            }
        }
    }
}
