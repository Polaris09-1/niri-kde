//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel

Scope {
    id: root

    // ===== Ajustes =====
    property string carpeta: Quickshell.env("HOME") + "/Desktop"
    property string fuente: "JetBrainsMono Nerd Font"
    property int celda: 104       // ancho de cada celda
    property int altoCelda: 112   // alto: icono + nombre en 2 líneas
    property int columnas: 2

    Colors { id: tema }

    // Lista los archivos de la carpeta y se actualiza sola
    FolderListModel {
        id: archivos
        folder: "file://" + root.carpeta
        showDirsFirst: true
        showHidden: false
        sortField: FolderListModel.Name
    }

    // Si es un acceso .desktop, busca la app para sacar su nombre e icono
    function entradaDe(nombre) {
        if (!nombre.endsWith(".desktop")) return null
        var id = nombre.slice(0, -8)
        return DesktopEntries.applications.values.find(a => a.id === id) || null
    }

    // Icono según el tipo de archivo
    function iconoArchivo(nombre, esCarpeta) {
        if (esCarpeta) return "folder"
        var ext = nombre.split(".").pop().toLowerCase()
        var mapa = {
            "pdf": "application-pdf",
            "png": "image-x-generic", "jpg": "image-x-generic", "jpeg": "image-x-generic", "webp": "image-x-generic",
            "txt": "text-x-generic", "md": "text-x-generic",
            "zip": "package-x-generic", "rar": "package-x-generic", "7z": "package-x-generic",
            "mp4": "video-x-generic", "mkv": "video-x-generic", "mp3": "audio-x-generic",
            "docx": "x-office-document", "doc": "x-office-document",
            "xlsx": "x-office-spreadsheet", "pptx": "x-office-presentation",
            "py": "text-x-python", "sh": "text-x-script"
        }
        return mapa[ext] || "text-x-generic"
    }

    // ===== Menú de clic derecho =====
    property var menu: null          // { fileName, filePath, entrada, nombre }
    property real menuY: 0
    property bool confirmarQuitar: false

    function abrirMenu(el, y) {
        root.confirmarQuitar = false
        root.menuY = y
        root.menu = el
    }

    function cerrarMenu() {
        root.menu = null
        root.confirmarQuitar = false
    }

    function abrir(el) {
        if (el.entrada) el.entrada.execute()
        else Quickshell.execDetached(["xdg-open", el.filePath])
        root.cerrarMenu()
    }

    function opciones(el) {
        if (!el) return []
        if (el.fileName.endsWith(".desktop"))
            return [ { id: "abrir", texto: "Abrir", icono: 0xF0415 },
                     { id: "quitar", texto: "Quitar del escritorio", icono: 0xF01B4, peligro: true } ]
        return [ { id: "abrir", texto: "Abrir", icono: 0xF0415 },
                 { id: "carpeta", texto: "Mostrar en carpeta", icono: 0xF024B } ]
    }

    function elegir(el, id) {
        if (id === "abrir") root.abrir(el)
        else if (id === "carpeta") { Quickshell.execDetached(["dolphin", "--select", el.filePath]); root.cerrarMenu() }
        else if (id === "quitar") root.confirmarQuitar = true
    }

    // Solo borra el acceso directo (.desktop) del escritorio; la app no se desinstala
    function quitarAcceso(el) {
        if (el && el.fileName.endsWith(".desktop") && el.filePath.startsWith(root.carpeta + "/"))
            Quickshell.execDetached(["rm", "--", el.filePath])
        root.cerrarMenu()
    }

    PanelWindow {
        anchors {
            top: true
            bottom: true
            left: true
        }
        // Empieza debajo de la barra superior (respeta su zona reservada) con margen
        margins {
            top: 14
            bottom: 24
            left: 14
        }
        implicitWidth: root.celda * root.columnas + 8
        exclusionMode: ExclusionMode.Normal   // se coloca bajo la barra; no reserva espacio propio
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "escritorio"

        GridView {
            id: grilla
            anchors.fill: parent
            flow: GridView.FlowTopToBottom
            cellWidth: root.celda
            cellHeight: root.altoCelda
            interactive: false
            model: archivos

            delegate: Item {
                id: el
                required property string fileName
                required property string filePath
                required property bool fileIsDir
                property var entrada: root.entradaDe(el.fileName)

                width: grilla.cellWidth
                height: grilla.cellHeight

                // Resalte suave al pasar el mouse (todo el icono + nombre)
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: 16
                    color: Qt.rgba(tema.primary.r, tema.primary.g, tema.primary.b, zona.pressed ? 0.3 : 0.16)
                    border.color: Qt.rgba(tema.primary.r, tema.primary.g, tema.primary.b, 0.45)
                    border.width: 1
                    opacity: zona.containsMouse || (root.menu && root.menu.filePath === el.filePath) ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                }

                Image {
                    id: icono
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 10
                    width: 52
                    height: 52
                    sourceSize.width: 104
                    sourceSize.height: 104
                    source: Quickshell.iconPath(el.entrada ? el.entrada.icon : root.iconoArchivo(el.fileName, el.fileIsDir), "text-x-generic")
                    scale: zona.containsMouse ? 1.08 : 1
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                    }
                }

                // Nombre sobre una pastilla translúcida: se lee sobre cualquier fondo
                Rectangle {
                    id: pastilla
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: icono.bottom
                    anchors.topMargin: 7
                    width: Math.min(nombre.implicitWidth, root.celda - 14) + 14
                    height: nombre.height + 6
                    radius: 9
                    color: Qt.rgba(tema.surface.r, tema.surface.g, tema.surface.b, zona.containsMouse ? 0.85 : 0.62)
                    border.color: Qt.rgba(tema.primary.r, tema.primary.g, tema.primary.b, zona.containsMouse ? 0.55 : 0.18)
                    border.width: 1
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }

                    Text {
                        id: nombre
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, root.celda - 14)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: el.entrada ? el.entrada.name : el.fileName
                        font.family: root.fuente
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: tema.surfaceText
                    }
                }

                MouseArea {
                    id: zona
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor

                    // Doble clic: abrir
                    onDoubleClicked: mouse => {
                        if (mouse.button !== Qt.LeftButton) return
                        if (el.entrada) el.entrada.execute()
                        else Quickshell.execDetached(["xdg-open", el.filePath])
                    }

                    // Clic izquierdo: cierra el menú · Clic derecho: abre el menú de este icono
                    onClicked: mouse => {
                        if (mouse.button !== Qt.RightButton) { root.cerrarMenu(); return }
                        var pt = el.mapToItem(capaMenu, 0, el.height - 8)
                        root.abrirMenu({ fileName: el.fileName, filePath: el.filePath, entrada: el.entrada,
                                         nombre: el.entrada ? el.entrada.name : el.fileName }, pt.y)
                    }
                }
            }
        }

        // ---------- Menú (crece desde el icono) ----------
        Item {
            id: capaMenu
            anchors.fill: parent

            // Si el mouse sale del escritorio, el menú se cierra solo
            HoverHandler {
                onHoveredChanged: hovered ? cierreMenu.stop() : cierreMenu.restart()
            }
            Timer {
                id: cierreMenu
                interval: 900
                onTriggered: root.cerrarMenu()
            }

            Rectangle {
                id: cajaMenu
                property var el: null
                property real escala: root.menu ? 1 : 0
                Behavior on escala {
                    NumberAnimation { duration: root.menu ? 300 : 150; easing.type: root.menu ? Easing.OutBack : Easing.InCubic }
                }
                Connections {
                    target: root
                    function onMenuChanged() { if (root.menu) cajaMenu.el = root.menu }
                }

                visible: escala > 0.01
                scale: escala
                opacity: Math.min(1, escala)
                transformOrigin: Item.Top
                x: 4
                width: parent.width - 8
                height: colMenu.implicitHeight + 16
                y: Math.min(parent.height - height - 4, root.menuY)
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
                        leftPadding: 6
                        bottomPadding: 4
                        elide: Text.ElideRight
                        text: cajaMenu.el ? cajaMenu.el.nombre : ""
                        font.family: root.fuente
                        font.pixelSize: 11
                        font.bold: true
                        color: Qt.rgba(tema.primary.r, tema.primary.g, tema.primary.b, 0.85)
                    }

                    // Opciones normales
                    Repeater {
                        model: root.confirmarQuitar ? [] : root.opciones(cajaMenu.el)
                        delegate: Rectangle {
                            id: op
                            required property var modelData
                            width: colMenu.width
                            height: 32
                            radius: 10
                            color: Qt.rgba(tema.primary.r, tema.primary.g, tema.primary.b, maOp.containsMouse ? 0.18 : 0)
                            Row {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Text {
                                    text: String.fromCodePoint(op.modelData.icono)
                                    font.family: root.fuente
                                    font.pixelSize: 13
                                    color: op.modelData.peligro ? "#ff8a80" : tema.primary
                                }
                                Text {
                                    text: op.modelData.texto
                                    font.family: root.fuente
                                    font.pixelSize: 11
                                    color: tema.surfaceText
                                }
                            }
                            MouseArea {
                                id: maOp
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.elegir(cajaMenu.el, op.modelData.id)
                            }
                        }
                    }

                    // Confirmación para quitar el acceso
                    Text {
                        visible: root.confirmarQuitar
                        width: parent.width
                        leftPadding: 6
                        rightPadding: 6
                        wrapMode: Text.Wrap
                        text: "¿Quitar este acceso del escritorio? La app no se desinstala."
                        font.family: root.fuente
                        font.pixelSize: 11
                        color: tema.surfaceText
                    }
                    Row {
                        visible: root.confirmarQuitar
                        topPadding: 6
                        spacing: 6
                        x: 4
                        Repeater {
                            model: [ { id: "no", texto: "Cancelar" }, { id: "si", texto: "Quitar" } ]
                            delegate: Rectangle {
                                id: bc
                                required property var modelData
                                width: (colMenu.width - 14) / 2
                                height: 30
                                radius: 10
                                color: bc.modelData.id === "si" ? (maBc.containsMouse ? "#ff6b6b" : "#e05555")
                                    : Qt.rgba(tema.primary.r, tema.primary.g, tema.primary.b, maBc.containsMouse ? 0.3 : 0.15)
                                Text {
                                    anchors.centerIn: parent
                                    text: bc.modelData.texto
                                    font.family: root.fuente
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: bc.modelData.id === "si" ? "white" : tema.surfaceText
                                }
                                MouseArea {
                                    id: maBc
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: bc.modelData.id === "si" ? root.quitarAcceso(cajaMenu.el) : root.cerrarMenu()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // IPC de prueba: qs -c escritorio ipc call escritorio menu <n.º de icono>
    IpcHandler {
        target: "escritorio"
        function menu(i: int): string {
            if (i < 0 || i >= archivos.count) return "no hay icono " + i
            var nombre = archivos.get(i, "fileName")
            var ruta = archivos.get(i, "filePath")
            var e = root.entradaDe(nombre)
            root.abrirMenu({ fileName: nombre, filePath: ruta, entrada: e, nombre: e ? e.name : nombre }, 10 + (i % 8) * (root.celda + 14) + root.celda)
            return root.opciones(root.menu).map(o => o.texto).join(", ")
        }
        function quitar(): string { if (!root.menu) return "sin menú"; root.elegir(root.menu, "quitar"); return "confirmando: " + root.confirmarQuitar }
        function cerrar(): void { root.cerrarMenu() }
    }
}
