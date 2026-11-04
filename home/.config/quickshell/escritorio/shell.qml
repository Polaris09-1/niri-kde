//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel

// Escritorio: elementos (reloj y un icono por cada archivo de ~/Desktop) sobre una cuadrícula, en la capa
// de fondo. Modo "Personalizar escritorio" (clic derecho en un hueco o Mod+Shift+D): arrastrar, tamaños
// S/M/L y opciones de cada elemento (engranaje).
// Con ventanas abiertas va a un workspace vacío y al salir vuelve (las ventanas no se mueven).
//
// - NO se recarga solo (Quickshell.watchFiles = false): matugen reescribe Colors.qml al cambiar el fondo
//   y una recarga perdería la edición en curso. Los colores se leen con FileView. Tras editar este módulo:
//   pkill -f -- '-c escritorio$'; niri msg action spawn -- qs -c escritorio
// - Diseños en disenos.json (junto a este archivo): "global" y "fondos" (uno propio por fondo, con la ruta
//   relativa a ~/Pictures/wallpapers). Al cambiar de fondo se carga el suyo o, si no tiene, el global.
//
// IPC: qs -c escritorio ipc call escritorio <personalizar|listo|cancelar|info|menu <i>|quitar|cerrar|
//      mover <clave> <col> <fila>|tam <clave> <S|M|L>|opcion <clave> <opción> <valor>|panel <clave>|
//      saludoPara <hora>|anadir <tipo>|quitarElemento <clave>|blur <si|no>|estadoWidget <clave>>
Scope {
    id: root

    // ===== Ajustes =====
    property string carpeta: Quickshell.env("HOME") + "/Desktop"
    property string fuente: "JetBrainsMono Nerd Font"
    property int paso: 32                   // lado de cada celda de la cuadrícula, en px
    property int margen: 16                 // de la cuadrícula al borde de la zona útil
    // Tamaño de cada elemento en celdas: [columnas, filas]
    readonly property var tamanos: ({
        reloj: { S: [8, 6], M: [12, 8], L: [15, 11] },
        icono: { S: [3, 3], M: [4, 4], L: [5, 5] },
        grupo: { S: [3, 3], M: [4, 4], L: [5, 5] },
        calendario: { S: [6, 6], M: [9, 9], L: [12, 13] },
        clima: { S: [6, 5], M: [10, 6], L: [10, 11] },
        recordatorios: { S: [8, 7], M: [10, 10], L: [12, 14] },
        musica: { S: [9, 3], M: [11, 4], L: [9, 9] }
    })
    // Catálogo: uno de cada tipo (el clima tiene una sola ciudad y hay una sola lista de recordatorios)
    readonly property var catalogo: [
        { tipo: "reloj", nombre: "Reloj", desc: "Hora, fecha y saludo", glifo: 0xF0954 },
        { tipo: "calendario", nombre: "Calendario", desc: "Hoy o el mes entero", glifo: 0xF00ED },
        { tipo: "clima", nombre: "Clima", desc: "Ahora y pronóstico", glifo: 0xF0595 },
        { tipo: "recordatorios", nombre: "Recordatorios", desc: "Tu lista de pendientes", glifo: 0xF0134 },
        { tipo: "musica", nombre: "Música", desc: "Lo que está sonando", glifo: 0xF075A }
    ]
    // Valores de cada opción si el diseño no dice otra cosa
    readonly property var opcionesBase: ({
        reloj: { kanji: true, fecha: true, saludo: true, tarjeta: false, h12: false, nombre: "" },
        icono: { etiqueta: true },
        grupo: { etiqueta: true, nombre: "Grupo", miembros: [] },
        calendario: { domingo: false },
        clima: { fahrenheit: false, pronostico: true },
        recordatorios: { completados: true },
        musica: { caratula: true, controles: true }
    })
    readonly property string prefijoIcono: "icono:"
    readonly property string prefijoGrupo: "grupo:"
    readonly property string carpetaFondos: Quickshell.env("HOME") + "/Pictures/wallpapers/"
    property int duracionFundido: 200       // ms de cada mitad del cambio de diseño entre fondos
    property int esperaGrupo: 500           // ms sobre otro icono para que soltar cree un grupo
    // Apps que no se ofrecen (por inicio del nombre), igual que en el cajón
    readonly property var appsOcultas: ["Avahi", "Foot Client", "Foot Server", "Hardware Locality", "Qt V4L2", "xgps"]
    // El escritorio de siempre: reloj abajo a la derecha; los iconos llegan solos a los primeros huecos
    readonly property var disenoInicial: [
        { clave: "reloj", tipo: "reloj", col: 42, fila: 17, tam: "L" }
    ]

    // ===== Estado =====
    property bool editando: false
    property string seleccion: ""
    property var fantasma: null             // adónde caería lo que se arrastra
    property var alEntrar: []               // copia del diseño al entrar (para Cancelar y detectar cambios)
    property string aviso: ""
    property string panelClave: ""          // elemento con el panel de opciones abierto
    property string sobreClave: ""          // elemento bajo el cursor
    property bool sobreBarra: false
    property var sinHueco: []               // archivos que no caben en la cuadrícula
    property bool disenoListo: false
    // ----- Diseños por fondo -----
    property string fondoActual: ""         // clave del fondo aplicado (ruta relativa a la carpeta de fondos)
    property string cargadoPara: ""         // fondo cuyo diseño está en pantalla: ahí se guardan los cambios
    property bool datosListos: false
    property bool fondoListo: false
    property bool cambiando: false          // fundido entre dos diseños
    property real opacidadElementos: 1
    property string dialogo: ""             // "" | "salir" | "borrarPropio"
    readonly property bool tienePropio: root.fondoActual !== "" && !!root.datos.fondos && !!root.datos.fondos[root.fondoActual]
    readonly property string nombreFondo: {
        var n = root.fondoActual.split("/").pop().replace(/\.[^.]+$/, "")
        return n.replace(/(-mp4)?[-_]+\w+[-_]com$/i, "").replace(/[-_]+/g, " ").replace(/\b\w/g, l => l.toUpperCase())
    }
    property bool catalogoAbierto: false
    property bool escribiendo: false        // un campo fuera del modo edición necesita el teclado
    property bool usarBlur: true            // desenfoque real de niri detrás de las tarjetas
    property var regionesBlur: []
    property string pestana: "apps"         // pestaña de "+ Añadir": apps | widgets
    property string filtroApps: ""
    property string destinoApps: ""         // "" = escritorio; si no, la clave de un grupo
    property var ocultos: ({})              // archivos que no se muestran: quitados en esta edición o borrándose
    property var quitados: []               // accesos que se borran al pulsar Listo
    property var creados: []                // accesos creados en esta edición (Cancelar los borra)
    property var pendientes: ({})           // archivo que va a llegar -> { grupo } o { col, fila }
    property var colaCopias: []
    property string grupoAbierto: ""
    property string objetivoGrupo: ""       // sobre qué se mantiene el icono que se arrastra
    property bool objetivoListo: false      // ya pasó la espera: soltar agrupa
    property bool arrastreElemento: false
    property bool arrastreSobrePanel: false
    property string miembroArrastrado: ""   // icono que se saca de un grupo
    property real flotanteX: 0
    property real flotanteY: 0
    property var destinoSacar: null
    readonly property string claveBarra: !root.editando || root.fantasma !== null || root.grupoAbierto !== "" ? ""
        : root.panelClave !== "" ? root.panelClave
        : root.sobreClave !== "" ? root.sobreClave : root.seleccion
    property bool tapado: false             // una ventana tapa (casi) todo el escritorio
    property real cobertura: 0
    readonly property bool pausado: root.tapado && !root.editando
    property var datos: ({ version: 1, global: { elementos: [] }, fondos: {} })

    readonly property int columnas: Math.max(1, Math.floor((ventana.width - 2 * root.margen) / root.paso))
    readonly property int filas: Math.max(1, Math.floor((ventana.height - 2 * root.margen) / root.paso))

    function xDe(c) { return root.margen + c * root.paso }
    function yDe(f) { return root.margen + f * root.paso }
    function colDe(x) { return Math.round((x - root.margen) / root.paso) }
    function filaDe(y) { return Math.round((y - root.margen) / root.paso) }
    function colEnVista(c, w) { return Math.max(0, Math.min(c, root.columnas - w)) }
    function filaEnVista(f, h) { return Math.max(0, Math.min(f, root.filas - h)) }
    function tamCeldas(tipo, tam) {
        var t = root.tamanos[tipo]
        return t && t[tam] ? t[tam] : [4, 4]
    }

    // ===== Colores (no se recarga con matugen: se leen del archivo) =====
    QtObject {
        id: colores
        property color surface: "#0f1419"
        property color surfaceText: "#dfe3ea"
        property color primary: "#96ccff"
        property color primaryText: "#003353"
        Behavior on surface { ColorAnimation { duration: 400 } }
        Behavior on surfaceText { ColorAnimation { duration: 400 } }
        Behavior on primary { ColorAnimation { duration: 400 } }
        Behavior on primaryText { ColorAnimation { duration: 400 } }
    }
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

    // ===== Diseño: modelo y archivo =====
    ListModel { id: modelo }

    function indiceDe(clave) {
        for (var i = 0; i < modelo.count; i++) if (modelo.get(i).clave === clave) return i
        return -1
    }
    function instantanea() {
        var l = []
        for (var i = 0; i < modelo.count; i++) {
            var m = modelo.get(i)
            l.push({ clave: m.clave, tipo: m.tipo, col: m.col, fila: m.fila, tam: m.tam, opciones: JSON.parse(m.op) })
        }
        return l
    }
    function hayCambios() { return JSON.stringify(root.instantanea()) !== JSON.stringify(root.alEntrar) }

    function opcionesDe(tipo, op) {
        var guardadas = {}
        try { guardadas = JSON.parse(op || "{}") } catch (e) {}
        return Object.assign({}, root.opcionesBase[tipo] || {}, guardadas)
    }
    function ponerOpcion(clave, opcion, valor) {
        var i = root.indiceDe(clave)
        if (i < 0) return
        var o = JSON.parse(modelo.get(i).op)
        o[opcion] = valor
        modelo.setProperty(i, "op", JSON.stringify(o))
    }

    function valido(e, vistos) {
        return e && typeof e.clave === "string" && !vistos[e.clave] && root.tamanos[e.tipo]
            && ["S", "M", "L"].indexOf(e.tam) >= 0 && Number.isInteger(e.col) && Number.isInteger(e.fila)
    }

    // Actualiza sobre la marcha lo que ya existe: los elementos no se vuelven a crear
    function cargar(lista) {
        var vistos = {}
        var limpia = []
        for (var e of lista) if (root.valido(e, vistos)) { vistos[e.clave] = true; limpia.push(e) }
        for (var i = modelo.count - 1; i >= 0; i--) if (!vistos[modelo.get(i).clave]) modelo.remove(i)
        for (var n of limpia) {
            var k = root.indiceDe(n.clave)
            var fila = { clave: n.clave, tipo: n.tipo, col: n.col, fila: n.fila, tam: n.tam, op: JSON.stringify(n.opciones || {}) }
            if (k < 0) modelo.append(fila)
            else modelo.set(k, fila)
        }
    }

    // ===== Archivos de ~/Desktop: cada uno es un elemento =====
    FolderListModel {
        id: archivos
        folder: "file://" + root.carpeta
        showDirsFirst: true
        showHidden: false
        sortField: FolderListModel.Name
        onStatusChanged: esperaConciliar.restart()
        onCountChanged: esperaConciliar.restart()
        onRowsInserted: esperaConciliar.restart()
        onRowsRemoved: esperaConciliar.restart()
        onModelReset: esperaConciliar.restart()
    }
    Timer {
        id: esperaConciliar
        interval: 200
        onTriggered: root.conciliar()
    }
    property var carpetas: ({})             // archivo -> es carpeta
    function esCarpeta(archivo) { return root.carpetas[archivo] === true }

    // El primer hueco libre: de arriba abajo y luego a la derecha
    function primerHueco(clave, w, h) {
        var r = root.ocupados(clave)
        for (var x = 0; x <= root.columnas - w; x++)
            for (var y = 0; y <= root.filas - h; y++)
                if (root.libreEn(r, x, y, w, h)) return { col: x, fila: y }
        return null
    }
    function miembrosDe(m) {
        try { return JSON.parse(m.op).miembros || [] } catch (e) { return [] }
    }
    function esArchivoVisible(n) { return root.carpetas[n] !== undefined && !root.ocultos[n] }
    function entradaDe(nombre) {
        if (!nombre.endsWith(".desktop")) return null
        var id = nombre.slice(0, -8)
        return DesktopEntries.applications.values.find(a => a.id === id) || null
    }
    function fuenteIcono(nombre) {
        var e = root.entradaDe(nombre)
        if (e) return Quickshell.iconPath(e.icon, "application-x-executable")
        if (root.carpetas[nombre] === true) return Quickshell.iconPath("folder", "text-x-generic")
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
        return Quickshell.iconPath(mapa[ext] || "text-x-generic", "text-x-generic")
    }
    function abrirArchivo(nombre) {
        var e = root.entradaDe(nombre)
        // execute() no abre terminal: una app con Terminal=true quedaría corriendo sin ventana
        if (e && e.runInTerminal) Quickshell.execDetached(["alacritty", "-e"].concat(e.command))
        else if (e) e.execute()
        else Quickshell.execDetached(["xdg-open", root.carpeta + "/" + nombre])
    }

    // Deja los iconos del diseño iguales a lo que hay en la carpeta. Lo que cambia sin estar editando se
    // guarda al momento, para que el icono nuevo no cambie de sitio al reiniciar.
    function conciliar() {
        if (!root.disenoListo || archivos.status !== FolderListModel.Ready || ventana.width <= 0) return
        var existen = {}
        var dirs = {}
        var orden = []
        for (var a = 0; a < archivos.count; a++) {
            var nombre = archivos.get(a, "fileName")
            existen[nombre] = true
            dirs[nombre] = archivos.get(a, "fileIsDir")
            orden.push(nombre)
        }
        root.carpetas = dirs
        // Lo que se ocultó para borrarlo deja de contar en cuanto el archivo ya no está
        var oc = Object.assign({}, root.ocultos)
        var hayQuitar = false
        for (var o in oc) if (!existen[o]) { delete oc[o]; hayQuitar = true }
        if (hayQuitar) root.ocultos = oc
        var visible = n => existen[n] && !oc[n]
        var cambio = false

        // Grupos: sin los archivos que ya no están; con uno solo, ese icono ocupa su lugar
        var enGrupo = {}
        for (var g = modelo.count - 1; g >= 0; g--) {
            var mg = modelo.get(g)
            if (mg.tipo !== "grupo") continue
            var og = JSON.parse(mg.op)
            var antes = og.miembros || []
            var quedan = antes.filter(visible)
            if (quedan.length <= 1) {
                var cg = mg.col, fg = mg.fila, tg = mg.tam, claveG = mg.clave
                modelo.remove(g)
                if (root.grupoAbierto === claveG) root.grupoAbierto = ""
                if (quedan.length === 1)
                    modelo.append({ clave: root.prefijoIcono + quedan[0], tipo: "icono", col: cg, fila: fg, tam: tg, op: "{}" })
                cambio = true
                continue
            }
            if (quedan.length !== antes.length) {
                og.miembros = quedan
                modelo.setProperty(g, "op", JSON.stringify(og))
                cambio = true
            }
            for (var q of quedan) enGrupo[q] = true
        }

        for (var i = modelo.count - 1; i >= 0; i--) {
            var m = modelo.get(i)
            if (m.tipo !== "icono") continue
            var na = m.clave.slice(root.prefijoIcono.length)
            if (!visible(na) || enGrupo[na]) {
                modelo.remove(i)
                cambio = true
            }
        }
        var sin = []
        var t = root.tamCeldas("icono", "M")
        var pend = Object.assign({}, root.pendientes)
        var hayPend = false
        for (var n of orden) {
            var clave = root.prefijoIcono + n
            if (!visible(n) || enGrupo[n] || root.indiceDe(clave) >= 0) continue
            var dest = pend[n]
            if (dest) { delete pend[n]; hayPend = true }
            if (dest && dest.grupo && root.indiceDe(dest.grupo) >= 0) {
                root.meterEnGrupo(dest.grupo, n)
                cambio = true
                continue
            }
            var d = dest && dest.col !== undefined ? root.posicionLibre(clave, dest.col, dest.fila, t[0], t[1])
                                                   : root.primerHueco(clave, t[0], t[1])
            if (!d) { sin.push(n); continue }
            modelo.append({ clave: clave, tipo: "icono", col: d.col, fila: d.fila, tam: "M", op: "{}" })
            cambio = true
        }
        if (hayPend) root.pendientes = pend
        root.sinHueco = sin
        if (cambio && !root.editando) root.guardar()
    }

    FileView {
        id: archivo
        path: Quickshell.env("HOME") + "/.config/quickshell/escritorio/disenos.json"
        printErrors: false
        onLoaded: {
            try {
                var d = JSON.parse(text())
                if (!d.global || !Array.isArray(d.global.elementos)) throw "sin diseño global"
                if (!d.fondos) d.fondos = {}
                root.datos = d
            } catch (e) {
                // No se pierde: queda una copia y se usa el diseño de siempre
                console.warn("escritorio: disenos.json no se pudo leer:", e)
                Quickshell.execDetached(["cp", "-f", "--", archivo.path, archivo.path + ".corrupto"])
                root.datos = { version: 1, global: { elementos: root.disenoInicial }, fondos: {} }
            }
            root.datosListos = true
            root.iniciar()
        }
        onLoadFailed: {
            root.datos = { version: 1, global: { elementos: root.disenoInicial }, fondos: {} }
            root.datosListos = true
            root.iniciar()
        }
    }

    // ===== Diseños por fondo =====
    function claveFondo(ruta) {
        return ruta.startsWith(root.carpetaFondos) ? ruta.slice(root.carpetaFondos.length) : ruta
    }
    FileView {
        path: Quickshell.env("HOME") + "/.cache/wallpaper-actual"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.fondoActual = root.claveFondo(text().trim())
            root.fondoListo = true
            root.iniciar()
            root.revisarFondo()
        }
        onLoadFailed: { root.fondoListo = true; root.iniciar() }
    }
    function disenoDe(clave) {
        var f = root.datos.fondos
        return clave !== "" && f && f[clave] ? f[clave].elementos : root.datos.global.elementos
    }
    // Solo cuando ya se sabe tanto el contenido del archivo como el fondo: si no, se vería un diseño y luego otro
    function iniciar() {
        if (root.disenoListo || !root.datosListos || !root.fondoListo) return
        root.cargadoPara = root.fondoActual
        root.cargar(root.disenoDe(root.fondoActual))
        root.disenoListo = true
        esperaConciliar.restart()
    }
    // Se comprueba al cambiar el fondo y al salir de la edición (mientras se edita no se toca nada)
    function revisarFondo() {
        if (!root.disenoListo || root.editando || root.cargadoPara === root.fondoActual) return
        root.fundirDiseno()
    }
    function fundirDiseno() {
        root.cerrarMenu()
        root.cerrarGrupo()
        if (root.escribiendo) { root.escribiendo = false; root.soltarTexto() }
        root.cambiando = true
        root.opacidadElementos = 0
        mitadFundido.restart()
    }
    Timer {
        id: mitadFundido
        interval: root.duracionFundido
        onTriggered: {
            root.cargadoPara = root.fondoActual
            root.cargar(root.disenoDe(root.fondoActual))
            root.conciliar()
            root.opacidadElementos = 1
            finFundido.restart()
        }
    }
    Timer {
        id: finFundido
        interval: root.duracionFundido
        onTriggered: { root.cambiando = false; root.revisarFondo() }
    }
    // destino: "" = el diseño en pantalla · "fondo" = propio del fondo actual · "global" = para todos
    // ("global" borra el propio solo del fondo actual: los demás conservan el suyo).
    function guardar(destino) {
        var d = Object.assign({}, root.datos)
        var f = Object.assign({}, d.fondos || {})
        var lista = root.instantanea()
        var clave = destino ? root.fondoActual : root.cargadoPara
        if (destino === "fondo" && clave !== "") {
            f[clave] = { elementos: lista }
        } else if (destino === "global") {
            d.global = { elementos: lista }
            delete f[clave]
        } else if (clave !== "" && f[clave]) {
            f[clave] = { elementos: lista }
        } else {
            d.global = { elementos: lista }
        }
        d.version = 1
        d.fondos = f
        root.datos = d
        if (destino) root.cargadoPara = root.fondoActual
        archivo.setText(JSON.stringify(d, null, 2) + "\n")
    }
    // Vuelve al diseño general: el propio se pierde (por eso se pide confirmación antes)
    function borrarPropio() {
        if (!root.tienePropio) return
        var d = Object.assign({}, root.datos)
        var f = Object.assign({}, d.fondos)
        delete f[root.fondoActual]
        d.fondos = f
        root.datos = d
        archivo.setText(JSON.stringify(d, null, 2) + "\n")
        root.dialogo = ""
        root.cerrarMenu()
        if (root.editando) {
            root.seleccion = ""
            root.panelClave = ""
            root.cerrarGrupo()
            root.cargadoPara = root.fondoActual
            root.cargar(root.disenoDe(root.fondoActual))
            root.conciliar()
            root.alEntrar = root.instantanea()
        } else {
            root.fundirDiseno()
        }
    }

    // ===== Cuadrícula =====
    // Se lee el modelo una vez y luego se compara con números: con muchos iconos esto corre en cada
    // movimiento del cursor y consultar el modelo miles de veces se notaría.
    function ocupados(clave) {
        var r = []
        for (var i = 0; i < modelo.count; i++) {
            var m = modelo.get(i)
            if (m.clave === clave) continue
            var t = root.tamCeldas(m.tipo, m.tam)
            var oc = root.colEnVista(m.col, t[0]), of = root.filaEnVista(m.fila, t[1])
            r.push(oc, of, oc + t[0], of + t[1])
        }
        return r
    }
    function libreEn(r, c, f, w, h) {
        if (c < 0 || f < 0 || c + w > root.columnas || f + h > root.filas) return false
        for (var i = 0; i < r.length; i += 4)
            if (c < r[i + 2] && r[i] < c + w && f < r[i + 3] && r[i + 1] < f + h) return false
        return true
    }
    function cabe(clave, c, f, w, h) { return root.libreEn(root.ocupados(clave), c, f, w, h) }
    // La posición libre más cercana a (c, f), o null si no cabe en ninguna parte
    function posicionLibre(clave, c, f, w, h) {
        var cc = Math.max(0, Math.min(c, root.columnas - w))
        var ff = Math.max(0, Math.min(f, root.filas - h))
        var r = root.ocupados(clave)
        if (root.libreEn(r, cc, ff, w, h)) return { col: cc, fila: ff }
        var mejor = null, dist = Infinity
        for (var y = 0; y <= root.filas - h; y++) {
            for (var x = 0; x <= root.columnas - w; x++) {
                var q = (x - c) * (x - c) + (y - f) * (y - f)
                if (q < dist && root.libreEn(r, x, y, w, h)) { dist = q; mejor = { col: x, fila: y } }
            }
        }
        return mejor
    }
    function colocar(clave, c, f) {
        var i = root.indiceDe(clave)
        if (i < 0) return
        modelo.setProperty(i, "col", c)
        modelo.setProperty(i, "fila", f)
    }
    function ponerTam(clave, tam) {
        var i = root.indiceDe(clave)
        if (i < 0) return false
        var m = modelo.get(i)
        var t = root.tamCeldas(m.tipo, tam)
        var d = root.posicionLibre(clave, m.col, m.fila, t[0], t[1])
        if (!d) { root.avisar("No hay espacio para ese tamaño"); return false }
        modelo.set(i, { clave: m.clave, tipo: m.tipo, col: d.col, fila: d.fila, tam: tam, op: m.op })
        root.conciliar()
        return true
    }
    // Quita el foco del campo de texto; Esc y Enter vuelven a ser los del modo edición
    function soltarTexto() { escena.forceActiveFocus() }

    // Barra de ajustes: sigue al cursor con un margen, para poder llegar hasta ella sin que se vaya
    function marcarSobre(clave, encima) {
        if (root.sobreBarra) return
        if (encima) { perderSobre.stop(); root.sobreClave = clave }
        else if (root.sobreClave === clave) perderSobre.restart()
    }
    Timer {
        id: perderSobre
        interval: 220
        onTriggered: if (!root.sobreBarra) root.sobreClave = ""
    }
    function itemDe(clave) {
        for (var i = 0; i < repetidor.count; i++) {
            var it = repetidor.itemAt(i)
            if (it && it.clave === clave) return it
        }
        return null
    }
    // ¿Cuánto estorba el rectángulo r? 0 = nada · 1 = tapa a otro elemento · 2 = se sale o tapa a su elemento
    function estorbo(r, el, evitar) {
        if (r.x < 4 || r.y < 4 || r.x + r.w > ventana.width - 4 || r.y + r.h > ventana.height - 4) return 2
        var cruza = (a) => r.x < a.x + a.w && a.x < r.x + r.w && r.y < a.y + a.h && a.y < r.y + r.h
        if (cruza({ x: el.x, y: el.y, w: el.width, h: el.height })) return 2
        if (evitar && evitar.some(cruza)) return 2
        for (var i = 0; i < repetidor.count; i++) {
            var it = repetidor.itemAt(i)
            if (it && it !== el && cruza({ x: it.x, y: it.y, w: it.width, h: it.height })) return 1
        }
        return 0
    }
    // De los sitios propuestos, el primero que estorbe menos
    function mejorSitio(candidatos, w, h, el, evitar) {
        var mejor = null, nivel = 3
        for (var c of candidatos) {
            var n = root.estorbo({ x: c.x, y: c.y, w: w, h: h }, el, evitar)
            if (n < nivel) { mejor = c; nivel = n }
            if (n === 0) break
        }
        return mejor || candidatos[0]
    }
    function zonaBarraEdicion() {
        return { x: barraEdicion.x, y: 14, w: barraEdicion.width, h: barraEdicion.height }
    }
    function sitioBarra(el, w, h) {
        var g = 6
        var cx = Math.max(4, Math.min(ventana.width - w - 4, el.x + (el.width - w) / 2))
        return root.mejorSitio([
            { x: cx, y: el.y - h - g },
            { x: el.x + el.width + g, y: el.y },
            { x: el.x - w - g, y: el.y },
            { x: cx, y: el.y + el.height + g }
        ], w, h, el, [root.zonaBarraEdicion()])
    }
    function sitioPanel(el, w, h, b) {
        var g = 6
        var cerca = (y) => Math.max(4, Math.min(ventana.height - h - 4, y))
        return root.mejorSitio([
            { x: Math.max(4, Math.min(ventana.width - w - 4, b.x)), y: b.y + b.h + g },
            { x: el.x + el.width + g, y: cerca(el.y) },
            { x: el.x - w - g, y: cerca(el.y) },
            { x: Math.max(4, Math.min(ventana.width - w - 4, b.x)), y: b.y - h - g }
        ], w, h, el, [root.zonaBarraEdicion(), b])
    }

    // ===== Grupos =====
    function meterEnGrupo(clave, archivo) {
        var i = root.indiceDe(clave)
        if (i < 0) return
        var o = JSON.parse(modelo.get(i).op)
        var l = o.miembros || []
        if (l.indexOf(archivo) < 0) l.push(archivo)
        o.miembros = l
        modelo.setProperty(i, "op", JSON.stringify(o))
    }
    function nombreNuevoGrupo() {
        var usados = {}
        for (var i = 0; i < modelo.count; i++) {
            var m = modelo.get(i)
            if (m.tipo === "grupo") usados[JSON.parse(m.op).nombre] = true
        }
        if (!usados["Grupo"]) return "Grupo"
        for (var n = 2; ; n++) if (!usados["Grupo " + n]) return "Grupo " + n
    }
    // Saca el archivo de donde esté: suelto o dentro de un grupo
    function sacarDeDonde(archivo, origen) {
        if (origen !== "") {
            var ig = root.indiceDe(origen)
            if (ig >= 0) {
                var o = JSON.parse(modelo.get(ig).op)
                o.miembros = (o.miembros || []).filter(x => x !== archivo)
                modelo.setProperty(ig, "op", JSON.stringify(o))
            }
        } else {
            var il = root.indiceDe(root.prefijoIcono + archivo)
            if (il >= 0) modelo.remove(il)
        }
    }
    // Mete el archivo en el grupo destino o crea uno nuevo con el icono destino
    function agrupar(archivo, destino, origen) {
        var i = root.indiceDe(destino)
        if (i < 0) return
        var md = modelo.get(i)
        if (md.tipo === "icono") {
            var base = md.clave.slice(root.prefijoIcono.length)
            var nueva = root.prefijoGrupo + Date.now()
            var op = JSON.stringify({ nombre: root.nombreNuevoGrupo(), miembros: [base, archivo] })
            var fila = { clave: nueva, tipo: "grupo", col: md.col, fila: md.fila, tam: md.tam, op: op }
            root.sacarDeDonde(archivo, origen)
            modelo.remove(root.indiceDe(destino))
            modelo.append(fila)
            root.seleccion = nueva
        } else {
            root.sacarDeDonde(archivo, origen)
            root.meterEnGrupo(destino, archivo)
        }
        root.conciliar()
    }
    function deshacerGrupo(clave) {
        var i = root.indiceDe(clave)
        if (i < 0) return
        var m = modelo.get(i)
        var l = root.miembrosDe(m), c = m.col, f = m.fila, tam = m.tam
        if (root.grupoAbierto === clave) root.grupoAbierto = ""
        if (root.panelClave === clave) root.panelClave = ""
        if (root.seleccion === clave) root.seleccion = ""
        if (root.sobreClave === clave) root.sobreClave = ""
        barraElemento.ultimo = null
        modelo.remove(i)
        var t = root.tamCeldas("icono", tam)
        for (var n of l) {
            var cl = root.prefijoIcono + n
            var d = root.posicionLibre(cl, c, f, t[0], t[1])
            if (d) modelo.append({ clave: cl, tipo: "icono", col: d.col, fila: d.fila, tam: tam, op: "{}" })
        }
        root.conciliar()
        if (!root.editando) root.guardar()
    }
    function alternarGrupo(clave) {
        root.cerrarMenu()
        root.panelClave = ""
        root.catalogoAbierto = false
        root.grupoAbierto = root.grupoAbierto === clave ? "" : clave
        root.actualizarBlur()
    }
    function cerrarGrupo() { root.grupoAbierto = ""; root.actualizarBlur() }
    function puntoEnPanelGrupo(x, y) {
        var it = cargaGrupo.item
        if (!it) return false
        return x >= cargaGrupo.x && x <= cargaGrupo.x + it.width && y >= cargaGrupo.y && y <= cargaGrupo.y + it.height
    }

    // ----- Arrastre sobre otros iconos -----
    // El cursor debe estar en la parte central del destino: así, pasar de largo no agrupa
    function marcarObjetivo(x, y, excluir) {
        var nuevo = ""
        for (var i = 0; i < repetidor.count && nuevo === ""; i++) {
            var it = repetidor.itemAt(i)
            if (!it || it.clave === excluir || (it.tipo !== "icono" && it.tipo !== "grupo")) continue
            var mx = it.width * 0.2, my = it.height * 0.2
            if (x >= it.x + mx && x <= it.x + it.width - mx && y >= it.y + my && y <= it.y + it.height - my) nuevo = it.clave
        }
        if (nuevo === root.objetivoGrupo) return
        root.objetivoGrupo = nuevo
        root.objetivoListo = false
        if (nuevo !== "") relojGrupo.restart()
        else relojGrupo.stop()
    }
    Timer {
        id: relojGrupo
        interval: root.esperaGrupo
        onTriggered: root.objetivoListo = root.objetivoGrupo !== ""
    }
    function terminarArrastre() {
        relojGrupo.stop()
        root.objetivoGrupo = ""
        root.objetivoListo = false
        root.fantasma = null
        root.arrastreElemento = false
        root.arrastreSobrePanel = false
    }

    // ----- Sacar un icono del panel del grupo -----
    function empezarSacar(archivo) {
        root.miembroArrastrado = archivo
        root.arrastreElemento = true
    }
    function moverSacar(x, y) {
        root.flotanteX = x
        root.flotanteY = y
        if (root.puntoEnPanelGrupo(x, y)) {
            root.fantasma = null
            root.destinoSacar = null
            root.marcarObjetivo(-1000, -1000, "")
            return
        }
        var t = root.tamCeldas("icono", "M")
        var cl = root.prefijoIcono + root.miembroArrastrado
        var d = root.posicionLibre(cl, root.colDe(x - t[0] * root.paso / 2), root.filaDe(y - t[1] * root.paso / 2), t[0], t[1])
        if (d) {
            root.destinoSacar = d
            root.fantasma = { col: d.col, fila: d.fila, w: t[0], h: t[1] }
        }
        root.marcarObjetivo(x, y, root.grupoAbierto)
    }
    function soltarSacar(x, y, origen) {
        var archivo = root.miembroArrastrado
        var dentro = root.puntoEnPanelGrupo(x, y)
        var objetivo = root.objetivoListo ? root.objetivoGrupo : ""
        var d = root.destinoSacar
        root.cancelarSacar()
        if (dentro) return
        // Después: el panel puede desaparecer con el grupo mientras aún se atiende este clic
        Qt.callLater(() => {
            if (objetivo !== "") { root.agrupar(archivo, objetivo, origen); return }
            if (!d) { root.avisar("No hay hueco para sacarlo"); return }
            root.sacarDeDonde(archivo, origen)
            modelo.append({ clave: root.prefijoIcono + archivo, tipo: "icono", col: d.col, fila: d.fila, tam: "M", op: "{}" })
            root.conciliar()
        })
    }
    function cancelarSacar() {
        root.miembroArrastrado = ""
        root.destinoSacar = null
        root.terminarArrastre()
    }

    function elegirDialogo(id) {
        if (id === "seguir") root.dialogo = ""
        else if (id === "fondo") root.salir(true, "fondo")
        else if (id === "global") root.salir(true, "global")
        else if (id === "descartar") root.salir(false, "")
        else if (id === "borrar") root.borrarPropio()
    }

    // ===== Quitar =====
    // Acceso .desktop en edición: se oculta y se borra al pulsar Listo (Cancelar lo devuelve).
    // Archivo real: siempre con confirmación y a la papelera.
    function pedirQuitar(archivo, x, y) {
        var e = root.entradaDe(archivo)
        if (archivo.endsWith(".desktop")) {
            var oc = Object.assign({}, root.ocultos)
            oc[archivo] = true
            root.ocultos = oc
            root.quitados = root.quitados.concat([archivo])
            if (root.sobreClave === root.prefijoIcono + archivo) root.sobreClave = ""
            if (root.seleccion === root.prefijoIcono + archivo) root.seleccion = ""
            if (root.panelClave === root.prefijoIcono + archivo) root.panelClave = ""
            barraElemento.ultimo = null
            Qt.callLater(root.conciliar)
            return
        }
        root.abrirMenu({ fileName: archivo, filePath: root.carpeta + "/" + archivo, entrada: e, nombre: archivo }, x, y)
        root.confirmarQuitar = true
    }

    // ===== Añadir apps =====
    function anadirDesdeSelector(id) {
        root.anadirApp(id, root.destinoApps !== "" ? { grupo: root.destinoApps } : null)
    }
    readonly property var apps: !root.catalogoAbierto || root.pestana !== "apps" ? [] : DesktopEntries.applications.values
        .filter(a => !a.noDisplay && !root.appsOcultas.some(p => a.name.startsWith(p)))
        .sort((a, b) => a.name.localeCompare(b.name))
    function sinAcentos(t) { return t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase() }
    readonly property var appsVisibles: {
        var f = root.sinAcentos(root.filtroApps.trim())
        if (f === "") return root.apps
        return root.apps.filter(a => root.sinAcentos(a.name + " " + (a.genericName || "")).includes(f))
    }
    readonly property var gruposActuales: {
        root.version
        var l = []
        for (var i = 0; i < modelo.count; i++) {
            var m = modelo.get(i)
            if (m.tipo === "grupo") l.push({ clave: m.clave, nombre: JSON.parse(m.op).nombre || "Grupo" })
        }
        return l
    }
    property int version: 0                 // sube cuando cambia el modelo (get() no avisa)
    Connections {
        target: modelo
        function onCountChanged() { root.version++ }
        function onDataChanged() { root.version++ }
    }
    function anadirApp(id, destino) {
        var n = id + ".desktop"
        var oc = Object.assign({}, root.ocultos)
        var p = Object.assign({}, root.pendientes)
        if (destino) p[n] = destino
        else delete p[n]
        root.pendientes = p
        if (oc[n]) {
            // Estaba quitado en esta misma edición: basta con volver a mostrarlo
            delete oc[n]
            root.ocultos = oc
            root.quitados = root.quitados.filter(x => x !== n)
            Qt.callLater(root.conciliar)
            return
        }
        if (root.carpetas[n] !== undefined) { root.avisar("Ya está en el escritorio"); return }
        if (root.editando) root.creados = root.creados.concat([n])
        root.colaCopias = root.colaCopias.concat([id])
        if (!pCopiar.running) root.siguienteCopia()
    }
    function siguienteCopia() {
        if (root.colaCopias.length === 0) return
        var id = root.colaCopias[0]
        root.colaCopias = root.colaCopias.slice(1)
        pCopiar.idActual = id
        // id y carpeta van como argumentos, nunca dentro del texto del comando
        pCopiar.command = ["sh", "-c",
            'src=$(find -L "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications ' +
            '"$HOME/.local/share/flatpak/exports/share/applications" /var/lib/flatpak/exports/share/applications ' +
            '-name "$1.desktop" 2>/dev/null | head -n1); [ -n "$src" ] && mkdir -p "$2" && cp -L -- "$src" "$2/$1.desktop"',
            "sh", id, root.carpeta]
        pCopiar.running = true
    }
    Process {
        id: pCopiar
        property string idActual: ""
        onExited: code => {
            if (code !== 0) root.avisar("No se pudo añadir " + pCopiar.idActual)
            root.siguienteCopia()
        }
    }
    Process {
        id: pPapelera
        property string nombre: ""
        onExited: code => {
            if (code !== 0) Quickshell.execDetached(["notify-send", "Escritorio", "No se pudo mover a la papelera: " + pPapelera.nombre])
        }
    }

    // ----- Arrastrar desde el cajón (Mod+A): el cajón sigue el cursor y avisa aquí por IPC -----
    property bool paraArrastreApp: false
    function empezarArrastreApp() {
        if (root.editando) return
        root.paraArrastreApp = true
        pEntrar.running = true
    }
    function volverTrasArrastre() {
        root.paraArrastreApp = false
        if (root.volverA >= 0) volverLuego.restart()
    }
    Timer {
        id: volverLuego
        interval: 900                       // deja ver dónde cayó antes de volver a las ventanas
        onTriggered: if (root.volverA >= 0) pSalir.running = true
    }
    function soltarApp(id, xPantalla, yPantalla) {
        var t = root.tamCeldas("icono", "M")
        var alto = ventana.screen ? ventana.screen.height : ventana.height
        var y = yPantalla - (alto - ventana.height)
        var c = root.colDe(xPantalla - t[0] * root.paso / 2)
        var f = root.filaDe(y - t[1] * root.paso / 2)
        var n = id + ".desktop"
        var cl = root.prefijoIcono + n
        if (root.carpetas[n] !== undefined && root.indiceDe(cl) >= 0) {
            var d = root.posicionLibre(cl, c, f, t[0], t[1])
            if (d) root.colocar(cl, d.col, d.fila)
            if (!root.editando) root.guardar()
        } else {
            root.anadirApp(id, { col: c, fila: f })
        }
        root.volverTrasArrastre()
    }

    // ===== Catálogo =====
    function existe(tipo) {
        modelo.count
        for (var i = 0; i < modelo.count; i++) if (modelo.get(i).tipo === tipo) return true
        return false
    }
    function anadirWidget(tipo) {
        if (root.existe(tipo)) return false
        var t = root.tamCeldas(tipo, "M")
        var d = root.posicionLibre(tipo, Math.floor((root.columnas - t[0]) / 2), Math.floor((root.filas - t[1]) / 2), t[0], t[1])
        if (!d) { root.avisar("No hay espacio para añadirlo"); return false }
        modelo.append({ clave: tipo, tipo: tipo, col: d.col, fila: d.fila, tam: "M", op: "{}" })
        root.seleccion = tipo
        return true
    }
    function quitarWidget(clave) {
        var i = root.indiceDe(clave)
        if (i < 0 || modelo.get(i).tipo === "icono") return
        if (modelo.get(i).tipo === "grupo") { root.deshacerGrupo(clave); return }
        if (root.panelClave === clave) root.panelClave = ""
        if (root.seleccion === clave) root.seleccion = ""
        if (root.sobreClave === clave) root.sobreClave = ""
        barraElemento.ultimo = null
        modelo.remove(i)
        root.conciliar()
    }

    // ===== Desenfoque real: la región de cada elemento con tarjeta =====
    function actualizarBlur() { esperaBlur.restart() }
    Timer {
        id: esperaBlur
        interval: 0
        onTriggered: {
            var l = []
            for (var i = 0; i < repetidor.count; i++) {
                var it = repetidor.itemAt(i)
                if (it && it.conTarjeta) l.push(it.regionBlur)
            }
            if (cargaGrupo.item) l.push(ventana.zonaGrupo)
            root.regionesBlur = l
        }
    }

    function avisar(t) { root.aviso = t; quitarAviso.restart() }
    Timer { id: quitarAviso; interval: 2500; onTriggered: root.aviso = "" }

    // ===== Entrar y salir del modo edición =====
    property int volverA: -1                // id del workspace al que hay que regresar
    property int wsEdicion: -1              // id del workspace vacío usado para editar

    function personalizar() {
        if (root.editando) { root.pedirSalida(); return }
        root.cerrarMenu()
        pEntrar.running = true
    }
    // Con cambios, pregunta dónde guardarlos; sin cambios, sale sin más
    function pedirSalida() {
        if (!root.editando) return
        root.soltarTexto()
        root.catalogoAbierto = false
        root.cerrarMenu()
        if (root.hayCambios()) root.dialogo = "salir"
        else root.salir(true, "")
    }
    function empezar() {
        // Si un cambio de fondo estaba a mitad, se termina ya: se edita el diseño correcto
        if (mitadFundido.running) mitadFundido.stop()
        if (root.cargadoPara !== root.fondoActual) {
            root.cargadoPara = root.fondoActual
            root.cargar(root.disenoDe(root.fondoActual))
            root.conciliar()
        }
        root.opacidadElementos = 1
        root.cambiando = false
        root.dialogo = ""
        root.alEntrar = root.instantanea()
        root.seleccion = ""
        root.panelClave = ""
        root.sobreClave = ""
        root.catalogoAbierto = false
        root.escribiendo = false
        root.grupoAbierto = ""
        root.ocultos = {}
        root.quitados = []
        root.creados = []
        root.editando = true
    }
    function salir(conservar, destino) {
        if (!root.editando) return
        root.dialogo = ""
        root.soltarTexto()
        root.fantasma = null
        root.seleccion = ""
        root.panelClave = ""
        root.sobreClave = ""
        root.sobreBarra = false
        root.catalogoAbierto = false
        root.grupoAbierto = ""
        root.cancelarSacar()
        root.cerrarMenu()
        if (conservar) {
            // Los accesos quitados se borran ahora; siguen ocultos hasta que el archivo ya no esté
            for (var q of root.quitados) Quickshell.execDetached(["rm", "--", root.carpeta + "/" + q])
            if (root.hayCambios()) root.guardar(destino)
        } else {
            root.cargar(root.alEntrar)
            // Cancelar: vuelven los quitados y se borran solo los accesos creados en esta edición
            var oc = {}
            for (var c of root.creados) {
                oc[c] = true
                Quickshell.execDetached(["rm", "--", root.carpeta + "/" + c])
            }
            root.ocultos = oc
            root.pendientes = {}
        }
        root.quitados = []
        root.creados = []
        root.editando = false
        root.conciliar()                    // un archivo que llegó durante la edición no se pierde al cancelar
        if (root.volverA >= 0) pSalir.running = true
        root.revisarFondo()                 // el fondo pudo cambiar durante la edición
    }

    // Workspace vacío en la misma pantalla (niri siempre deja uno al final)
    Process {
        id: pEntrar
        command: ["niri", "msg", "--json", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.volverA = -1
                root.wsEdicion = -1
                try {
                    var ws = JSON.parse(text)
                    var actual = ws.find(w => w.is_focused)
                    if (actual && actual.active_window_id !== null) {
                        var vacios = ws.filter(w => w.output === actual.output && w.active_window_id === null)
                        vacios.sort((a, b) => a.idx - b.idx)
                        if (vacios.length > 0) {
                            root.volverA = actual.id
                            root.wsEdicion = vacios[0].id
                            Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(vacios[0].idx)])
                        }
                    }
                } catch (e) {
                    console.warn("escritorio: no pude leer los workspaces:", e)
                }
                if (root.paraArrastreApp) root.paraArrastreApp = false
                else root.empezar()
            }
        }
    }
    // Vuelve solo si sigue en el workspace de edición (si el usuario ya se fue, no lo mueve)
    Process {
        id: pSalir
        command: ["niri", "msg", "--json", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var ws = JSON.parse(text)
                    var actual = ws.find(w => w.is_focused)
                    var destino = ws.find(w => w.id === root.volverA)
                    if (actual && destino && actual.id === root.wsEdicion)
                        Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(destino.idx)])
                } catch (e) {
                    console.warn("escritorio: no pude volver al workspace:", e)
                }
                root.volverA = -1
                root.wsEdicion = -1
            }
        }
    }

    // ===== ¿Hay una ventana que tapa el escritorio? (misma regla que el módulo "fondo") =====
    Process {
        id: eventos
        command: ["niri", "msg", "--json", "event-stream"]
        running: true
        stdout: SplitParser {
            onRead: dato => revisar.restart()
        }
        onRunningChanged: if (!running) reintentar.start()
    }
    Timer {
        id: reintentar
        interval: 3000
        onTriggered: eventos.running = true
    }
    Timer {
        id: revisar
        interval: 250
        onTriggered: {
            if (consulta.running) { revisar.restart(); return }
            consulta.running = true
        }
    }
    Process {
        id: consulta
        command: ["sh", "-c", "niri msg --json workspaces; niri msg --json windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var lineas = text.trim().split("\n")
                    var ws = JSON.parse(lineas[0])
                    var ventanas = JSON.parse(lineas[1])
                    var salida = ventana.screen ? ventana.screen.name : ""
                    var ids = ws.filter(w => w.is_active && (salida === "" || w.output === salida)).map(w => w.id)
                    var W = ventana.screen ? ventana.screen.width : ventana.width
                    var H = ventana.screen ? ventana.screen.height : ventana.height
                    var vis = ventanas.filter(v => ids.indexOf(v.workspace_id) >= 0 && v.layout)
                    var flotante = 0
                    vis.forEach(v => {
                        if (v.is_floating && v.layout.tile_pos_in_workspace_view !== null)
                            flotante = Math.max(flotante, v.layout.tile_size[0] * v.layout.tile_size[1])
                    })
                    var cols = {}
                    vis.forEach(v => {
                        var pos = v.layout.pos_in_scrolling_layout
                        if (v.is_floating || !pos) return
                        var k = v.workspace_id + ":" + pos[0]
                        var c = cols[k] || { w: 0, h: 0 }
                        c.w = Math.max(c.w, v.layout.tile_size[0])
                        c.h += v.layout.tile_size[1]
                        cols[k] = c
                    })
                    var ancho = 0, alto = 0
                    Object.keys(cols).forEach(k => {
                        ancho += cols[k].w + 16
                        alto = Math.max(alto, cols[k].h)
                    })
                    var mosaico = Math.min(W, ancho) * Math.min(H, alto)
                    root.cobertura = Math.min(1, Math.max(mosaico, flotante) / Math.max(1, W * H))
                    root.tapado = root.cobertura >= 0.85
                } catch (e) {
                    console.warn("escritorio: no pude leer niri:", e)
                }
            }
        }
    }

    // ===== Menú de clic derecho =====
    property var menu: null          // { fileName, filePath, entrada, nombre } o { escritorio: true }
    property real menuX: 0
    property real menuY: 0
    property bool confirmarQuitar: false

    function abrirMenu(el, x, y) {
        root.confirmarQuitar = false
        root.menuX = x
        root.menuY = y
        root.menu = el
    }

    function cerrarMenu() {
        root.menu = null
        root.confirmarQuitar = false
    }

    function abrir(el) {
        root.abrirArchivo(el.fileName)
        root.cerrarMenu()
    }

    function opciones(el) {
        if (!el) return []
        if (el.escritorio)
            return [ { id: "personalizar", texto: "Personalizar escritorio", icono: 0xF03EB } ]
                .concat(root.tienePropio ? [ { id: "quitar", texto: "Volver al diseño general", icono: 0xF0450, peligro: true } ] : [])
        if (el.grupo)
            return [ { id: "abrirGrupo", texto: "Abrir", icono: 0xF0415 },
                     { id: "deshacerGrupo", texto: "Deshacer grupo", icono: 0xF0237 } ]
        if (el.fileName.endsWith(".desktop"))
            return [ { id: "abrir", texto: "Abrir", icono: 0xF0415 },
                     { id: "quitar", texto: "Quitar del escritorio", icono: 0xF01B4, peligro: true } ]
        return [ { id: "abrir", texto: "Abrir", icono: 0xF0415 },
                 { id: "carpeta", texto: "Mostrar en carpeta", icono: 0xF024B },
                 { id: "quitar", texto: "Quitar del escritorio", icono: 0xF01B4, peligro: true } ]
    }

    function elegir(el, id) {
        if (id === "abrir") root.abrir(el)
        else if (id === "carpeta") { Quickshell.execDetached(["dolphin", "--select", el.filePath]); root.cerrarMenu() }
        else if (id === "quitar") root.confirmarQuitar = true
        else if (id === "personalizar") root.personalizar()
        else if (id === "abrirGrupo") { root.alternarGrupo(el.grupo); root.grupoAbierto = el.grupo }
        else if (id === "deshacerGrupo") { var g = el.grupo; root.cerrarMenu(); root.deshacerGrupo(g) }
    }

    // Acceso directo (.desktop): se borra solo el acceso, la app no se desinstala.
    // Archivo o carpeta real: a la papelera, nunca se borra para siempre.
    function quitarAcceso(el) {
        if (el && el.escritorio) { root.borrarPropio(); return }
        if (el && el.filePath && el.filePath.startsWith(root.carpeta + "/")) {
            if (el.fileName.endsWith(".desktop")) {
                Quickshell.execDetached(["rm", "--", el.filePath])
            } else {
                pPapelera.nombre = el.fileName
                pPapelera.command = ["gio", "trash", "--", el.filePath]
                pPapelera.running = true
            }
        }
        root.cerrarMenu()
    }

    Component.onCompleted: { Quickshell.watchFiles = false; revisar.restart() }

    // ===================================================================
    PanelWindow {
        id: ventana
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Normal   // se coloca bajo la barra; no reserva espacio propio
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "escritorio"
        WlrLayershell.keyboardFocus: root.editando || root.escribiendo ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        BackgroundEffect.blurRegion: root.usarBlur && !root.cambiando && root.regionesBlur.length > 0 ? zonaBlur : null
        property Region zonaBlur: Region { regions: root.regionesBlur }
        property Region zonaGrupo: Region { item: cargaGrupo.item; radius: 20 }

        Item {
            id: escena
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: {
                if (root.dialogo !== "") root.dialogo = ""
                else if (root.catalogoAbierto) root.catalogoAbierto = false
                else if (root.grupoAbierto !== "") root.cerrarGrupo()
                else if (root.panelClave !== "") root.panelClave = ""
                else if (root.editando) root.pedirSalida()
            }
            Keys.onReturnPressed: if (root.editando && root.dialogo === "") root.pedirSalida()
            Keys.onEnterPressed: if (root.editando && root.dialogo === "") root.pedirSalida()

            // El panel de un grupo se cierra si el cursor se va a una ventana. Este detector vive en el
            // padre de todo: en un elemento de delante bloquearía el cursor de lo que hay debajo.
            HoverHandler {
                enabled: root.grupoAbierto !== "" && !root.editando
                onHoveredChanged: hovered ? cierreGrupo.stop() : cierreGrupo.restart()
            }
            Timer {
                id: cierreGrupo
                interval: 900
                onTriggered: root.cerrarGrupo()
            }

            // Hueco del escritorio: clic derecho = menú; clic = cierra menú / quita la selección
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    root.cerrarMenu()
                    root.cerrarGrupo()
                    if (root.editando) { root.soltarTexto(); root.seleccion = ""; root.panelClave = ""; root.catalogoAbierto = false; return }
                    if (root.escribiendo) { root.escribiendo = false; root.soltarTexto() }
                    if (mouse.button === Qt.RightButton) root.abrirMenu({ escritorio: true, nombre: "Escritorio" }, mouse.x, mouse.y)
                    else root.cerrarMenu()
                }
            }

            // ---------- Velo y cuadrícula del modo edición ----------
            Item {
                anchors.fill: parent
                opacity: root.editando ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 180 } }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(colores.surface.r, colores.surface.g, colores.surface.b, 0.35)
                }
                Canvas {
                    id: puntos
                    anchors.fill: parent
                    readonly property color color: colores.surfaceText
                    onColorChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        var g = getContext("2d")
                        g.clearRect(0, 0, width, height)
                        g.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.3)
                        for (var f = 0; f <= root.filas; f++)
                            for (var c = 0; c <= root.columnas; c++)
                                g.fillRect(root.xDe(c) - 1, root.yDe(f) - 1, 2, 2)
                    }
                }
                // Adónde caerá lo que se arrastra
                Rectangle {
                    visible: root.fantasma !== null && root.objetivoGrupo === ""
                    x: root.fantasma ? root.xDe(root.fantasma.col) : 0
                    y: root.fantasma ? root.yDe(root.fantasma.fila) : 0
                    width: root.fantasma ? root.fantasma.w * root.paso : 0
                    height: root.fantasma ? root.fantasma.h * root.paso : 0
                    radius: 16
                    color: Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, 0.22)
                    border.color: colores.primary
                    border.width: 2
                    Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                }
            }

            // ---------- Elementos ----------
            Item {
                id: capaElementos
                anchors.fill: parent
                z: root.arrastreElemento ? 180 : 0     // lo que se arrastra pasa por encima de los paneles
                opacity: root.opacidadElementos         // fundido al cambiar de diseño
                Behavior on opacity { NumberAnimation { duration: root.duracionFundido; easing.type: Easing.InOutQuad } }
                Repeater {
                    id: repetidor
                    model: modelo
                    delegate: Elemento {
                        raiz: root
                        tema: colores
                    }
                    onItemAdded: root.actualizarBlur()
                    onItemRemoved: root.actualizarBlur()
                }
            }

            // ---------- Barra del modo edición ----------
            Rectangle {
                id: barraEdicion
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.editando ? 14 : -height - 8
                z: 100
                width: filaBarra.width + 28
                height: 52
                radius: 26
                color: Qt.rgba(colores.surface.r, colores.surface.g, colores.surface.b, 0.96)
                border.color: Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, 0.6)
                border.width: 1.5
                visible: root.editando || y > -height - 6
                Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Row {
                    id: filaBarra
                    anchors.centerIn: parent
                    spacing: 8

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        rightPadding: 12
                        Text {
                            text: "Personalizar escritorio · " + (root.tienePropio ? "diseño de este fondo" : "diseño general")
                            font.family: root.fuente
                            font.pixelSize: 13
                            font.bold: true
                            color: colores.surfaceText
                        }
                        Text {
                            width: Math.min(implicitWidth, 560)
                            elide: Text.ElideRight
                            text: root.aviso !== "" ? root.aviso
                                : root.sinHueco.length > 0 ? root.sinHueco.length + " sin hueco: libera espacio para verlos"
                                : "Arrastra para mover · S M L y ⚙ al pasar el cursor"
                            font.family: root.fuente
                            font.pixelSize: 10
                            color: root.aviso !== "" ? colores.primary : colores.surfaceText
                            opacity: root.aviso !== "" ? 1 : 0.7
                        }
                    }

                    Repeater {
                        model: (root.tienePropio ? [{ id: "general", texto: "Volver al general" }] : []).concat([
                            { id: "anadir", texto: "+ Añadir" },
                            { id: "restablecer", texto: "Restablecer" },
                            { id: "cancelar", texto: "Cancelar" },
                            { id: "listo", texto: "Listo", fuerte: true }
                        ])
                        delegate: Rectangle {
                            id: boton
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            width: textoBoton.width + 28
                            height: 34
                            radius: 17
                            color: boton.modelData.fuerte ? (zonaBoton.containsMouse ? Qt.lighter(colores.primary, 1.1) : colores.primary)
                                : Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, zonaBoton.containsMouse ? 0.28 : 0.14)
                            Text {
                                id: textoBoton
                                anchors.centerIn: parent
                                text: boton.modelData.texto
                                font.family: root.fuente
                                font.pixelSize: 12
                                font.bold: true
                                color: boton.modelData.fuerte ? colores.primaryText : colores.surfaceText
                            }
                            MouseArea {
                                id: zonaBoton
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (boton.modelData.id === "listo") root.pedirSalida()
                                    else if (boton.modelData.id === "cancelar") root.salir(false, "")
                                    else if (boton.modelData.id === "general") root.dialogo = "borrarPropio"
                                    else if (boton.modelData.id === "anadir") {
                                        root.panelClave = ""
                                        root.cerrarGrupo()
                                        root.filtroApps = ""
                                        root.catalogoAbierto = !root.catalogoAbierto
                                    }
                                    else {
                                        root.seleccion = ""
                                        root.panelClave = ""
                                        root.cerrarGrupo()
                                        root.cargar(root.disenoInicial)
                                        root.conciliar()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- Barra de ajustes del elemento: siempre por fuera de él ----------
            Rectangle {
                id: barraElemento
                readonly property var objetivo: root.claveBarra !== "" ? root.itemDe(root.claveBarra) : null
                property var ultimo: null
                onObjetivoChanged: if (objetivo) { ultimo = objetivo; recolocar(true) }
                onWidthChanged: recolocar(true)
                // Se queda quieta al cambiar el tamaño (para seguir pulsando S M L) salvo que tape al elemento
                property var sitio: ({ x: 0, y: 0 })
                function recolocar(siempre) {
                    if (!ultimo) return
                    if (!siempre && root.estorbo({ x: sitio.x, y: sitio.y, w: width, h: height }, ultimo, [root.zonaBarraEdicion()]) < 2) return
                    sitio = root.sitioBarra(ultimo, width, height)
                }
                Connections {
                    target: barraElemento.ultimo
                    function onXChanged() { barraElemento.recolocar(true) }
                    function onYChanged() { barraElemento.recolocar(true) }
                    function onWidthChanged() { barraElemento.recolocar(false) }
                    function onHeightChanged() { barraElemento.recolocar(false) }
                }
                x: sitio.x
                y: sitio.y
                z: 150
                width: filaAjustes.width + 8
                height: 34
                radius: 17
                color: Qt.rgba(colores.surface.r, colores.surface.g, colores.surface.b, 0.97)
                border.color: Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, 0.6)
                opacity: objetivo ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                HoverHandler {
                    onHoveredChanged: {
                        root.sobreBarra = hovered
                        if (hovered) perderSobre.stop()
                        else perderSobre.restart()
                    }
                }

                Row {
                    id: filaAjustes
                    anchors.centerIn: parent
                    spacing: 2
                    Repeater {
                        model: ["S", "M", "L"]
                        delegate: Rectangle {
                            id: chipTam
                            required property string modelData
                            readonly property bool activo: barraElemento.ultimo && barraElemento.ultimo.tam === modelData
                            width: 30
                            height: 26
                            radius: 13
                            color: activo ? colores.primary
                                : Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, zonaChipTam.containsMouse ? 0.25 : 0)
                            Text {
                                anchors.centerIn: parent
                                text: chipTam.modelData
                                font.family: root.fuente
                                font.pixelSize: 12
                                font.bold: true
                                color: chipTam.activo ? colores.primaryText : colores.surfaceText
                            }
                            MouseArea {
                                id: zonaChipTam
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.seleccion = barraElemento.ultimo.clave
                                    root.ponerTam(barraElemento.ultimo.clave, chipTam.modelData)
                                }
                            }
                        }
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 18
                        color: Qt.rgba(colores.surfaceText.r, colores.surfaceText.g, colores.surfaceText.b, 0.25)
                    }
                    Rectangle {
                        id: botonAjustes
                        readonly property bool abierto: barraElemento.ultimo && root.panelClave === barraElemento.ultimo.clave
                        width: 30
                        height: 26
                        radius: 13
                        color: abierto ? colores.primary
                            : Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, zonaAjustes.containsMouse ? 0.25 : 0)
                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF0493)
                            font.family: root.fuente
                            font.pixelSize: 15
                            color: botonAjustes.abierto ? colores.primaryText : colores.surfaceText
                        }
                        MouseArea {
                            id: zonaAjustes
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.seleccion = barraElemento.ultimo.clave
                                root.cerrarGrupo()
                                root.panelClave = botonAjustes.abierto ? "" : barraElemento.ultimo.clave
                            }
                        }
                    }
                    // Quitar: solo widgets (los iconos son archivos de la carpeta). Cancelar lo deshace.
                    Rectangle {
                        visible: !!barraElemento.ultimo && barraElemento.ultimo.tipo !== "icono"
                        width: 30
                        height: 26
                        radius: 13
                        color: zonaQuitar.containsMouse ? "#e05555" : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: root.fuente
                            font.pixelSize: 12
                            font.bold: true
                            color: zonaQuitar.containsMouse ? "white" : colores.surfaceText
                        }
                        MouseArea {
                            id: zonaQuitar
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.quitarWidget(barraElemento.ultimo.clave)
                        }
                    }
                }
            }

            // ---------- Panel de opciones del elemento ----------
            Loader {
                id: cargaPanel
                z: 160
                active: root.panelClave !== "" && root.itemDe(root.panelClave) !== null
                // Igual que la barra: quieto mientras no tape al elemento ni a la barra
                property var sitio: ({ x: 0, y: 0 })
                function recolocar(siempre) {
                    if (!item || !item.elemento) return
                    var b = { x: barraElemento.x, y: barraElemento.y, w: barraElemento.width, h: barraElemento.height }
                    if (!siempre && root.estorbo({ x: sitio.x, y: sitio.y, w: item.width, h: item.height }, item.elemento, [root.zonaBarraEdicion(), b]) < 2) return
                    sitio = root.sitioPanel(item.elemento, item.width, item.height, b)
                }
                onLoaded: recolocar(true)
                Connections {
                    target: barraElemento
                    function onXChanged() { cargaPanel.recolocar(false) }
                    function onYChanged() { cargaPanel.recolocar(false) }
                }
                Connections {
                    target: cargaPanel.item
                    function onHeightChanged() { cargaPanel.recolocar(false) }
                }
                Connections {
                    target: cargaPanel.item ? cargaPanel.item.elemento : null
                    function onWidthChanged() { cargaPanel.recolocar(false) }
                    function onHeightChanged() { cargaPanel.recolocar(false) }
                }
                x: sitio.x
                y: sitio.y
                sourceComponent: PanelOpciones {
                    raiz: root
                    tema: colores
                    elemento: root.itemDe(root.panelClave)
                    opacity: 0
                    Component.onCompleted: opacity = 1
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
            }

            // ---------- Panel de un grupo ----------
            Loader {
                id: cargaGrupo
                z: 165
                active: root.grupoAbierto !== "" && root.itemDe(root.grupoAbierto) !== null
                property var sitio: ({ x: 0, y: 0 })
                function recolocar() {
                    if (!item || !item.elemento) return
                    var el = item.elemento, g = 8, w = item.width, h = item.height
                    var cerca = (y) => Math.max(4, Math.min(ventana.height - h - 4, y))
                    var cx = Math.max(4, Math.min(ventana.width - w - 4, el.x + (el.width - w) / 2))
                    sitio = root.mejorSitio([
                        { x: el.x + el.width + g, y: cerca(el.y) },
                        { x: el.x - w - g, y: cerca(el.y) },
                        { x: cx, y: el.y + el.height + g },
                        { x: cx, y: el.y - h - g }
                    ], w, h, el, root.editando ? [root.zonaBarraEdicion()] : [])
                }
                onLoaded: { recolocar(); root.actualizarBlur() }
                onActiveChanged: root.actualizarBlur()
                Connections {
                    target: cargaGrupo.item
                    function onWidthChanged() { cargaGrupo.recolocar() }
                    function onHeightChanged() { cargaGrupo.recolocar() }
                }
                x: sitio.x
                y: sitio.y
                sourceComponent: PanelGrupo {
                    raiz: root
                    tema: colores
                    elemento: root.itemDe(root.grupoAbierto)
                    opacity: 0
                    Component.onCompleted: opacity = 1
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
            }

            // ---------- Icono que se saca de un grupo, siguiendo al cursor ----------
            Image {
                z: 190
                visible: root.miembroArrastrado !== ""
                x: root.flotanteX - width / 2
                y: root.flotanteY - height / 2
                width: 52
                height: 52
                sourceSize.width: 104
                sourceSize.height: 104
                source: root.miembroArrastrado !== "" ? root.fuenteIcono(root.miembroArrastrado) : ""
            }

            // ---------- "+ Añadir": apps instaladas y widgets ----------
            Rectangle {
                id: panelCatalogo
                z: 170
                anchors.horizontalCenter: parent.horizontalCenter
                y: 76
                width: 820
                height: columnaCatalogo.implicitHeight + 28
                radius: 20
                color: Qt.rgba(colores.surface.r, colores.surface.g, colores.surface.b, 0.97)
                border.color: Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, 0.6)
                border.width: 1.5
                opacity: root.catalogoAbierto ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: root.soltarTexto() }
                onVisibleChanged: if (visible && root.pestana === "apps") campoApps.forceActiveFocus()

                Column {
                    id: columnaCatalogo
                    x: 14
                    y: 14
                    width: parent.width - 28
                    spacing: 10

                    Row {
                        spacing: 6
                        Repeater {
                            model: [ { k: "apps", t: "Apps" }, { k: "widgets", t: "Widgets" } ]
                            delegate: Rectangle {
                                id: pest
                                required property var modelData
                                readonly property bool activa: root.pestana === pest.modelData.k
                                width: txtPest.width + 28
                                height: 30
                                radius: 15
                                color: pest.activa ? colores.primary
                                    : Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, zonaPest.containsMouse ? 0.25 : 0.12)
                                Text {
                                    id: txtPest
                                    anchors.centerIn: parent
                                    text: pest.modelData.t
                                    font.family: root.fuente; font.pixelSize: 12; font.bold: true
                                    color: pest.activa ? colores.primaryText : colores.surfaceText
                                }
                                MouseArea {
                                    id: zonaPest
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.pestana = pest.modelData.k
                                        if (pest.modelData.k === "apps") campoApps.forceActiveFocus()
                                        else root.soltarTexto()
                                    }
                                }
                            }
                        }
                    }

                    // ----- Apps -----
                    Rectangle {
                        visible: root.pestana === "apps"
                        width: parent.width
                        height: 34
                        radius: 12
                        color: Qt.rgba(colores.surfaceText.r, colores.surfaceText.g, colores.surfaceText.b, 0.08)
                        border.width: 1
                        border.color: campoApps.activeFocus ? colores.primary : Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, 0.35)
                        TextInput {
                            id: campoApps
                            objectName: "campoApps"
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            font.family: root.fuente; font.pixelSize: 13
                            color: colores.surfaceText
                            selectionColor: colores.primary
                            selectedTextColor: colores.primaryText
                            text: root.filtroApps
                            onTextEdited: root.filtroApps = text
                            Keys.onEscapePressed: { root.catalogoAbierto = false; root.soltarTexto() }
                            Keys.onReturnPressed: if (root.appsVisibles.length > 0) root.anadirDesdeSelector(root.appsVisibles[0].id)
                            Keys.onEnterPressed: if (root.appsVisibles.length > 0) root.anadirDesdeSelector(root.appsVisibles[0].id)
                        }
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            visible: campoApps.text === ""
                            text: "Buscar aplicación…"
                            font.family: root.fuente; font.pixelSize: 13
                            color: colores.surfaceText
                            opacity: 0.45
                        }
                    }
                    Flow {
                        visible: root.pestana === "apps"
                        width: parent.width
                        spacing: 6
                        Text {
                            height: 26
                            verticalAlignment: Text.AlignVCenter
                            rightPadding: 4
                            text: "Añadir a"
                            font.family: root.fuente; font.pixelSize: 11
                            color: colores.surfaceText
                        }
                        Repeater {
                            model: [{ clave: "", nombre: "Escritorio" }].concat(root.gruposActuales)
                            delegate: Rectangle {
                                id: dest
                                required property var modelData
                                readonly property bool activo: root.destinoApps === dest.modelData.clave
                                width: Math.min(txtDest.implicitWidth, 150) + 22
                                height: 26
                                radius: 13
                                color: dest.activo ? colores.primary
                                    : Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, zonaDest.containsMouse ? 0.25 : 0.1)
                                Text {
                                    id: txtDest
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, 150)
                                    elide: Text.ElideRight
                                    text: dest.modelData.nombre
                                    font.family: root.fuente; font.pixelSize: 11; font.bold: true
                                    color: dest.activo ? colores.primaryText : colores.surfaceText
                                }
                                MouseArea {
                                    id: zonaDest
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.destinoApps = dest.modelData.clave
                                }
                            }
                        }
                    }
                    GridView {
                        id: rejillaApps
                        visible: root.pestana === "apps"
                        width: parent.width
                        height: root.pestana === "apps" ? 3 * cellHeight : 0
                        cellWidth: Math.floor(width / 7)
                        cellHeight: 108
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.appsVisibles
                        delegate: Item {
                            id: ca
                            required property var modelData
                            readonly property bool puesta: root.esArchivoVisible(ca.modelData.id + ".desktop")
                            width: rejillaApps.cellWidth
                            height: rejillaApps.cellHeight
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                radius: 12
                                color: Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, zonaApp.containsMouse && !ca.puesta ? 0.22 : 0)
                            }
                            // Arriba fija (no centrada): un nombre en dos líneas no desalinea el icono
                            Column {
                                x: 6
                                y: 18
                                width: parent.width - 12
                                spacing: 4
                                opacity: ca.puesta ? 0.45 : 1
                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 44; height: 44
                                    sourceSize.width: 88
                                    sourceSize.height: 88
                                    asynchronous: true
                                    source: Quickshell.iconPath(ca.modelData.icon, "application-x-executable")
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    text: ca.modelData.name
                                    font.family: root.fuente; font.pixelSize: 10
                                    color: colores.surfaceText
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    visible: ca.puesta
                                    text: "Ya está"
                                    font.family: root.fuente; font.pixelSize: 9
                                    color: colores.primary
                                }
                            }
                            MouseArea {
                                id: zonaApp
                                anchors.fill: parent
                                enabled: !ca.puesta
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.anadirDesdeSelector(ca.modelData.id)
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: rejillaApps.count === 0
                            text: "Sin resultados"
                            font.family: root.fuente; font.pixelSize: 12
                            color: colores.surfaceText
                            opacity: 0.6
                        }
                    }

                    // ----- Widgets -----
                    Row {
                        id: filaCatalogo
                        visible: root.pestana === "widgets"
                        spacing: 8
                        Repeater {
                            model: root.catalogo
                            delegate: Rectangle {
                                id: ficha
                                required property var modelData
                                readonly property bool puesto: root.existe(ficha.modelData.tipo)
                                width: 148
                                height: 112
                                radius: 14
                                color: Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b,
                                               ficha.puesto ? 0.05 : zonaFicha.containsMouse ? 0.25 : 0.12)
                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - 16
                                    spacing: 3
                                    opacity: ficha.puesto ? 0.55 : 1
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: String.fromCodePoint(ficha.modelData.glifo); font.family: root.fuente; font.pixelSize: 26; color: colores.primary }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: ficha.modelData.nombre; font.family: root.fuente; font.pixelSize: 12; font.bold: true; color: colores.surfaceText }
                                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: ficha.puesto ? "Ya está añadido" : ficha.modelData.desc; font.family: root.fuente; font.pixelSize: 10; color: colores.surfaceText }
                                }
                                MouseArea {
                                    id: zonaFicha
                                    anchors.fill: parent
                                    enabled: !ficha.puesto
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (root.anadirWidget(ficha.modelData.tipo)) root.catalogoAbierto = false }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- Diálogo: dónde guardar al salir, o confirmar que se borra el diseño propio ----------
            Rectangle {
                id: veloDialogo
                anchors.fill: parent
                z: 195
                color: Qt.rgba(colores.surface.r, colores.surface.g, colores.surface.b, 0.55)
                opacity: root.dialogo !== "" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: root.dialogo = "" }

                Rectangle {
                    anchors.centerIn: parent
                    width: 440
                    height: colDialogo.implicitHeight + 36
                    radius: 22
                    color: Qt.rgba(colores.surface.r, colores.surface.g, colores.surface.b, 0.98)
                    border.color: Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, 0.6)
                    border.width: 1.5
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

                    Column {
                        id: colDialogo
                        x: 18
                        y: 18
                        width: parent.width - 36
                        spacing: 8

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: root.dialogo === "borrarPropio" ? "¿Volver al diseño general?" : "¿Dónde guardas este diseño?"
                            font.family: root.fuente; font.pixelSize: 15; font.bold: true
                            color: colores.surfaceText
                        }
                        Text {
                            width: parent.width
                            bottomPadding: 6
                            wrapMode: Text.Wrap
                            text: root.dialogo === "borrarPropio"
                                ? "Se borrará para siempre el diseño propio de «" + root.nombreFondo + "». No se puede deshacer con Cancelar."
                                : "Fondo actual: " + (root.nombreFondo || "ninguno")
                            font.family: root.fuente; font.pixelSize: 11
                            color: colores.surfaceText
                            opacity: 0.8
                        }

                        Repeater {
                            model: root.dialogo === "borrarPropio" ? [
                                { id: "borrar", t: "Borrar y usar el general", d: "", peligro: true },
                                { id: "seguir", t: "No borrar", d: "" }
                            ] : (root.fondoActual !== "" ? [
                                { id: "fondo", t: "Guardar solo para este fondo", d: "Los demás fondos no cambian.", fuerte: true }
                            ] : []).concat([
                                { id: "global", t: "Usar en todos los fondos", d: "Cambia el diseño general. Los fondos con diseño propio conservan el suyo." },
                                { id: "descartar", t: "Descartar los cambios", d: "Todo vuelve a como estaba." },
                                { id: "seguir", t: "Seguir editando", d: "" }
                            ])
                            delegate: Rectangle {
                                id: opD
                                required property var modelData
                                width: colDialogo.width
                                height: Math.max(40, colOp.implicitHeight + 16)
                                radius: 12
                                color: opD.modelData.fuerte ? (zonaOp.containsMouse ? Qt.lighter(colores.primary, 1.1) : colores.primary)
                                    : opD.modelData.peligro ? (zonaOp.containsMouse ? "#ff6b6b" : "#e05555")
                                    : Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, zonaOp.containsMouse ? 0.25 : 0.1)
                                Column {
                                    id: colOp
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 24
                                    spacing: 1
                                    Text {
                                        width: parent.width
                                        text: opD.modelData.t
                                        font.family: root.fuente; font.pixelSize: 12; font.bold: true
                                        color: opD.modelData.fuerte ? colores.primaryText : opD.modelData.peligro ? "white" : colores.surfaceText
                                    }
                                    Text {
                                        width: parent.width
                                        visible: opD.modelData.d !== ""
                                        wrapMode: Text.Wrap
                                        text: opD.modelData.d
                                        font.family: root.fuente; font.pixelSize: 10
                                        color: opD.modelData.fuerte ? colores.primaryText : colores.surfaceText
                                        opacity: 0.8
                                    }
                                }
                                MouseArea {
                                    id: zonaOp
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.elegirDialogo(opD.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            // ---------- Menú (crece desde donde se pidió) ----------
            Item {
                id: capaMenu
                anchors.fill: parent
                z: 200

                // Si el mouse sale del escritorio, el menú se cierra solo
                HoverHandler {
                    enabled: root.menu !== null      // activo todo el rato bloquearía el cursor de lo de debajo
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
                        NumberAnimation { duration: root.menu ? 150 : 120; easing.type: Easing.OutCubic }
                    }
                    Connections {
                        target: root
                        function onMenuChanged() { if (root.menu) cajaMenu.el = root.menu }
                    }

                    visible: escala > 0.01
                    scale: escala
                    opacity: Math.min(1, escala)
                    transformOrigin: Item.TopLeft
                    width: 204
                    height: colMenu.implicitHeight + 16
                    x: Math.max(4, Math.min(parent.width - width - 4, root.menuX))
                    y: Math.max(4, Math.min(parent.height - height - 4, root.menuY))
                    radius: 16
                    color: Qt.rgba(colores.surface.r, colores.surface.g, colores.surface.b, 0.96)
                    border.color: Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, 0.6)
                    border.width: 1.5

                    // Que un clic en el marco no llegue al hueco de debajo
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

                    Column {
                        id: colMenu
                        x: 8
                        y: 8
                        width: parent.width - 16
                        spacing: 2

                        Text {
                            visible: !cajaMenu.el || !cajaMenu.el.escritorio
                            width: parent.width
                            leftPadding: 6
                            bottomPadding: 4
                            elide: Text.ElideRight
                            text: cajaMenu.el ? cajaMenu.el.nombre : ""
                            font.family: root.fuente
                            font.pixelSize: 11
                            font.bold: true
                            color: Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, 0.85)
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
                                color: Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, maOp.containsMouse ? 0.18 : 0)
                                Row {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    Text {
                                        text: String.fromCodePoint(op.modelData.icono)
                                        font.family: root.fuente
                                        font.pixelSize: 13
                                        color: op.modelData.peligro ? "#ff8a80" : colores.primary
                                    }
                                    Text {
                                        text: op.modelData.texto
                                        font.family: root.fuente
                                        font.pixelSize: 11
                                        color: colores.surfaceText
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
                            text: cajaMenu.el && cajaMenu.el.escritorio
                                ? "¿Borrar para siempre el diseño propio de este fondo y usar el general?"
                                : cajaMenu.el && cajaMenu.el.fileName && !cajaMenu.el.fileName.endsWith(".desktop")
                                ? "¿Mover a la papelera? El archivo se podrá recuperar desde ella."
                                : "¿Quitar este acceso del escritorio? La app no se desinstala."
                            font.family: root.fuente
                            font.pixelSize: 11
                            color: colores.surfaceText
                        }
                        Row {
                            visible: root.confirmarQuitar
                            topPadding: 6
                            spacing: 6
                            x: 4
                            Repeater {
                                model: [ { id: "no", texto: "Cancelar" },
                                         { id: "si", texto: cajaMenu.el && cajaMenu.el.escritorio ? "Borrar" : cajaMenu.el && cajaMenu.el.fileName && !cajaMenu.el.fileName.endsWith(".desktop") ? "Papelera" : "Quitar" } ]
                                delegate: Rectangle {
                                    id: bc
                                    required property var modelData
                                    width: (colMenu.width - 14) / 2
                                    height: 30
                                    radius: 10
                                    color: bc.modelData.id === "si" ? (maBc.containsMouse ? "#ff6b6b" : "#e05555")
                                        : Qt.rgba(colores.primary.r, colores.primary.g, colores.primary.b, maBc.containsMouse ? 0.3 : 0.15)
                                    Text {
                                        anchors.centerIn: parent
                                        text: bc.modelData.texto
                                        font.family: root.fuente
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: bc.modelData.id === "si" ? "white" : colores.surfaceText
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
    }

    IpcHandler {
        target: "escritorio"
        // Entra al modo edición; si ya está dentro, sale conservando (lo usa el atajo)
        function personalizar(): void { root.personalizar() }
        function listo(): void { root.pedirSalida() }
        function cancelar(): void { root.salir(false, "") }
        function elegirDialogo(id: string): void { root.elegirDialogo(id) }
        function info(): string {
            return JSON.stringify({ editando: root.editando, seleccion: root.seleccion, columnas: root.columnas,
                                    filas: root.filas, ancho: ventana.width, alto: ventana.height, tapado: root.tapado,
                                    cobertura: root.cobertura, pausado: root.pausado, volverA: root.volverA,
                                    wsEdicion: root.wsEdicion, cambios: root.editando ? root.hayCambios() : false,
                                    aviso: root.aviso, fondo: root.fondoActual, cargadoPara: root.cargadoPara, propio: root.tienePropio, cambiando: root.cambiando, dialogo: root.dialogo, propios: Object.keys(root.datos.fondos || {}), catalogo: root.catalogoAbierto, grupoAbierto: root.grupoAbierto, sitioGrupo: cargaGrupo.sitio, objetivo: root.objetivoGrupo, objetivoListo: root.objetivoListo, ocultos: root.ocultos, quitados: root.quitados, creados: root.creados, escribiendo: root.escribiendo, blur: root.usarBlur, regiones: root.regionesBlur.length, panel: root.panelClave, barra: root.claveBarra, sitioBarra: barraElemento.sitio, sitioPanel: cargaPanel.sitio,
                                    sinHueco: root.sinHueco, elementos: root.instantanea() })
        }
        // Para probar sin mouse
        function mover(clave: string, col: int, fila: int): string {
            var i = root.indiceDe(clave)
            if (i < 0) return "no existe " + clave
            var t = root.tamCeldas(modelo.get(i).tipo, modelo.get(i).tam)
            var d = root.posicionLibre(clave, col, fila, t[0], t[1])
            if (!d) return "sin espacio"
            root.colocar(clave, d.col, d.fila)
            return d.col + " " + d.fila
        }
        function tam(clave: string, t: string): string { return root.ponerTam(clave, t) ? "ok" : "sin espacio" }
        function opcion(clave: string, o: string, v: string): void {
            root.ponerOpcion(clave, o, v === "si" ? true : v === "no" ? false : v)
        }
        function panel(clave: string): void { root.seleccion = clave; root.panelClave = clave }
        function arrastreApp(accion: string): void {
            if (accion === "empezar") root.empezarArrastreApp()
            else root.volverTrasArrastre()
        }
        function soltarApp(id: string, x: int, y: int): void { root.soltarApp(id, x, y) }
        function anadirApp(id: string, grupo: string): void { root.anadirApp(id, grupo !== "-" ? { grupo: grupo } : null) }
        function abrirGrupo(clave: string): void { root.alternarGrupo(clave) }
        function agrupar(archivo: string, destino: string): void { root.agrupar(archivo, destino, "") }
        function anadir(tipo: string): string { return root.anadirWidget(tipo) ? "ok" : "no" }
        function quitarElemento(clave: string): void { root.quitarWidget(clave) }
        function blur(v: string): string { root.usarBlur = v === "si"; return "blur " + root.usarBlur + " regiones " + root.regionesBlur.length }
        function estadoWidget(clave: string): string {
            var it = root.itemDe(clave)
            if (!it || !it.contenido) return "no está"
            var c = it.contenido
            if (it.tipo === "clima") return JSON.stringify({ ciudad: c.ciudad, temp: c.datos ? c.datos.current.temperature_2m : null, fallo: c.fallo, antiguedad: c.antiguedad, horas: c.horas.length, dias: c.dias.length, resultados: c.resultados.length, activo: c.activo })
            if (it.tipo === "recordatorios") return JSON.stringify({ lista: c.lista, pendientes: c.pendientes, escribiendo: root.escribiendo })
            if (it.tipo === "musica") return JSON.stringify({ titulo: c.titulo, artista: c.artista, hay: !!c.jugador, suena: c.jugador ? c.jugador.isPlaying : false, pos: c.jugador ? c.jugador.position : 0, largo: c.jugador ? c.jugador.length : 0, activo: c.activo })
            if (it.tipo === "calendario") return JSON.stringify({ mes: c.primero, primerDia: c.primerDia, cab: c.cabeceras, hoyEn: c.celdas.findIndex(x => x.esHoy), activo: c.activo })
            return JSON.stringify({ activo: c.activo })
        }
        function saludoPara(h: int): string {
            var it = root.itemDe("reloj")
            return it && it.contenido ? it.contenido.saludoDe(h) : "sin reloj"
        }
        // Mide el reloj (para fijar sus tamaños)
        function medirReloj(): string {
            for (var i = 0; i < repetidor.count; i++) {
                var it = repetidor.itemAt(i)
                if (it && it.tipo === "reloj" && it.contenido)
                    return JSON.stringify({ caja: [it.width, it.height], contenido: [it.contenido.anchoContenido, it.contenido.altoContenido], activo: it.contenido.activo, hora: it.contenido.horaMostrada })
            }
            return "sin reloj"
        }
        // qs -c escritorio ipc call escritorio menu <n.º de icono>
        function menu(i: int): string {
            var w = null, n = 0
            for (var k = 0; k < repetidor.count; k++) {
                var it = repetidor.itemAt(k)
                if (it && it.tipo === "icono" && n++ === i) w = it
            }
            if (!w || !w.contenido) return "no hay icono " + i
            root.abrirMenu(w.contenido.datos(), w.x + w.width - 8, w.y + w.height - 8)
            return root.opciones(root.menu).map(o => o.texto).join(", ")
        }
        function quitar(): string { if (!root.menu) return "sin menú"; root.elegir(root.menu, "quitar"); return "confirmando: " + root.confirmarQuitar }
        function cerrar(): void { root.cerrarMenu() }
    }
}
