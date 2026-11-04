import Quickshell
import QtQuick

// Un elemento del escritorio sobre la cuadrícula. Fuera del modo edición solo muestra su contenido;
// en el modo edición se arrastra y encaja en la posición libre más cercana. La barra S M L · ⚙ y el panel
// de opciones viven en shell.qml, por fuera del elemento: nunca tapan su contenido.
Item {
    id: el

    // Del modelo
    required property string clave
    required property string tipo
    required property int col
    required property int fila
    required property string tam
    required property string op             // opciones guardadas, en JSON
    // De shell.qml
    required property var raiz
    required property var tema

    readonly property var celdas: raiz.tamCeldas(tipo, tam)
    readonly property int colVista: raiz.colEnVista(col, celdas[0])
    readonly property int filaVista: raiz.filaEnVista(fila, celdas[1])
    readonly property bool editando: raiz.editando
    readonly property bool seleccionado: raiz.seleccion === clave
    readonly property alias contenido: cargador.item
    readonly property var opciones: raiz.opcionesDe(tipo, op)
    readonly property string archivo: tipo === "icono" ? clave.slice(raiz.prefijoIcono.length) : ""
    readonly property string titulo: tipo === "icono" ? (contenido ? contenido.nombreVisible : "")
        : tipo === "grupo" ? (opciones.nombre || "Grupo")
        : (raiz.catalogo.find(c => c.tipo === tipo) || { nombre: tipo }).nombre
    // Desenfoque real de niri detrás de las tarjetas
    readonly property bool conTarjeta: contenido && contenido.usaTarjeta === true
    onConTarjetaChanged: raiz.actualizarBlur()
    onVisibleChanged: raiz.actualizarBlur()
    property Region regionBlur: Region { item: el; radius: 18 }

    readonly property bool activo: !raiz.pausado
    property bool arrastrando: false
    property real xArrastre: 0
    property real yArrastre: 0
    property real agarreX: 0
    property real agarreY: 0
    property var destino: null

    x: arrastrando ? xArrastre : raiz.xDe(colVista)
    y: arrastrando ? yArrastre : raiz.yDe(filaVista)
    width: celdas[0] * raiz.paso
    height: celdas[1] * raiz.paso
    z: arrastrando ? 50 : seleccionado ? 10 : 1

    Behavior on x { enabled: !el.arrastrando; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !el.arrastrando; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // ----- Contenido -----
    Component {
        id: cReloj
        WidgetReloj {
            tema: el.tema
            fuente: el.raiz.fuente
            tam: el.tam
            opciones: el.opciones
            activo: el.activo
        }
    }
    Component {
        id: cIcono
        WidgetIcono {
            tema: el.tema
            fuente: el.raiz.fuente
            carpeta: el.raiz.carpeta
            raiz: el.raiz
            archivo: el.archivo
            tam: el.tam
            opciones: el.opciones
            interactivo: !el.raiz.editando
            menuActual: el.raiz.menu
            onPideMenu: (datos, px, py) => {
                var p = mapToItem(el.parent, px, py)
                el.raiz.abrirMenu(datos, p.x, p.y)
            }
            onClicSimple: el.raiz.cerrarMenu()
        }
    }
    Component {
        id: cGrupo
        WidgetGrupo {
            tema: el.tema
            raiz: el.raiz
            fuente: el.raiz.fuente
            clave: el.clave
            tam: el.tam
            opciones: el.opciones
            interactivo: !el.raiz.editando
        }
    }
    Component {
        id: cCalendario
        WidgetCalendario {
            tema: el.tema
            fuente: el.raiz.fuente
            tam: el.tam
            opciones: el.opciones
            activo: el.activo
            interactivo: !el.raiz.editando
        }
    }
    Component {
        id: cClima
        WidgetClima {
            tema: el.tema
            fuente: el.raiz.fuente
            tam: el.tam
            opciones: el.opciones
            activo: el.activo
        }
    }
    Component {
        id: cRecordatorios
        WidgetRecordatorios {
            tema: el.tema
            fuente: el.raiz.fuente
            raiz: el.raiz
            tam: el.tam
            opciones: el.opciones
            interactivo: !el.raiz.editando
        }
    }
    Component {
        id: cMusica
        WidgetMusica {
            tema: el.tema
            fuente: el.raiz.fuente
            tam: el.tam
            opciones: el.opciones
            activo: el.activo
            interactivo: !el.raiz.editando
        }
    }
    Loader {
        id: cargador
        anchors.fill: parent
        sourceComponent: ({ reloj: cReloj, icono: cIcono, grupo: cGrupo, calendario: cCalendario, clima: cClima,
                            recordatorios: cRecordatorios, musica: cMusica })[el.tipo] || null
    }

    // ----- Solo en el modo edición -----
    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Qt.rgba(el.tema.surfaceText.r, el.tema.surfaceText.g, el.tema.surfaceText.b, el.arrastrando ? 0.1 : 0.05)
        border.width: el.seleccionado ? 2 : 1
        border.color: Qt.rgba(el.tema.primary.r, el.tema.primary.g, el.tema.primary.b, el.seleccionado ? 0.95 : 0.45)
        opacity: el.editando ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    // Destino de un grupo: se resalta mientras otro icono se mantiene encima (lleno = ya puedes soltar)
    Rectangle {
        anchors.fill: parent
        radius: 16
        visible: el.raiz.objetivoGrupo === el.clave
        color: Qt.rgba(el.tema.primary.r, el.tema.primary.g, el.tema.primary.b, el.raiz.objetivoListo ? 0.4 : 0.1)
        border.width: 2
        border.color: el.tema.primary
    }

    MouseArea {
        id: zonaArrastre
        anchors.fill: parent
        enabled: el.editando
        hoverEnabled: true
        // La barra de ajustes sigue al elemento bajo el cursor
        onContainsMouseChanged: el.raiz.marcarSobre(el.clave, containsMouse)
        cursorShape: el.arrastrando ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        preventStealing: true
        onPressed: mouse => {
            var p = mapToItem(el.parent, mouse.x, mouse.y)
            el.agarreX = p.x - el.x
            el.agarreY = p.y - el.y
            el.raiz.soltarTexto()
            if (el.raiz.panelClave !== el.clave) el.raiz.panelClave = ""
            el.raiz.seleccion = el.clave
            el.xArrastre = el.x
            el.yArrastre = el.y
            el.destino = { col: el.colVista, fila: el.filaVista }
        }
        onPositionChanged: mouse => {
            if (!pressed) return
            var p = mapToItem(el.parent, mouse.x, mouse.y)
            var nx = p.x - el.agarreX
            var ny = p.y - el.agarreY
            if (!el.arrastrando) {
                if (Math.abs(nx - el.x) + Math.abs(ny - el.y) < 5) return
                el.arrastrando = true
                el.raiz.panelClave = ""
                el.raiz.arrastreElemento = true
                if (el.raiz.grupoAbierto === el.clave) el.raiz.cerrarGrupo()
            }
            el.xArrastre = nx
            el.yArrastre = ny
            var d = el.raiz.posicionLibre(el.clave, el.raiz.colDe(nx), el.raiz.filaDe(ny), el.celdas[0], el.celdas[1])
            if (d) el.destino = d
            el.raiz.fantasma = { col: el.destino.col, fila: el.destino.fila, w: el.celdas[0], h: el.celdas[1] }
            // Solo un icono suelto puede agruparse: mantenerlo sobre otro icono o sobre un grupo
            if (el.tipo === "icono") {
                el.raiz.marcarObjetivo(p.x, p.y, el.clave)
                el.raiz.arrastreSobrePanel = el.raiz.puntoEnPanelGrupo(p.x, p.y)
            }
        }
        onReleased: mouse => {
            var p = mapToItem(el.parent, mouse.x, mouse.y)
            if (el.arrastrando) {
                var objetivo = el.raiz.objetivoListo ? el.raiz.objetivoGrupo : ""
                var alPanel = el.tipo === "icono" && el.raiz.puntoEnPanelGrupo(p.x, p.y) ? el.raiz.grupoAbierto : ""
                if (objetivo === "" && alPanel === "") el.raiz.colocar(el.clave, el.destino.col, el.destino.fila)
                el.arrastrando = false
                el.raiz.terminarArrastre()
                // Después: agrupar puede borrar este mismo elemento mientras aún se atiende su clic
                var archivo = el.archivo, raiz = el.raiz
                Qt.callLater(() => {
                    if (objetivo !== "") raiz.agrupar(archivo, objetivo, "")
                    else if (alPanel !== "") raiz.agrupar(archivo, alPanel, "")
                    else raiz.conciliar()
                })
            } else if (el.tipo === "grupo") {
                el.raiz.alternarGrupo(el.clave)
            }
        }
        onCanceled: { el.arrastrando = false; el.raiz.terminarArrastre() }
    }

    // Quitar: en la esquina del marco, sin tapar el icono
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        visible: el.editando && el.tipo === "icono" && !el.arrastrando
        width: 22
        height: 22
        radius: 11
        color: zonaMenos.containsMouse ? "#e05555" : Qt.rgba(el.tema.surface.r, el.tema.surface.g, el.tema.surface.b, 0.95)
        border.color: Qt.rgba(el.tema.primary.r, el.tema.primary.g, el.tema.primary.b, 0.6)
        Text {
            anchors.centerIn: parent
            text: "−"
            font.family: el.raiz.fuente
            font.pixelSize: 14
            font.bold: true
            color: zonaMenos.containsMouse ? "white" : el.tema.surfaceText
        }
        MouseArea {
            id: zonaMenos
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                var p = mapToItem(el.parent, mouse.x, mouse.y)
                el.raiz.pedirQuitar(el.archivo, p.x, p.y)
            }
        }
    }
}
