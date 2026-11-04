//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel

// Galería de fondos: carrusel infinito, ancho y centrado. Tarjetas laterales en paralelogramo (solo se
// inclina el marco) que pierden opacidad y nitidez con la distancia; la del centro se endereza y crece.
// Detrás, la imagen fija difuminada del fondo elegido. Vídeo/GIF solo en la tarjeta del centro.
// Debajo, el nombre, la paleta de matugen y la maqueta de la barra.
Scope {
    id: root

    // Sin el aviso "Config reloaded": matugen recarga este módulo en cada cambio de fondo.
    // Solo se oculta el de recarga correcta; el de error sigue saliendo.
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }

    // ===== Ajustes =====
    property string carpeta: Quickshell.env("HOME") + "/Pictures/wallpapers"
    property string script: Quickshell.env("HOME") + "/.local/bin/wallpaper.sh"
    // Forma del carrusel según la distancia al centro (0, 1, 2, 3, 4 tarjetas), en px a 1920x1080.
    // Entre dos valores se interpola: cada tarjeta cambia de forma de manera continua al moverse.
    readonly property var tablaX:          [0, 560, 793, 984, 1141]
    readonly property var tablaAncho:      [760, 240, 195, 160, 130]
    readonly property var tablaAlto:       [428, 320, 265, 215, 175]
    readonly property var tablaSesgo:      [0, 0.24, 0.24, 0.24, 0.24]
    readonly property var tablaRadio:      [26, 20, 18, 16, 14]
    readonly property var tablaOpacidad:   [1, 0.9, 0.62, 0.34, 0]
    readonly property var tablaDesenfoque: [0, 0.8, 1.7, 2.6, 3.4]
    readonly property real anchoCentro: tablaAncho[0] * root.u
    readonly property real altoCentro: tablaAlto[0] * root.u
    readonly property real margenSombra: 36 * root.u
    property int tarjetasPorLado: 4         // como máximo (sin repetir fondos)
    property int duracionMovimiento: 450
    property real desenfoqueFondo: 6        // niveles de mipmap de la imagen de atrás
    property real tinteFondo: 0.5           // cuánto oscurece el color de superficie al fondo

    // ===== Estado =====
    property bool abierto: false
    property bool aplicando: false
    property var comandoAplicar: []
    property string actual: ""              // fondo aplicado ahora
    readonly property real u: Math.max(0.5, Math.min(ventana.width / 1920, ventana.height / 1080))
    // ===== Carrusel infinito =====
    // "objetivo" es un índice SIN límite (… -1, 0, 1, 2 …); la tarjeta real es objetivo mod n.
    // Así, después del último viene el primero (y al revés) sin rebobinar: el carrusel solo
    // sigue avanzando. carrusel.pos persigue a objetivo con animación.
    readonly property int n: carpetaModelo.count
    property int objetivo: 0
    property bool animar: true
    readonly property int indice: root.n > 0 ? root.mod(root.objetivo, root.n) : -1
    // Ranuras de tarjetas: nunca más que fondos (con 1 o 2 no se repite ninguno)
    readonly property int ranuras: Math.min(root.n, 2 * root.tarjetasPorLado + 1)
    // Ventana visible alrededor de pos: [pos - margen, pos - margen + ranuras)
    readonly property real margenVentana: Math.floor((root.ranuras - 1) / 2) + 0.5
    property int version: 0                 // sube al cambiar la carpeta (get() no avisa)
    function mod(a, m) { return ((a % m) + m) % m }
    function tabla(t, a) {
        var i = Math.min(Math.floor(a), t.length - 2)
        return t[i] + (t[i + 1] - t[i]) * (a - i)
    }
    function rutaEn(i) { root.version; return i >= 0 && i < carpetaModelo.count ? carpetaModelo.get(i, "filePath") : "" }
    function mover(paso) { if (root.n > 1) root.objetivo += paso }
    // Ir a la tarjeta i por el camino más corto (dando la vuelta si hace falta)
    function irA(i) {
        if (root.n < 1 || i < 0 || i >= root.n) return
        var d = root.mod(i - root.indice, root.n)
        if (d > root.n / 2) d -= root.n
        root.objetivo += d
    }

    // La tarjeta seleccionada (la del centro): de ella salen el título, la paleta,
    // el fondo difuminado y el contador. Pasar el cursor por otra NO cambia nada.
    property string elegido: root.rutaEn(root.indice)
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

    // Colores que se muestran: los del fondo elegido (animados)
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
        // Sin la marca de la web de descarga al final ("-moewalls-com")
        return nombre.replace(/(-mp4)?[-_]+\w+[-_]com$/i, "").replace(/[-_]+/g, " ")
            .split(" ").map(p => p.charAt(0).toUpperCase() + p.slice(1)).join(" ")
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
        function elegir(i: int): void { root.irA(i) }
        // Para probar el carrusel infinito: avanza (+) o retrocede (-) varias tarjetas
        function mover(pasos: int): string { root.mover(pasos); return root.indice + " " + root.objetivo }
        function info(): string {
            var l = []
            for (var i = 0; i < carpetaModelo.count; i++) l.push(carpetaModelo.get(i, "filePath"))
            return JSON.stringify({ abierto: root.abierto, actual: root.actual, fondos: l,
                                    indice: root.indice, objetivo: root.objetivo, pos: carrusel.pos,
                                    ranuras: root.ranuras, animada: previaAnim.info(), elegido: root.elegido,
                                    vista: root.vista, titulo: titulo.text, contador: contador.text,
                                    previa: (fondoAtras.usarA ? imgA : imgB).source.toString(),
                                    paleta: root.pal ? root.pal.primary : null,
                                    fotogramas: root.fotogramas, transicion: ajustesFondo.transicion,
                                    duracion: ajustesFondo.duracion })
        }
        // Para probar: forma actual de cada tarjeta visible, ordenadas de izquierda a derecha
        function tarjetas(): string {
            var l = []
            for (var i = 0; i < repetidor.count; i++) {
                var t = repetidor.itemAt(i)
                if (!t || !t.visible) continue
                l.push({ logica: t.logica, d: +t.d.toFixed(3), cx: Math.round(t.cx), ancho: Math.round(t.ancho),
                         alto: Math.round(t.alto), sesgo: +t.sesgo.toFixed(3), opacidad: +t.opacity.toFixed(2),
                         desenfoque: +t.desenfoque.toFixed(2),
                         archivo: t.filePath.split("/").pop() })
            }
            l.sort((a, b) => a.d - b.d)
            return JSON.stringify(l)
        }
    }

    function abrir() {
        esconder.stop()
        root.aplicando = false
        ventana.visible = true
        root.abierto = true
        // Empieza en el fondo actual, sin animar el salto
        for (var i = 0; i < carpetaModelo.count; i++) {
            if (carpetaModelo.get(i, "filePath") === root.actual) {
                root.animar = false
                root.objetivo = i
                root.animar = true
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
        var p = carrusel.mapToItem(escena, carrusel.width / 2, carrusel.height / 2)
        aplicar(root.elegido, p.x, p.y)
    }

    // x, y: dónde se hizo clic (la transición del fondo nace ahí)
    function aplicar(ruta, x, y) {
        if (root.aplicando || ruta === "") return
        root.aplicando = true
        root.comandoAplicar = [root.script, ruta, "-", String(Math.round(x)), String(Math.round(y))]
        // Primero se desvanece la galería, luego el fondo cambia con su transición
        root.cerrar()
        lanzarAplicar.restart()
    }

    Timer {
        id: lanzarAplicar
        interval: 230
        // Separado de la galería (nunca un Process hijo): matugen reescribe Colors.qml, la galería
        // se recarga y una recarga mata a sus procesos hijos, con wallpaper.sh a medias.
        onTriggered: Quickshell.execDetached(root.comandoAplicar)
    }

    Timer {
        id: esconder
        interval: 450
        onTriggered: ventana.visible = false
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
        onStatusChanged: { root.version++; if (status === FolderListModel.Ready) buscarFotogramas.restart() }
        onCountChanged: { root.version++; buscarFotogramas.restart() }
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
    onFotogramasChanged: { calcularPaleta.restart(); fondoAtras.mostrar(root.vista) }

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
            // Los usa el módulo "fondo" (aquí solo para no borrarlos al guardar)
            property bool pausarConBateria: false
            property bool optimizarVideo: true
            property int fpsVideo: 30
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
        screen: Principal.pantalla
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
                NumberAnimation { duration: root.aplicando ? 220 : 300; easing.type: Easing.OutCubic }
            }

            // ---------- Detrás: imagen fija difuminada del fondo elegido (con fundido) ----------
            // Va en una capa propia a media resolución: solo se vuelve a pintar durante el fundido,
            // no en cada fotograma del vídeo de la tarjeta del centro.
            Item {
                id: fondoAtras
                anchors.fill: parent
                layer.enabled: true
                layer.textureSize: Qt.size(Math.ceil(width / 2), Math.ceil(height / 2))
                layer.smooth: true
                property bool usarA: true
                property string cargando: ""

                function mostrar(ruta) {
                    var url = root.urlDe(ruta)
                    if (url === "") return
                    var visible = fondoAtras.usarA ? imgA : imgB
                    if (visible.source.toString() === url) return
                    var oculta = fondoAtras.usarA ? imgB : imgA
                    fondoAtras.cargando = url
                    oculta.source = url
                    if (oculta.status === Image.Ready) fondoAtras.usarA = !fondoAtras.usarA
                }

                Connections {
                    target: root
                    function onVistaChanged() { fondoAtras.mostrar(root.vista) }
                }

                Rectangle { anchors.fill: parent; color: c.surface }

                Image {
                    id: imgA
                    visible: false
                    asynchronous: true
                    mipmap: true
                    sourceSize.width: 640
                    onStatusChanged: if (status === Image.Ready && source.toString() === fondoAtras.cargando && !fondoAtras.usarA) fondoAtras.usarA = true
                }
                Image {
                    id: imgB
                    visible: false
                    asynchronous: true
                    mipmap: true
                    sourceSize.width: 640
                    onStatusChanged: if (status === Image.Ready && source.toString() === fondoAtras.cargando && fondoAtras.usarA) fondoAtras.usarA = false
                }

                Forma {
                    anchors.fill: parent
                    fuente: imgA
                    caja: Qt.size(width + 8, height + 8)
                    relacion: imgA.implicitHeight > 0 ? imgA.implicitWidth / imgA.implicitHeight : 16 / 9
                    desenfoque: root.desenfoqueFondo
                    opacity: fondoAtras.usarA ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
                }
                Forma {
                    anchors.fill: parent
                    fuente: imgB
                    caja: Qt.size(width + 8, height + 8)
                    relacion: imgB.implicitHeight > 0 ? imgB.implicitWidth / imgB.implicitHeight : 16 / 9
                    desenfoque: root.desenfoqueFondo
                    opacity: fondoAtras.usarA ? 0 : 1
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
                }

                // Tinte: hace legible el texto sea cual sea la imagen
                Rectangle { anchors.fill: parent; color: root.conAlfa(c.surface, root.tinteFondo) }
            }

            // Clic en un hueco: cerrar. Rueda en cualquier parte: mover
            MouseArea {
                anchors.fill: parent
                onClicked: root.cerrar()
            }
            property real acumulado: 0
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: ev => {
                    var v = Math.abs(ev.angleDelta.x) > Math.abs(ev.angleDelta.y) ? ev.angleDelta.x : ev.angleDelta.y
                    escena.acumulado += v
                    while (escena.acumulado <= -120) { root.mover(1); escena.acumulado += 120 }
                    while (escena.acumulado >= 120) { root.mover(-1); escena.acumulado -= 120 }
                }
            }

            // ---------- Vídeo o GIF elegido: un solo decodificador, al tamaño de la tarjeta ----------
            // Solo se pinta dentro de "fuenteVideo" (hideSource) y lo muestra la tarjeta del centro.
            PreviaAnimada {
                id: previaAnim
                width: Math.max(1, Math.round(root.anchoCentro))
                height: Math.max(1, Math.round(root.altoCentro))
                ruta: root.abierto && root.esAnimado(root.vista) ? root.vista : ""
                anchoV: ventana.width > 0 ? Math.round(ventana.width) : 1920
                altoV: ventana.height > 0 ? Math.round(ventana.height) : 1080
            }
            ShaderEffectSource {
                id: fuenteVideo
                visible: false
                sourceItem: previaAnim
                hideSource: true
                live: previaAnim.reproduciendo !== ""
                textureSize: Qt.size(previaAnim.width, previaAnim.height)
            }

            // ---------- Todo lo de encima (se esconde al aplicar) ----------
            Item {
                id: interfaz
                anchors.fill: parent
                opacity: root.aplicando ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }

                // ----- Encabezado: contador sobre la tarjeta del centro -----
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: carrusel.top
                    anchors.bottomMargin: 16 * root.u - root.margenSombra
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
                            text: (root.indice + 1) + " / " + root.n
                            color: c.primary
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                }

                // ----- Carrusel infinito -----
                // Hay "ranuras" fijas (como mucho una por fondo). Cada ranura j muestra la tarjeta
                // lógica L ≡ j (mód ranuras) que cae en la ventana visible alrededor de pos; al salir
                // por un borde (ya transparente) reaparece por el otro con su siguiente tarjeta. Así
                // nunca se rebobina y nunca hay dos tarjetas iguales a la vez.
                Item {
                    id: carrusel
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: parent.height * 0.42 - height / 2
                    height: root.altoCentro + 2 * root.margenSombra

                    property real pos: root.objetivo
                    Behavior on pos {
                        enabled: root.animar
                        NumberAnimation { duration: root.duracionMovimiento; easing.type: Easing.OutCubic }
                    }

                    // Entrada: sube un poco mientras la galería aparece
                    transform: Translate {
                        y: root.abierto ? 0 : 36
                        Behavior on y {
                            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                        }
                    }

                    Repeater {
                        id: repetidor
                        model: root.ranuras
                        delegate: Item {
                            id: tarjeta
                            required property int index

                            readonly property int nr: root.ranuras
                            readonly property real m: root.margenVentana
                            // Tarjeta lógica de esta ranura y su distancia al centro (en tarjetas)
                            readonly property int logica: index + nr * Math.ceil((carrusel.pos - m - index) / nr)
                            readonly property real d: logica - carrusel.pos
                            readonly property real ad: Math.abs(d)
                            readonly property real a: Math.min(ad, 4)
                            readonly property real t: Math.min(ad, 1)          // 0 = centro, 1 = lateral
                            readonly property string filePath: root.rutaEn(root.mod(logica, root.n))
                            readonly property bool centro: logica === root.objetivo
                            readonly property bool sobre: zonaT.containsMouse
                            readonly property bool esActual: filePath !== "" && filePath === root.actual
                            // Distancia al borde de la ventana: se desvanece en el último medio paso
                            readonly property real borde: Math.min(d + m, (nr - m) - d)

                            // Forma: sale de las tablas según la distancia
                            readonly property real ancho: root.tabla(root.tablaAncho, a) * root.u
                            readonly property real alto: root.tabla(root.tablaAlto, a) * root.u
                            readonly property real sesgo: root.tabla(root.tablaSesgo, a)
                            readonly property real radio: root.tabla(root.tablaRadio, a) * root.u
                            readonly property real cx: (d < 0 ? -1 : 1) * root.tabla(root.tablaX, a) * root.u
                            // Al pasar el cursor por una lateral: más nítida y más visible
                            property real realce: sobre && !centro ? 1 : 0
                            Behavior on realce { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            readonly property real desenfoque: Math.max(0, root.tabla(root.tablaDesenfoque, a) - realce * 0.8)
                            readonly property real grosorBorde: 3 * root.u * (1 - t) + 1.5 * root.u * t
                            readonly property real alfaBorde: Math.max(0, 1 - 2 * t) + 0.16 * t + realce * 0.5
                            readonly property color colorBorde: t < 0.5 || realce > 0 ? c.primary : c.surfaceText

                            width: ancho + sesgo * alto + 2 * root.margenSombra
                            height: alto + 2 * root.margenSombra
                            x: carrusel.width / 2 + cx - width / 2
                            y: (carrusel.height - height) / 2
                            z: 100 - ad * 5
                            opacity: Math.max(0, Math.min(1, borde / 0.5))
                                     * Math.min(1, root.tabla(root.tablaOpacidad, a) + realce * 0.1)
                                     * cargada
                            visible: opacity > 0.01 && filePath !== ""

                            // Aparece con fundido la primera vez que carga su imagen
                            property real cargada: foto.status === Image.Ready ? 1 : 0
                            Behavior on cargada { NumberAnimation { duration: 180 } }

                            Image {
                                id: foto
                                visible: false
                                asynchronous: true
                                mipmap: true
                                sourceSize.width: 960
                                source: root.urlDe(tarjeta.filePath)
                            }

                            Forma {
                                anchors.fill: parent
                                fuente: foto
                                caja: Qt.size(tarjeta.ancho, tarjeta.alto)
                                sesgo: tarjeta.sesgo
                                radio: tarjeta.radio
                                desenfoque: tarjeta.desenfoque
                                relacion: foto.implicitHeight > 0 ? foto.implicitWidth / foto.implicitHeight : 16 / 9
                                grosorBorde: tarjeta.grosorBorde
                                alfaBorde: tarjeta.alfaBorde
                                colorBorde: tarjeta.colorBorde
                                alfaSombra: 0.4
                                alcanceSombra: root.margenSombra
                                colorSombra: Qt.rgba(c.primary.r * (1 - tarjeta.t), c.primary.g * (1 - tarjeta.t), c.primary.b * (1 - tarjeta.t), 1)
                            }

                            // Vídeo/GIF: solo en la tarjeta del centro (la imagen fija queda debajo)
                            Forma {
                                id: capaVideo
                                anchors.fill: parent
                                readonly property bool activa: tarjeta.centro && previaAnim.listo && previaAnim.reproduciendo === tarjeta.filePath
                                fuente: fuenteVideo
                                caja: Qt.size(tarjeta.ancho, tarjeta.alto)
                                sesgo: tarjeta.sesgo
                                radio: tarjeta.radio
                                relacion: previaAnim.width / Math.max(1, previaAnim.height)
                                grosorBorde: tarjeta.grosorBorde
                                alfaBorde: tarjeta.alfaBorde
                                colorBorde: tarjeta.colorBorde
                                opacity: activa ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: 220 } }
                            }

                            // Insignias: solo en la del centro
                            Item {
                                anchors.centerIn: parent
                                width: tarjeta.ancho
                                height: tarjeta.alto
                                opacity: Math.max(0, 1 - 3 * tarjeta.t)
                                visible: opacity > 0

                                Rectangle {
                                    visible: tarjeta.esActual
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 14
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

                                Rectangle {
                                    visible: root.esAnimado(tarjeta.filePath)
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.margins: 14
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

                                // "Clic para aplicar" al pasar el cursor
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: textoAplicar.width + 26
                                    height: 30
                                    radius: 15
                                    color: root.conAlfa(c.surface, 0.85)
                                    border.color: c.primary
                                    opacity: tarjeta.sobre && tarjeta.centro && !tarjeta.esActual ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: 160 }
                                    }
                                    Text {
                                        id: textoAplicar
                                        anchors.centerIn: parent
                                        text: "Clic para aplicar"
                                        color: c.primary
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }
                            }

                            // En una lateral, el fondo actual se marca con un ✓ pequeño
                            Rectangle {
                                visible: tarjeta.esActual
                                opacity: Math.max(0, 3 * tarjeta.t - 2)
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: root.margenSombra + 10
                                width: 22
                                height: 22
                                radius: 11
                                color: c.primary
                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: c.primaryText
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }

                            // Solo responde dentro del paralelogramo (las esquinas son de las vecinas)
                            MouseArea {
                                id: zonaT
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                containmentMask: QtObject {
                                    function contains(point: point): bool {
                                        var py = point.y - zonaT.height / 2
                                        var px = point.x - zonaT.width / 2 + tarjeta.sesgo * py
                                        return Math.abs(px) <= tarjeta.ancho / 2 && Math.abs(py) <= tarjeta.alto / 2
                                    }
                                }
                                onClicked: mouse => {
                                    if (!tarjeta.centro) {
                                        root.objetivo = tarjeta.logica        // primero se elige
                                        return
                                    }
                                    var p = zonaT.mapToItem(escena, mouse.x, mouse.y)
                                    root.aplicar(tarjeta.filePath, p.x, p.y)
                                }
                            }
                        }
                    }
                }

                // ----- Debajo: nombre, paleta y maqueta de la barra -----
                Column {
                    id: detalle
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: carrusel.bottom
                    anchors.topMargin: 2
                    spacing: 16

                    // Nombre del fondo (cambia con un fundido)
                    Text {
                        id: titulo
                        anchors.horizontalCenter: parent.horizontalCenter
                        property string texto: root.bonito(root.vista.split("/").pop().replace(/\.[^.]+$/, ""))
                        width: Math.min(implicitWidth, interfaz.width - 200)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: texto
                        color: c.surfaceText
                        font.pixelSize: 34
                        font.bold: true
                        onTextoChanged: saltoTitulo.restart()
                        NumberAnimation { id: saltoTitulo; target: titulo; property: "opacity"; from: 0.2; to: 1; duration: 300 }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 44

                        // Paleta que generaría matugen
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
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
                                    spacing: 4
                                    opacity: root.pal ? 1 : 0.35
                                    Behavior on opacity { NumberAnimation { duration: 250 } }
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 32
                                        height: 32
                                        radius: 16
                                        color: c[modelData.k]
                                        border.color: root.conAlfa(c.surfaceText, 0.5)
                                        border.width: 1.5
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.n
                                        color: c.surfaceText
                                        opacity: 0.75
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }

                        // Maqueta de la barra con los colores nuevos
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.pal ? "Así se verá tu barra" : "Calculando colores…"
                                color: c.surfaceText
                                opacity: 0.75
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
                    }
                }

                // ----- Ayudas de teclado -----
                Row {
                    id: ayudas
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 34
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

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
                anchors.leftMargin: 40
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 34
                spacing: 6
                opacity: root.abierto && !root.aplicando ? 0.95 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
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
                anchors.rightMargin: 40
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 34
                spacing: 6
                opacity: root.abierto && !root.aplicando ? 0.95 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
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
                Keys.onLeftPressed: root.mover(-1)
                Keys.onRightPressed: root.mover(1)
                Keys.onReturnPressed: root.aplicarCentro()
                Keys.onEnterPressed: root.aplicarCentro()
                Keys.onEscapePressed: root.cerrar()
            }
        }
    }
}
