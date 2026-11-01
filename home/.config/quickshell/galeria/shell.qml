//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel

// Galería de fondos: carrusel 3D con vista previa a pantalla completa
// y vista previa de la paleta de matugen antes de aplicar.
Scope {
    id: root

    // ===== Ajustes =====
    property string carpeta: Quickshell.env("HOME") + "/Pictures/wallpapers"
    property string script: Quickshell.env("HOME") + "/.local/bin/wallpaper.sh"
    property int anchoTarjeta: 440          // ancho de cada miniatura
    property real giro: 38                  // grados de giro 3D de las tarjetas laterales

    // ===== Estado =====
    property bool abierto: false
    property bool aplicando: false
    property string actual: ""              // fondo aplicado ahora
    // La tarjeta seleccionada (la del centro): de ella salen el título, la paleta,
    // la vista previa grande y el contador. Pasar el cursor por otra NO cambia nada.
    property string elegido: lista.currentItem ? lista.currentItem.filePath : ""
    // Lo que se previsualiza: el que está bajo el ratón, o el del centro
    property string vista: elegido

    property var paletas: ({})              // ruta -> colores de matugen
    property var fotogramas: ({})           // vídeo/GIF -> imagen fija (la saca fondo-fotograma.sh)

    // Vídeo o GIF: se previsualiza con un fotograma; imagen: ella misma
    function esAnimado(ruta) { return /\.(mp4|webm|mkv|mov|gif)$/i.test(ruta) }
    function imagenDe(ruta) {
        if (ruta === "" || !esAnimado(ruta)) return ruta
        return root.fotogramas[ruta] || ""
    }
    function urlDe(ruta) { var r = imagenDe(ruta); return r !== "" ? "file://" + r : "" }
    property var pal: paletas[vista] || null

    Colors { id: tema }

    // Colores que se muestran: los del fondo previsualizado (animados)
    QtObject {
        id: c
        property color surface: root.pal ? root.pal.surface : tema.surface
        property color surfaceText: root.pal ? root.pal.surfaceText : tema.surfaceText
        property color primary: root.pal ? root.pal.primary : tema.primary
        property color primaryText: root.pal ? root.pal.primaryText : tema.primaryText
        property color secondary: root.pal ? root.pal.secondary : tema.secondary
        property color tertiary: root.pal ? root.pal.tertiary : tema.secondary
        Behavior on surface { ColorAnimation { duration: 500 } }
        Behavior on surfaceText { ColorAnimation { duration: 500 } }
        Behavior on primary { ColorAnimation { duration: 500 } }
        Behavior on primaryText { ColorAnimation { duration: 500 } }
        Behavior on secondary { ColorAnimation { duration: 500 } }
        Behavior on tertiary { ColorAnimation { duration: 500 } }
    }

    function conAlfa(col, a) { return Qt.rgba(col.r, col.g, col.b, a) }

    function bonito(nombre) {
        return nombre.replace(/[-_]+/g, " ").replace(/\b\w/g, l => l.toUpperCase())
    }

    // ===== Atajo: qs -c galeria ipc call galeria toggle =====
    IpcHandler {
        target: "galeria"
        function toggle(): void {
            if (root.abierto) root.cerrar()
            else root.abrir()
        }
        // Para probar: aplica la tarjeta i como si se hiciera clic en (x, y)
        function aplicar(i: int, x: int, y: int): void {
            if (i < 0 || i >= carpetaModelo.count) return
            root.aplicar(carpetaModelo.get(i, "filePath"), x, y)
        }
        // Para probar: selecciona (centra) la tarjeta i, sin aplicar
        function elegir(i: int): void {
            if (i >= 0 && i < carpetaModelo.count) lista.currentIndex = i
        }
        function info(): string {
            var l = []
            for (var i = 0; i < carpetaModelo.count; i++) l.push(carpetaModelo.get(i, "filePath"))
            return JSON.stringify({ abierto: root.abierto, actual: root.actual, fondos: l,
                                    indice: lista.currentIndex, elegido: root.elegido,
                                    vista: root.vista, titulo: titulo.text, contador: contador.text,
                                    previa: (previa.usarA ? imgA : imgB).source.toString(),
                                    paleta: root.pal ? root.pal.primary : null,
                                    fotogramas: root.fotogramas, transicion: ajustesFondo.transicion,
                                    duracion: ajustesFondo.duracion })
        }
    }

    function abrir() {
        esconder.stop()
        root.aplicando = false
        ventana.visible = true
        root.abierto = true
        // Empieza en el fondo actual
        for (var i = 0; i < carpetaModelo.count; i++) {
            if (carpetaModelo.get(i, "filePath") === root.actual) {
                lista.currentIndex = i
                lista.positionViewAtIndex(i, ListView.Center)
                break
            }
        }
        teclado.forceActiveFocus()
    }

    function cerrar() {
        root.abierto = false
        esconder.restart()
    }

    function aplicarCentro() {
        var p = lista.mapToItem(escena, lista.width / 2, 16 + root.anchoTarjeta * 9 / 32)
        aplicar(root.elegido, p.x, p.y)
    }

    // x, y: dónde se hizo clic (la transición del fondo nace ahí)
    function aplicar(ruta, x, y) {
        if (root.aplicando || ruta === "") return
        root.aplicando = true
        pAplicar.command = [root.script, ruta, "-", String(Math.round(x)), String(Math.round(y))]
        // Primero se desvanece la galería, luego el fondo cambia con su transición
        root.cerrar()
        lanzarAplicar.restart()
    }

    Timer {
        id: lanzarAplicar
        interval: 230
        onTriggered: pAplicar.running = true
    }

    Timer {
        id: esconder
        interval: 450
        onTriggered: ventana.visible = false
    }

    Process {
        id: pAplicar
    }

    // Fondo aplicado actualmente
    FileView {
        path: Quickshell.env("HOME") + "/.cache/wallpaper-actual"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.actual = text().trim()
    }

    FolderListModel {
        id: carpetaModelo
        folder: "file://" + root.carpeta
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.JPG", "*.JPEG", "*.PNG",
                      "*.mp4", "*.webm", "*.mkv", "*.mov", "*.gif", "*.MP4", "*.GIF"]
        showDirs: false
        sortField: FolderListModel.Name
        onStatusChanged: if (status === FolderListModel.Ready) buscarFotogramas.restart()
        onCountChanged: buscarFotogramas.restart()
    }

    // ===== Fotogramas de vídeos/GIF (miniatura, vista previa y paleta) =====
    // Las rutas van como argumentos (nunca dentro del texto del comando)
    Timer {
        id: buscarFotogramas
        interval: 300
        onTriggered: {
            if (pFotogramas.running) { restart(); return }
            var faltan = []
            for (var i = 0; i < carpetaModelo.count; i++) {
                var r = carpetaModelo.get(i, "filePath")
                if (root.esAnimado(r) && !root.fotogramas[r]) faltan.push(r)
            }
            if (faltan.length === 0) return
            pFotogramas.command = ["sh", "-c",
                'for f in "$@"; do printf "%s\\t%s\\n" "$f" "$("$HOME/.local/bin/fondo-fotograma.sh" "$f" 2>/dev/null)"; done',
                "sh"].concat(faltan)
            pFotogramas.running = true
        }
    }
    Process {
        id: pFotogramas
        stdout: SplitParser {
            onRead: linea => {
                var partes = linea.split("\t")
                if (partes.length < 2 || partes[1] === "") return
                var copia = Object.assign({}, root.fotogramas)
                copia[partes[0]] = partes[1]
                root.fotogramas = copia
            }
        }
    }
    onFotogramasChanged: { calcularPaleta.restart(); previa.mostrar(root.vista) }

    // ===== Transición del fondo (la usa el módulo "fondo") =====
    FileView {
        id: archivoAjustesFondo
        path: Quickshell.env("HOME") + "/.config/quickshell/fondo/ajustes.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: ajustesFondo
            property string transicion: "circulo"
            property int duracion: 800
            property bool pausarTapado: true
        }
    }

    // ===== Paleta de matugen sin aplicar nada (--dry-run) =====
    Process {
        id: pMatugen
        property string ruta: ""
        command: ["matugen", "image", root.imagenDe(ruta), "--dry-run", "--json", "hex",
                  "--source-color-index", "0", "-t", "scheme-fidelity"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var k = JSON.parse(text).colors
                    var copia = Object.assign({}, root.paletas)
                    copia[pMatugen.ruta] = {
                        surface: k.surface.default.color,
                        surfaceText: k.on_surface.default.color,
                        primary: k.primary.default.color,
                        primaryText: k.on_primary.default.color,
                        secondary: k.secondary.default.color,
                        tertiary: k.tertiary.default.color
                    }
                    root.paletas = copia
                } catch (e) {}
            }
        }
        onRunningChanged: if (!running) calcularPaleta.restart()
    }

    Timer {
        id: calcularPaleta
        interval: 200
        onTriggered: {
            if (root.vista === "" || root.paletas[root.vista] || pMatugen.running) return
            if (root.imagenDe(root.vista) === "") return      // fotograma aún no listo
            pMatugen.ruta = root.vista
            pMatugen.running = true
        }
    }

    onVistaChanged: calcularPaleta.restart()

    // ===================================================================
    PanelWindow {
        id: ventana
        visible: false
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "galeria"
        WlrLayershell.keyboardFocus: root.abierto ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Item {
            id: escena
            anchors.fill: parent
            opacity: root.abierto ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.aplicando ? 220 : 400; easing.type: Easing.OutCubic }
            }

            // ---------- Vista previa a pantalla completa (con fundido) ----------
            Item {
                id: previa
                anchors.fill: parent
                clip: true
                property bool usarA: true
                property string cargando: ""

                function mostrar(ruta) {
                    var url = root.urlDe(ruta)
                    if (url === "") return
                    var visible = previa.usarA ? imgA : imgB
                    if (visible.source.toString() === url) return
                    var oculta = previa.usarA ? imgB : imgA
                    previa.cargando = url
                    oculta.source = url
                    if (oculta.status === Image.Ready) previa.usarA = !previa.usarA
                }

                Connections {
                    target: root
                    function onVistaChanged() { previa.mostrar(root.vista) }
                }

                // Imagen fija, sin zoom ni movimiento
                Item {
                    anchors.fill: parent

                    Image {
                        id: imgA
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: ventana.width
                        opacity: previa.usarA ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: 550; easing.type: Easing.InOutQuad }
                        }
                        onStatusChanged: if (status === Image.Ready && source.toString() === previa.cargando && !previa.usarA) previa.usarA = true
                    }

                    Image {
                        id: imgB
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: ventana.width
                        opacity: previa.usarA ? 0 : 1
                        Behavior on opacity {
                            NumberAnimation { duration: 550; easing.type: Easing.InOutQuad }
                        }
                        onStatusChanged: if (status === Image.Ready && source.toString() === previa.cargando && previa.usarA) previa.usarA = false
                    }
                }

                // Clic en el fondo: cerrar
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.cerrar()
                }
            }

            // ---------- Todo lo de encima (se esconde al aplicar) ----------
            Item {
                id: interfaz
                anchors.fill: parent
                opacity: root.aplicando ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: 350 }
                }

                // Degradado inferior para que se lea el texto
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height * 0.7
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.55; color: root.conAlfa(c.surface, 0.6) }
                        GradientStop { position: 1.0; color: root.conAlfa(c.surface, 0.92) }
                    }
                }

                // ----- Encabezado -----
                Column {
                    id: encabezado
                    anchors.left: parent.left
                    anchors.leftMargin: 70
                    anchors.bottom: lista.top
                    anchors.bottomMargin: 10
                    spacing: 10
                    opacity: root.abierto ? 1 : 0
                    transform: Translate {
                        x: root.abierto ? 0 : -60
                        Behavior on x {
                            NumberAnimation { duration: 600; easing.type: Easing.OutBack }
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 500 }
                    }

                    Row {
                        spacing: 12
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "FONDOS"
                            color: c.primary
                            font.pixelSize: 13
                            font.bold: true
                            font.letterSpacing: 6
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: contador.width + 16
                            height: 22
                            radius: 11
                            color: root.conAlfa(c.primary, 0.2)
                            border.color: c.primary
                            Text {
                                id: contador
                                anchors.centerIn: parent
                                text: (lista.currentIndex + 1) + " / " + carpetaModelo.count
                                color: c.primary
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    // Nombre del fondo (cambia con un pequeño salto)
                    Text {
                        id: titulo
                        property string texto: root.bonito(root.vista.split("/").pop().replace(/\.[^.]+$/, ""))
                        text: texto
                        color: c.surfaceText
                        font.pixelSize: 46
                        font.bold: true
                        style: Text.Raised
                        styleColor: root.conAlfa("black", 0.4)
                        onTextoChanged: saltoTitulo.restart()
                        SequentialAnimation {
                            id: saltoTitulo
                            NumberAnimation { target: titulo; property: "opacity"; from: 0.2; to: 1; duration: 350 }
                        }
                    }

                    // Paleta que generaría matugen
                    Row {
                        spacing: 14

                        Repeater {
                            model: [
                                { n: "Primario", k: "primary" },
                                { n: "Secundario", k: "secondary" },
                                { n: "Terciario", k: "tertiary" },
                                { n: "Superficie", k: "surface" },
                                { n: "Texto", k: "surfaceText" }
                            ]
                            delegate: Column {
                                required property var modelData
                                required property int index
                                spacing: 4
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: c[modelData.k]
                                    border.color: root.conAlfa(c.surfaceText, 0.5)
                                    border.width: 1.5
                                    scale: root.pal ? 1 : 0.6
                                    Behavior on scale {
                                        NumberAnimation { duration: 400 + index * 60; easing.type: Easing.OutBack; easing.overshoot: 3 }
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.n
                                    color: c.surfaceText
                                    opacity: 0.7
                                    font.pixelSize: 10
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !root.pal
                            text: "calculando colores…"
                            color: c.surfaceText
                            opacity: 0.6
                            font.italic: true
                            font.pixelSize: 12
                        }
                    }
                }

                // ----- Maqueta de la barra con los colores nuevos -----
                Column {
                    anchors.right: parent.right
                    anchors.rightMargin: 70
                    anchors.bottom: lista.top
                    anchors.bottomMargin: 18
                    spacing: 8
                    opacity: root.abierto ? 1 : 0
                    transform: Translate {
                        x: root.abierto ? 0 : 60
                        Behavior on x {
                            NumberAnimation { duration: 600; easing.type: Easing.OutBack }
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 500 }
                    }

                    Text {
                        anchors.right: parent.right
                        text: "Así se verá tu barra"
                        color: c.surfaceText
                        opacity: 0.7
                        font.pixelSize: 11
                    }

                    Rectangle {
                        width: 340
                        height: 46
                        radius: 23
                        color: root.conAlfa(c.surface, 0.85)
                        border.color: root.conAlfa(c.primary, 0.6)
                        border.width: 1.5

                        Row {
                            anchors.centerIn: parent
                            spacing: 10

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                radius: 16
                                color: c.primary
                                Grid {
                                    anchors.centerIn: parent
                                    columns: 2
                                    spacing: 2
                                    Repeater {
                                        model: 4
                                        Rectangle { width: 5; height: 5; radius: 1.5; color: c.primaryText }
                                    }
                                }
                            }

                            Repeater {
                                model: ["firefox", "Alacritty", "system-file-manager", "utilities-system-monitor", "multimedia-volume-control"]
                                delegate: Item {
                                    required property string modelData
                                    required property int index
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 36
                                    height: 40
                                    Rectangle {
                                        visible: index === 1
                                        anchors.centerIn: parent
                                        width: 36
                                        height: 36
                                        radius: 11
                                        color: root.conAlfa(c.primary, 0.25)
                                        border.color: c.primary
                                    }
                                    Image {
                                        anchors.centerIn: parent
                                        width: 22
                                        height: 22
                                        sourceSize.width: 48
                                        sourceSize.height: 48
                                        source: Quickshell.iconPath(modelData, "application-x-executable")
                                    }
                                    Rectangle {
                                        visible: index < 2
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        width: index === 1 ? 14 : 4
                                        height: 3
                                        radius: 1.5
                                        color: index === 1 ? c.primary : c.surfaceText
                                    }
                                }
                            }
                        }
                    }
                }

                // ----- Carrusel 3D -----
                ListView {
                    id: lista
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: ayudas.top
                    anchors.bottomMargin: 16
                    height: root.anchoTarjeta * 9 / 16 + 110
                    orientation: ListView.Horizontal
                    model: carpetaModelo
                    spacing: -root.anchoTarjeta * 0.18
                    cacheBuffer: 4000
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: width / 2 - root.anchoTarjeta / 2
                    preferredHighlightEnd: width / 2 + root.anchoTarjeta / 2
                    highlightMoveDuration: 450
                    boundsBehavior: Flickable.StopAtBounds

                    // Entrada desde abajo
                    transform: Translate {
                        y: root.abierto ? 0 : 260
                        Behavior on y {
                            NumberAnimation { duration: 650; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                        }
                    }

                    // Rueda del ratón: avanza tarjeta por tarjeta
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: ev => {
                            if (ev.angleDelta.y < 0 || ev.angleDelta.x < 0) lista.incrementCurrentIndex()
                            else lista.decrementCurrentIndex()
                        }
                    }

                    delegate: Item {
                        id: tarjeta
                        required property int index
                        required property string filePath
                        required property string fileBaseName

                        width: root.anchoTarjeta
                        height: lista.height

                        // Distancia al centro, en tarjetas (0 = en el centro)
                        property real dist: (x + width / 2 - lista.contentX - lista.width / 2) / (width + lista.spacing)
                        property real ad: Math.min(Math.abs(dist), 3)
                        property bool centro: lista.currentIndex === index
                        property bool sobre: zonaT.containsMouse
                        property bool esActual: filePath === root.actual

                        z: 100 - ad * 10 + (sobre ? 5 : 0)
                        opacity: 1 - 0.3 * Math.min(ad, 2.5)
                        scale: (1 - 0.17 * Math.min(ad, 2)) * (sobre ? 1.05 : 1)
                        Behavior on scale {
                            enabled: !lista.moving
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }

                        transform: Rotation {
                            origin.x: tarjeta.width / 2
                            origin.y: foto.height / 2
                            axis { x: 0; y: 1; z: 0 }
                            angle: Math.max(-60, Math.min(60, -tarjeta.dist * root.giro)) * (tarjeta.sobre ? 0.5 : 1)
                            Behavior on angle {
                                enabled: !lista.moving
                                NumberAnimation { duration: 250 }
                            }
                        }

                        // ----- La foto con esquinas redondeadas y brillo -----
                        Item {
                            id: foto
                            width: parent.width
                            height: parent.width * 9 / 16
                            anchors.top: parent.top
                            anchors.topMargin: 16

                            Image {
                                id: imgT
                                anchors.fill: parent
                                visible: false
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 640
                                source: root.urlDe(tarjeta.filePath)
                            }

                            Rectangle {
                                id: mascaraT
                                anchors.fill: parent
                                radius: 20
                                visible: false
                                layer.enabled: true
                            }

                            MultiEffect {
                                anchors.fill: parent
                                source: imgT
                                maskEnabled: true
                                maskSource: mascaraT
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                                brightness: tarjeta.centro || tarjeta.sobre ? 0 : -0.25
                                Behavior on brightness {
                                    NumberAnimation { duration: 300 }
                                }
                                shadowEnabled: true
                                shadowColor: tarjeta.centro ? c.primary : "black"
                                shadowBlur: 1.0
                                shadowOpacity: tarjeta.centro ? 0.9 : 0.6
                                shadowVerticalOffset: tarjeta.centro ? 0 : 10
                            }

                            // Borde de color en la del centro
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -3
                                radius: 23
                                color: "transparent"
                                border.color: c.primary
                                border.width: 3
                                opacity: tarjeta.centro ? 1 : tarjeta.sobre ? 0.5 : 0
                                Behavior on opacity {
                                    NumberAnimation { duration: 250 }
                                }
                            }

                            // Reflejo de vidrio que cruza al pasar el ratón
                            Item {
                                anchors.fill: parent
                                clip: true
                                Rectangle {
                                    width: parent.width * 0.35
                                    height: parent.height * 2.2
                                    y: -parent.height * 0.6
                                    rotation: 25
                                    x: tarjeta.sobre ? parent.width * 1.2 : -parent.width * 0.6
                                    Behavior on x {
                                        NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
                                    }
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.22) }
                                        GradientStop { position: 1.0; color: "transparent" }
                                    }
                                }
                            }

                            // Insignia "Actual"
                            Rectangle {
                                visible: tarjeta.esActual
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 12
                                width: textoActual.width + 22
                                height: 26
                                radius: 13
                                color: c.primary
                                Text {
                                    id: textoActual
                                    anchors.centerIn: parent
                                    text: "✓ Actual"
                                    color: c.primaryText
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            // Insignia "Vídeo" / "GIF"
                            Rectangle {
                                visible: root.esAnimado(tarjeta.filePath)
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 12
                                width: textoTipo.width + 22
                                height: 26
                                radius: 13
                                color: root.conAlfa(c.surface, 0.85)
                                border.color: c.primary
                                Text {
                                    id: textoTipo
                                    anchors.centerIn: parent
                                    text: /\.gif$/i.test(tarjeta.filePath) ? "▶ GIF" : "▶ Vídeo"
                                    color: c.primary
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            // Nombre de esta tarjeta
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.margins: 12
                                width: Math.min(textoNombre.implicitWidth + 24, parent.width - 24)
                                height: 28
                                radius: 14
                                color: root.conAlfa(c.surface, 0.8)
                                Text {
                                    id: textoNombre
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 12
                                    width: parent.width - 24
                                    elide: Text.ElideRight
                                    text: root.bonito(tarjeta.fileBaseName)
                                    color: c.surfaceText
                                    font.pixelSize: 12
                                    font.bold: tarjeta.centro
                                }
                            }

                            // Aviso al pasar el cursor: "Clic para elegir" / "Clic para aplicar"
                            Rectangle {
                                anchors.centerIn: parent
                                width: textoAplicar.width + 26
                                height: 30
                                radius: 15
                                color: root.conAlfa(c.surface, 0.85)
                                border.color: c.primary
                                opacity: tarjeta.sobre && !(tarjeta.centro && tarjeta.esActual) ? 1 : 0
                                scale: tarjeta.sobre ? 1 : 0.8
                                Behavior on opacity {
                                    NumberAnimation { duration: 200 }
                                }
                                Behavior on scale {
                                    NumberAnimation { duration: 250; easing.type: Easing.OutBack }
                                }
                                Text {
                                    id: textoAplicar
                                    anchors.centerIn: parent
                                    text: tarjeta.centro ? "Clic para aplicar" : "Clic para elegir"
                                    color: c.primary
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }
                        }

                        // ----- Reflejo en el "suelo" -----
                        Item {
                            id: reflejo
                            anchors.top: foto.bottom
                            anchors.topMargin: 8
                            width: foto.width
                            height: 80
                            clip: true
                            opacity: tarjeta.centro ? 0.4 : 0.25

                            // La foto volteada: se ve su parte de abajo, como en un espejo
                            Image {
                                width: foto.width
                                height: foto.height
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 320
                                source: root.urlDe(tarjeta.filePath)
                                transform: Scale { yScale: -1; origin.y: foto.height / 2 }
                            }

                            // Se desvanece hacia abajo
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: mascaraReflejo
                                blurEnabled: true
                                blur: 0.3
                            }
                        }

                        Rectangle {
                            id: mascaraReflejo
                            width: reflejo.width
                            height: reflejo.height
                            radius: 20
                            visible: false
                            layer.enabled: true
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "white" }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }

                        MouseArea {
                            id: zonaT
                            x: 0
                            y: foto.y
                            width: foto.width
                            height: foto.height
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (!tarjeta.centro) {
                                    lista.currentIndex = tarjeta.index   // primero se elige
                                    return
                                }
                                var p = zonaT.mapToItem(escena, mouse.x, mouse.y)
                                root.aplicar(tarjeta.filePath, p.x, p.y)
                            }
                        }
                    }
                }

                // ----- Ayudas de teclado -----
                Row {
                    id: ayudas
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 34
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    opacity: root.abierto ? 0.9 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 700 }
                    }

                    Repeater {
                        model: [
                            { t: "← →", d: "navegar" },
                            { t: "Rueda", d: "deslizar" },
                            { t: "Clic", d: "elegir / aplicar" },
                            { t: "Enter", d: "aplicar" },
                            { t: "Esc", d: "cerrar" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: filaAyuda.width + 20
                            height: 30
                            radius: 15
                            color: root.conAlfa(c.surface, 0.7)
                            border.color: root.conAlfa(c.primary, 0.5)
                            Row {
                                id: filaAyuda
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: modelData.t
                                    color: c.primary
                                    font.bold: true
                                    font.pixelSize: 12
                                }
                                Text {
                                    text: modelData.d
                                    color: c.surfaceText
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }

            // ---------- Transición y duración del cambio de fondo ----------
            Component {
                id: chipAjuste
                Rectangle {
                    id: chip
                    property string texto: ""
                    property bool activo: false
                    signal elegir()
                    width: textoChip.width + 24
                    height: 30
                    radius: 15
                    color: activo ? c.primary : root.conAlfa(c.surface, zonaChip.containsMouse ? 0.9 : 0.7)
                    border.color: root.conAlfa(c.primary, activo ? 1 : 0.5)
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                    Text {
                        id: textoChip
                        anchors.centerIn: parent
                        text: chip.texto
                        color: chip.activo ? c.primaryText : c.surfaceText
                        font.pixelSize: 12
                        font.bold: chip.activo
                    }
                    MouseArea {
                        id: zonaChip
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: chip.elegir()
                    }
                }
            }

            Row {
                id: filaTransicion
                anchors.left: parent.left
                anchors.leftMargin: 70
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 34
                spacing: 6
                opacity: root.abierto && !root.aplicando ? 0.95 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 500 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Transición"
                    color: c.surfaceText
                    opacity: 0.75
                    font.pixelSize: 12
                    rightPadding: 4
                }
                Repeater {
                    model: [
                        { n: "Círculo", k: "circulo" },
                        { n: "Ola", k: "ola" },
                        { n: "Barrido", k: "barrido" },
                        { n: "Fundido", k: "fundido" },
                        { n: "Aleatoria", k: "aleatoria" }
                    ]
                    delegate: Loader {
                        required property var modelData
                        sourceComponent: chipAjuste
                        onLoaded: {
                            item.texto = modelData.n
                            item.activo = Qt.binding(() => ajustesFondo.transicion === modelData.k)
                            item.elegir.connect(() => ajustesFondo.transicion = modelData.k)
                        }
                    }
                }
            }

            Row {
                id: filaDuracion
                anchors.right: parent.right
                anchors.rightMargin: 70
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 34
                spacing: 6
                opacity: root.abierto && !root.aplicando ? 0.95 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 500 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Duración"
                    color: c.surfaceText
                    opacity: 0.75
                    font.pixelSize: 12
                    rightPadding: 4
                }
                Repeater {
                    model: [
                        { n: "Rápida", ms: 500 },
                        { n: "Normal", ms: 800 },
                        { n: "Lenta", ms: 1400 }
                    ]
                    delegate: Loader {
                        required property var modelData
                        sourceComponent: chipAjuste
                        onLoaded: {
                            item.texto = modelData.n
                            item.activo = Qt.binding(() => ajustesFondo.duracion === modelData.ms)
                            item.elegir.connect(() => ajustesFondo.duracion = modelData.ms)
                        }
                    }
                }
            }

            // ---------- Teclado ----------
            Item {
                id: teclado
                focus: true
                Keys.onLeftPressed: lista.decrementCurrentIndex()
                Keys.onRightPressed: lista.incrementCurrentIndex()
                Keys.onReturnPressed: root.aplicarCentro()
                Keys.onEnterPressed: root.aplicarCentro()
                Keys.onEscapePressed: root.cerrar()
            }
        }
    }
}
