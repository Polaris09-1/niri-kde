import QtQuick

// Opciones propias de un elemento. Cada cambio se ve al momento; Cancelar en el modo edición los deshace.
// Un tipo nuevo solo tiene que añadir aquí sus filas.
Rectangle {
    id: p

    required property var raiz
    required property var tema
    required property var elemento              // el Elemento que se está ajustando

    readonly property var o: p.elemento ? p.elemento.opciones : ({})
    readonly property string tipo: p.elemento ? p.elemento.tipo : ""
    readonly property string clave: p.elemento ? p.elemento.clave : ""
    readonly property string fuente: p.raiz.fuente
    readonly property var climaW: p.tipo === "clima" && p.elemento ? p.elemento.contenido : null

    width: 284
    height: col.implicitHeight + 24
    radius: 18
    color: Qt.rgba(tema.surface.r, tema.surface.g, tema.surface.b, 0.97)
    border.color: Qt.rgba(tema.primary.r, tema.primary.g, tema.primary.b, 0.6)
    border.width: 1.5

    // Que un clic en el panel no llegue al hueco de debajo
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: p.raiz.soltarTexto() }

    component Fila: Item {
        id: fila
        property string texto: ""
        default property alias control: lugar.data
        width: col.width
        height: 34
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: fila.texto
            font.family: p.fuente
            font.pixelSize: 12
            color: p.tema.surfaceText
        }
        Item {
            id: lugar
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    component Interruptor: Rectangle {
        id: sw
        property string opcion: ""
        readonly property bool activo: p.o[sw.opcion] === true
        width: 40
        height: 22
        radius: 11
        color: sw.activo ? p.tema.primary : Qt.rgba(p.tema.surfaceText.r, p.tema.surfaceText.g, p.tema.surfaceText.b, 0.18)
        Behavior on color { ColorAnimation { duration: 140 } }
        Rectangle {
            width: 16
            height: 16
            radius: 8
            y: 3
            x: sw.activo ? 21 : 3
            color: sw.activo ? p.tema.primaryText : p.tema.surfaceText
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: p.raiz.ponerOpcion(p.clave, sw.opcion, !sw.activo)
        }
    }

    component Chips: Row {
        id: chips
        property var opciones: []               // [{ t: texto, activo: bool, elegir: función }]
        spacing: 2
        Repeater {
            model: chips.opciones
            delegate: Rectangle {
                id: chip
                required property var modelData
                width: Math.max(32, txt.width + 16)
                height: 26
                radius: 13
                color: chip.modelData.activo ? p.tema.primary
                    : Qt.rgba(p.tema.primary.r, p.tema.primary.g, p.tema.primary.b, zonaChip.containsMouse ? 0.25 : 0.1)
                Text {
                    id: txt
                    anchors.centerIn: parent
                    text: chip.modelData.t
                    font.family: p.fuente
                    font.pixelSize: 11
                    font.bold: true
                    color: chip.modelData.activo ? p.tema.primaryText : p.tema.surfaceText
                }
                MouseArea {
                    id: zonaChip
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chip.modelData.elegir()
                }
            }
        }
    }

    Column {
        id: col
        x: 14
        y: 12
        width: parent.width - 28
        spacing: 2

        Text {
            width: parent.width
            bottomPadding: 6
            elide: Text.ElideRight
            text: p.elemento ? p.elemento.titulo : ""
            font.family: p.fuente
            font.pixelSize: 13
            font.bold: true
            color: p.tema.primary
        }

        // ----- Reloj -----
        Fila { visible: p.tipo === "reloj"; texto: "Kanji del día"; Interruptor { opcion: "kanji" } }
        Fila { visible: p.tipo === "reloj"; texto: "Fecha"; Interruptor { opcion: "fecha" } }
        Fila { visible: p.tipo === "reloj"; texto: "Saludo"; Interruptor { opcion: "saludo" } }
        Fila { visible: p.tipo === "reloj"; texto: "Tarjeta de fondo"; Interruptor { opcion: "tarjeta" } }
        Fila {
            visible: p.tipo === "reloj"
            texto: "Formato"
            Chips {
                opciones: [
                    { t: "24 h", activo: p.o.h12 !== true, elegir: () => p.raiz.ponerOpcion(p.clave, "h12", false) },
                    { t: "12 h", activo: p.o.h12 === true, elegir: () => p.raiz.ponerOpcion(p.clave, "h12", true) }
                ]
            }
        }
        Fila {
            visible: p.tipo === "reloj"
            texto: "Nombre"
            Rectangle {
                width: 160
                height: 28
                radius: 10
                color: Qt.rgba(p.tema.surfaceText.r, p.tema.surfaceText.g, p.tema.surfaceText.b, 0.08)
                border.width: 1
                border.color: campo.activeFocus ? p.tema.primary
                    : Qt.rgba(p.tema.primary.r, p.tema.primary.g, p.tema.primary.b, 0.35)
                TextInput {
                    id: campo
                    objectName: "campoNombre"
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    maximumLength: 24
                    selectByMouse: true
                    font.family: p.fuente
                    font.pixelSize: 12
                    color: p.tema.surfaceText
                    selectionColor: p.tema.primary
                    selectedTextColor: p.tema.primaryText
                    Component.onCompleted: text = p.o.nombre || ""
                    onTextEdited: p.raiz.ponerOpcion(p.clave, "nombre", text.trim())
                    Keys.onReturnPressed: p.raiz.soltarTexto()
                    Keys.onEnterPressed: p.raiz.soltarTexto()
                    Keys.onEscapePressed: p.raiz.soltarTexto()
                }
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: Text.AlignVCenter
                    visible: campo.text === ""
                    elide: Text.ElideRight
                    text: p.tipo === "reloj" && p.elemento.contenido ? p.elemento.contenido.nombre : ""
                    font.family: p.fuente
                    font.pixelSize: 12
                    color: p.tema.surfaceText
                    opacity: 0.45
                }
            }
        }

        // ----- Calendario -----
        Fila {
            visible: p.tipo === "calendario"
            texto: "La semana empieza"
            Chips {
                opciones: [
                    { t: "Lunes", activo: p.o.domingo !== true, elegir: () => p.raiz.ponerOpcion(p.clave, "domingo", false) },
                    { t: "Domingo", activo: p.o.domingo === true, elegir: () => p.raiz.ponerOpcion(p.clave, "domingo", true) }
                ]
            }
        }

        // ----- Clima -----
        Fila {
            visible: p.tipo === "clima"
            texto: "Temperatura"
            Chips {
                opciones: [
                    { t: "°C", activo: p.o.fahrenheit !== true, elegir: () => p.raiz.ponerOpcion(p.clave, "fahrenheit", false) },
                    { t: "°F", activo: p.o.fahrenheit === true, elegir: () => p.raiz.ponerOpcion(p.clave, "fahrenheit", true) }
                ]
            }
        }
        Fila { visible: p.tipo === "clima"; texto: "Pronóstico"; Interruptor { opcion: "pronostico" } }
        Fila {
            visible: p.tipo === "clima"
            texto: "Ciudad"
            Rectangle {
                width: 170
                height: 28
                radius: 10
                color: Qt.rgba(p.tema.surfaceText.r, p.tema.surfaceText.g, p.tema.surfaceText.b, 0.08)
                border.width: 1
                border.color: campoCiudad.activeFocus ? p.tema.primary
                    : Qt.rgba(p.tema.primary.r, p.tema.primary.g, p.tema.primary.b, 0.35)
                TextInput {
                    id: campoCiudad
                    objectName: "campoCiudad"
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    maximumLength: 60
                    selectByMouse: true
                    font.family: p.fuente
                    font.pixelSize: 12
                    color: p.tema.surfaceText
                    selectionColor: p.tema.primary
                    selectedTextColor: p.tema.primaryText
                    onTextEdited: esperaBusqueda.restart()
                    // Al elegir ciudad se vacía el campo y se devuelve el teclado
                    Connections {
                        target: p.climaW
                        function onCiudadChanged() {
                            campoCiudad.text = ""
                            p.raiz.soltarTexto()
                        }
                    }
                    Keys.onReturnPressed: esperaBusqueda.triggered()
                    Keys.onEnterPressed: esperaBusqueda.triggered()
                    Keys.onEscapePressed: p.raiz.soltarTexto()
                }
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: Text.AlignVCenter
                    visible: campoCiudad.text === ""
                    elide: Text.ElideRight
                    text: p.climaW && p.climaW.ciudad ? p.climaW.ciudad.nombre : "Buscar…"
                    font.family: p.fuente
                    font.pixelSize: 12
                    color: p.tema.surfaceText
                    opacity: 0.45
                }
                Timer {
                    id: esperaBusqueda
                    interval: 400
                    onTriggered: if (p.climaW) p.climaW.buscarCiudad(campoCiudad.text)
                }
            }
        }
        Repeater {
            model: p.climaW ? p.climaW.resultados : []
            delegate: Rectangle {
                id: res
                required property var modelData
                width: col.width
                height: 34
                radius: 10
                color: Qt.rgba(p.tema.primary.r, p.tema.primary.g, p.tema.primary.b, zr.containsMouse ? 0.2 : 0.06)
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 8
                    width: parent.width - 16
                    Text { width: parent.width; elide: Text.ElideRight; text: res.modelData.nombre; font.family: p.fuente; font.pixelSize: 11; font.bold: true; color: p.tema.surfaceText }
                    Text { width: parent.width; elide: Text.ElideRight; text: res.modelData.region; font.family: p.fuente; font.pixelSize: 10; color: p.tema.surfaceText; opacity: 0.7 }
                }
                MouseArea {
                    id: zr
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: p.climaW.elegirCiudad(res.modelData)
                }
            }
        }

        // ----- Recordatorios -----
        Fila { visible: p.tipo === "recordatorios"; texto: "Mostrar completados"; Interruptor { opcion: "completados" } }

        // ----- Música -----
        Fila { visible: p.tipo === "musica"; texto: "Carátula"; Interruptor { opcion: "caratula" } }
        Fila { visible: p.tipo === "musica"; texto: "Controles"; Interruptor { opcion: "controles" } }

        // ----- Icono -----
        Fila {
            visible: p.tipo === "icono" || p.tipo === "grupo"
            texto: "Tamaño"
            Chips {
                opciones: ["S", "M", "L"].map(t => ({
                    t: t, activo: p.elemento && p.elemento.tam === t,
                    elegir: () => p.raiz.ponerTam(p.clave, t)
                }))
            }
        }
        Fila { visible: p.tipo === "icono" || p.tipo === "grupo"; texto: "Etiqueta"; Interruptor { opcion: "etiqueta" } }
    }
}
