//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    // Sin el aviso "Config reloaded": matugen recarga este módulo en cada cambio de fondo.
    // Solo se oculta el de recarga correcta; el de error sigue saliendo.
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }
    property bool abierto: false
    property string filtro: ""

    // Arrastrar una app al escritorio: mantener pulsada y mover. No usa el arrastre de Wayland (el
    // escritorio está debajo de las ventanas y la app podría caer dentro de otra): el cajón sigue el
    // cursor, deja ver el escritorio y al soltar avisa al módulo "escritorio" por IPC.
    property var arrastrada: null
    property real cursorX: 0
    property real cursorY: 0
    function ipcEscritorio(args) {
        Quickshell.execDetached(["qs", "-c", "escritorio", "ipc", "call", "escritorio"].concat(args))
    }
    function empezarArrastre(app, x, y) {
        root.arrastrada = app
        root.cursorX = x
        root.cursorY = y
        root.ipcEscritorio(["arrastreApp", "empezar"])
    }
    function soltarArrastre() {
        var app = root.arrastrada
        root.arrastrada = null
        root.ipcEscritorio(["soltarApp", app.id, String(Math.round(root.cursorX)), String(Math.round(root.cursorY))])
        root.cerrar()
    }
    function cancelarArrastre() {
        root.arrastrada = null
        root.ipcEscritorio(["arrastreApp", "cancelar"])
        root.cerrar()
    }

    // Apps que no quieres ver (por inicio del nombre)
    property var ocultas: ["Avahi", "Foot Client", "Foot Server", "Hardware Locality", "Qt V4L2", "xgps"]

    // Lista base: sin ocultas, ordenada por nombre
    property var apps: DesktopEntries.applications.values
        .filter(a => !a.noDisplay && !root.ocultas.some(p => a.name.startsWith(p)))
        .sort((a, b) => a.name.localeCompare(b.name))

    // Lista que se muestra: filtrada por lo que escribes
    property var visibles: root.apps
        .filter(a => a.name.toLowerCase().includes(root.filtro.toLowerCase()))

    // Colores de matugen
    Colors { id: tema }

    // Atajo de niri: qs -c cajon ipc call cajon toggle
    IpcHandler {
        target: "cajon"
        function toggle(): void {
            if (root.abierto) root.cerrar()
            else root.abrir()
        }
    }

    function abrir() {
        esconder.stop()
        buscador.text = ""
        ventana.visible = true
        root.abierto = true
        buscador.forceActiveFocus()
    }

    function cerrar() {
        root.arrastrada = null
        root.abierto = false
        esconder.restart()
    }

    function alEscritorio(app) {
        Quickshell.execDetached(["sh", "-c", "cp $(find ~/.local/share/applications /usr/share/applications -name $1.desktop | head -1) ~/Desktop/ && notify-send Escritorio \"Acceso añadido\"", "sh", app.id])
        root.cerrar()
    }

    function lanzar(app) {
        // execute() no abre terminal: una app con Terminal=true quedaría corriendo sin ventana
        if (app.runInTerminal) Quickshell.execDetached(["alacritty", "-e"].concat(app.command))
        else app.execute()
        root.cerrar()
    }

    // Espera a que termine la animación de cierre
    Timer {
        id: esconder
        interval: 300
        onTriggered: ventana.visible = false
    }

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
        WlrLayershell.namespace: "cajon"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        // Toda la pantalla, salvo durante un arrastre: ahí hay que ver el escritorio nítido
        BackgroundEffect.blurRegion: root.arrastrada === null ? zonaBlur : null
        property Region zonaBlur: Region { x: 0; y: 0; width: ventana.width; height: ventana.height }

        // Fondo oscuro; clic afuera cierra
        Rectangle {
            anchors.fill: parent
            color: tema.surface
            opacity: root.abierto && root.arrastrada === null ? 0.55 : 0
            Behavior on opacity {
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.cerrar()
                enabled: root.arrastrada === null
            }
        }

        // La app que se arrastra, siguiendo al cursor
        Image {
            z: 10
            visible: root.arrastrada !== null
            x: root.cursorX - width / 2
            y: root.cursorY - height / 2
            width: 64
            height: 64
            sourceSize.width: 128
            sourceSize.height: 128
            source: root.arrastrada ? Quickshell.iconPath(root.arrastrada.icon, "application-x-executable") : ""
        }

        // Contenido con zoom de entrada
        Item {
            id: contenido
            anchors.fill: parent
            opacity: root.abierto && root.arrastrada === null ? 1 : 0
            scale: root.abierto ? 1 : 0.9
            Behavior on opacity {
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 350; easing.type: Easing.OutBack }
            }

            // Caja del buscador
            Rectangle {
                id: caja
                anchors.top: parent.top
                anchors.topMargin: 80
                anchors.horizontalCenter: parent.horizontalCenter
                width: 500
                height: 48
                radius: 24
                color: "transparent"
                border.color: tema.primary
                border.width: 2

                TextInput {
                    id: buscador
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    verticalAlignment: TextInput.AlignVCenter
                    color: tema.surfaceText
                    font.pixelSize: 18
                    onTextChanged: root.filtro = text
                    Keys.onEscapePressed: root.arrastrada !== null ? root.cancelarArrastre() : root.cerrar()
                    Keys.onReturnPressed: if (root.visibles.length > 0) root.lanzar(root.visibles[0])
                    Keys.onEnterPressed: if (root.visibles.length > 0) root.lanzar(root.visibles[0])

                    // Texto de ayuda cuando está vacío
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Buscar aplicación..."
                        color: tema.surfaceText
                        opacity: 0.5
                        font.pixelSize: 18
                        visible: buscador.text.length === 0
                    }
                }
            }

            GridView {
                id: grilla
                anchors.top: caja.bottom
                anchors.topMargin: 40
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 80
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 200, cellWidth * 8)
                cellWidth: 140
                cellHeight: 140
                clip: true
                interactive: root.arrastrada === null
                model: root.visibles

                delegate: Item {
                    id: celda
                    required property var modelData
                    required property int index
                    width: grilla.cellWidth
                    height: grilla.cellHeight

                    // Primera coincidencia del buscador (la que abre Enter)
                    property bool elegida: root.filtro !== "" && celda.index === 0

                    // Entrada en cascada
                    transform: Translate {
                        y: root.abierto ? 0 : 60
                        Behavior on y {
                            NumberAnimation {
                                duration: 250 + Math.min(celda.index, 40) * 12
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    // Resalte: al pasar el mouse o si es la elegida
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 8
                        radius: 20
                        color: tema.primary
                        opacity: (zona.containsMouse || celda.elegida) ? 0.25 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    // Arriba fija (no centrada): un nombre en dos líneas no desalinea el icono
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 25
                        spacing: 8
                        scale: (zona.containsMouse || celda.elegida) ? 1.1 : 1
                        Behavior on scale {
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 64
                            height: 64
                            sourceSize.width: 64
                            sourceSize.height: 64
                            source: Quickshell.iconPath(celda.modelData.icon, "application-x-executable")
                        }

                        Text {
                            width: grilla.cellWidth - 16
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: tema.surfaceText
                            font.pixelSize: 13
                            text: celda.modelData.name
                        }
                    }

                    MouseArea {
                        id: zona
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        pressAndHoldInterval: 300
                        preventStealing: root.arrastrada !== null
                        onClicked: mouse => {
                            if (root.arrastrada !== null) return
                            mouse.button === Qt.RightButton ? root.alEscritorio(celda.modelData) : root.lanzar(celda.modelData)
                        }
                        onPressAndHold: mouse => {
                            if (mouse.button !== Qt.LeftButton) return
                            var p = zona.mapToItem(null, mouse.x, mouse.y)
                            root.empezarArrastre(celda.modelData, p.x, p.y)
                        }
                        onPositionChanged: mouse => {
                            if (root.arrastrada === null) return
                            var p = zona.mapToItem(null, mouse.x, mouse.y)
                            root.cursorX = p.x
                            root.cursorY = p.y
                        }
                        onReleased: if (root.arrastrada !== null) root.soltarArrastre()
                        onCanceled: if (root.arrastrada !== null) root.cancelarArrastre()
                    }
                }
            }
        }
    }
}
