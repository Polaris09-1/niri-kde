import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

// Página Capturas: área / pantalla / ventana (herramienta de niri), temporizador,
// grabar pantalla (wf-recorder) y últimas capturas con Copiar / Editar (satty) /
// Mostrar en carpeta / Borrar (a la papelera).
Item {
    id: c

    property var s
    property var tema
    property var grabadora
    property bool activa: false
    signal atras()

    implicitHeight: col.implicitHeight

    property int retraso: 0             // segundos de temporizador
    property string audio: "no"
    property string modoGrab: "pantalla"
    property string elegida: ""         // ruta de la captura elegida
    property bool confirmarBorrar: false
    property string carpeta: Quickshell.env("HOME") + "/Pictures/Screenshots"

    onActivaChanged: { c.elegida = ""; c.confirmarBorrar = false }

    FolderListModel {
        id: capturas
        folder: "file://" + c.carpeta
        nameFilters: ["*.png", "*.jpg", "*.jpeg"]
        showDirs: false
        sortField: FolderListModel.Time
    }

    // Aviso cuando aparece una captura nueva (tras la carga inicial de la carpeta)
    property int conteoPrevio: -1
    Connections {
        target: capturas
        function onCountChanged() { vigiaCarpeta.restart() }
    }
    Timer {
        id: vigiaCarpeta
        interval: 500
        onTriggered: {
            if (capturas.status !== FolderListModel.Ready) { vigiaCarpeta.restart(); return }
            if (c.conteoPrevio >= 0 && capturas.count > c.conteoPrevio) {
                var nueva = capturas.get(0, "filePath")
                Quickshell.execDetached(["notify-send", "-a", "Capturas", "-i", nueva, "-t", "4000",
                    "Captura guardada", "Copiada al portapapeles. Edítala desde el panel → Capturas"])
            }
            c.conteoPrevio = capturas.count
        }
    }

    function ejecutar(cmd) { Quickshell.execDetached(cmd) }

    function copiar(ruta) {
        c.ejecutar(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", ruta])
        c.s.avisoCaptura("Imagen copiada")
    }

    function editar(ruta) {
        c.s.panel = ""
        c.ejecutar(["satty", "--filename", ruta,
            "--output-filename", c.carpeta + "/Captura editada %Y-%m-%d %H-%M-%S.png",
            "--copy-command", "wl-copy", "--early-exit"])
    }

    function borrar(ruta) {
        c.ejecutar(["gio", "trash", ruta])
        c.elegida = ""
        c.confirmarBorrar = false
    }

    Column {
        id: col
        width: parent.width
        spacing: 12

        Encabezado {
            tema: c.tema
            titulo: "Capturas"
            onAtras: c.atras()
        }

        // ---------- Capturar ----------
        Row {
            width: parent.width
            spacing: 8
            Repeater {
                model: [
                    { id: "area", icono: 0xF0293, texto: "Área" },
                    { id: "pantalla", icono: 0xF0379, texto: "Pantalla" },
                    { id: "ventana", icono: 0xF05B6, texto: "Ventana" }
                ]
                delegate: Rectangle {
                    id: t
                    required property var modelData
                    width: (col.width - 16) / 3
                    height: 72
                    radius: 18
                    color: c.s.alfa(c.tema.primary, maT.containsMouse ? 0.2 : 0.09)
                    scale: maT.pressed ? 0.95 : 1
                    Behavior on scale {
                        NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: c.s.ic(t.modelData.icono)
                            font.family: c.s.fuente
                            font.pixelSize: 22
                            color: c.tema.primary
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: t.modelData.texto
                            font.family: c.s.fuente
                            font.pixelSize: 11
                            color: c.tema.surfaceText
                        }
                    }
                    MouseArea {
                        id: maT
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: c.s.capturar(t.modelData.id, c.retraso)
                    }
                }
            }
        }

        // Temporizador
        Row {
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: c.s.ic(0xF13AB) + "  Esperar"
                font.family: c.s.fuente
                font.pixelSize: 11
                color: c.s.alfa(c.tema.surfaceText, 0.7)
                rightPadding: 4
            }
            Repeater {
                model: [0, 3, 5, 10]
                delegate: Chip {
                    required property var modelData
                    s: c.s
                    tema: c.tema
                    texto: modelData === 0 ? "No" : modelData + " s"
                    elegido: c.retraso === modelData
                    onClic: c.retraso = modelData
                }
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "Se guardan en ~/Pictures/Screenshots y se copian al portapapeles. Atajos: Print · Ctrl+Print · Alt+Print"
            font.family: c.s.fuente
            font.pixelSize: 10
            color: c.s.alfa(c.tema.surfaceText, 0.5)
        }

        // ---------- Grabar ----------
        Etiqueta { s: c.s; tema: c.tema; texto: "Grabar pantalla" }

        Rectangle {
            width: parent.width
            height: colGrab.implicitHeight + 24
            radius: 16
            color: c.grabadora.grabando ? Qt.rgba(1, 0.33, 0.33, 0.15) : c.s.alfa(c.tema.primary, 0.07)

            Column {
                id: colGrab
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 10

                Row {
                    visible: !c.grabadora.grabando
                    spacing: 6
                    Repeater {
                        model: [ { id: "pantalla", t: "Pantalla completa" }, { id: "area", t: "Un área" } ]
                        delegate: Chip {
                            required property var modelData
                            s: c.s
                            tema: c.tema
                            texto: modelData.t
                            elegido: c.modoGrab === modelData.id
                            onClic: c.modoGrab = modelData.id
                        }
                    }
                }
                Row {
                    visible: !c.grabadora.grabando
                    spacing: 6
                    Repeater {
                        model: [ { id: "no", t: "Sin audio" }, { id: "sistema", t: "Sonido del sistema" }, { id: "mic", t: "Micrófono" } ]
                        delegate: Chip {
                            required property var modelData
                            s: c.s
                            tema: c.tema
                            texto: modelData.t
                            elegido: c.audio === modelData.id
                            onClic: c.audio = modelData.id
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 36
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        visible: c.grabadora.grabando
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10
                            height: 10
                            radius: 5
                            color: "#ff5555"
                            SequentialAnimation on opacity {
                                running: c.grabadora.grabando
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 600 }
                                NumberAnimation { to: 1; duration: 600 }
                            }
                        }
                        Text {
                            text: "Grabando  " + c.grabadora.tiempo()
                            font.family: c.s.fuente
                            font.pixelSize: 13
                            font.bold: true
                            color: c.tema.surfaceText
                        }
                    }
                    Text {
                        visible: !c.grabadora.grabando && c.grabadora.error !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - btnGrab.width - 10
                        wrapMode: Text.Wrap
                        text: "✕  " + c.grabadora.error
                        font.family: c.s.fuente
                        font.pixelSize: 11
                        color: "#ff8a80"
                    }
                    BotonTexto {
                        id: btnGrab
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        tema: c.tema
                        fuente: c.s.fuente
                        lleno: !c.grabadora.grabando
                        peligro: c.grabadora.grabando
                        texto: c.grabadora.grabando ? "Detener" : c.grabadora.eligiendoArea ? "Elige el área…" : "Grabar"
                        onClic: {
                            if (c.grabadora.grabando) c.grabadora.detener()
                            else c.s.grabar(c.modoGrab, c.audio)
                        }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Se guardan en ~/Videos/Grabaciones. Atajo: Shift+Print (inicia/detiene). Para detener también puedes tocar el punto rojo de la barra."
                    font.family: c.s.fuente
                    font.pixelSize: 10
                    color: c.s.alfa(c.tema.surfaceText, 0.5)
                }
            }
        }

        // ---------- Recientes ----------
        Item {
            width: parent.width
            height: 20
            Etiqueta { s: c.s; tema: c.tema; texto: "Últimas capturas"; topPadding: 0 }
            Text {
                anchors.right: parent.right
                text: "Abrir carpeta"
                font.family: c.s.fuente
                font.pixelSize: 11
                color: c.tema.primary
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { c.s.panel = ""; c.ejecutar(["dolphin", c.carpeta]) }
                }
            }
        }

        Text {
            visible: capturas.count === 0
            text: "Todavía no hay capturas"
            font.family: c.s.fuente
            font.pixelSize: 12
            color: c.s.alfa(c.tema.surfaceText, 0.55)
        }

        Grid {
            columns: 3
            spacing: 8
            Repeater {
                model: Math.min(6, capturas.count)
                delegate: Rectangle {
                    id: mini
                    required property int index
                    property string ruta: capturas.get(mini.index, "filePath") || ""
                    property bool elegida: c.elegida === mini.ruta
                    width: (col.width - 16) / 3
                    height: width * 0.6
                    radius: 12
                    color: c.s.alfa(c.tema.surfaceText, 0.06)
                    border.color: mini.elegida ? c.tema.primary : (maMini.containsMouse ? c.s.alfa(c.tema.primary, 0.5) : "transparent")
                    border.width: 2
                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 240
                        source: mini.ruta !== "" ? "file://" + mini.ruta : ""
                    }
                    MouseArea {
                        id: maMini
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { c.confirmarBorrar = false; c.elegida = mini.elegida ? "" : mini.ruta }
                        onDoubleClicked: c.editar(mini.ruta)
                    }
                }
            }
        }

        // Acciones sobre la captura elegida
        Row {
            visible: c.elegida !== ""
            spacing: 6
            BotonTexto { visible: !c.confirmarBorrar; tema: c.tema; fuente: c.s.fuente; texto: "Copiar"; lleno: true; onClic: c.copiar(c.elegida) }
            BotonTexto { visible: !c.confirmarBorrar; tema: c.tema; fuente: c.s.fuente; texto: "Editar"; onClic: c.editar(c.elegida) }
            BotonTexto { visible: !c.confirmarBorrar; tema: c.tema; fuente: c.s.fuente; texto: "Ver en carpeta"; onClic: { c.s.panel = ""; c.ejecutar(["dolphin", "--select", c.elegida]) } }
            BotonTexto { visible: !c.confirmarBorrar; tema: c.tema; fuente: c.s.fuente; texto: "Borrar"; peligro: true; onClic: c.confirmarBorrar = true }
            Text {
                visible: c.confirmarBorrar
                anchors.verticalCenter: parent.verticalCenter
                text: "¿Mover a la papelera?"
                font.family: c.s.fuente
                font.pixelSize: 12
                color: c.tema.surfaceText
            }
            BotonTexto { visible: c.confirmarBorrar; tema: c.tema; fuente: c.s.fuente; texto: "Cancelar"; onClic: c.confirmarBorrar = false }
            BotonTexto { visible: c.confirmarBorrar; tema: c.tema; fuente: c.s.fuente; texto: "Borrar"; peligro: true; onClic: c.borrar(c.elegida) }
        }
    }
}
