import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick

// Agente polkit propio (2026-11-01, punto 5 del plan 10/10): cuando una app pide permisos de
// administrador (Discover, udisks, pkexec, power-profiles…), aparece este diálogo con el estilo
// de los paneles. Sin un agente, esas peticiones fallan.
//
// Seguridad:
// - La contraseña solo vive en el campo de texto hasta pulsar Enter/Autorizar; se entrega a polkit
//   con flow.submit() y el campo se vacía en cada intento. Nunca va a registros, archivos ni IPC.
// - Debe arrancarlo niri (spawn-at-startup): polkit asocia el agente a la sesión de quien lo lanza.
// - No se recarga solo (Quickshell.watchFiles = false): un cambio de fondo reescribe Colors.qml y
//   cancelaría un diálogo abierto. Tras editar este archivo:
//   pkill -f -- '-c permisos$'; niri msg action spawn -- qs -c permisos
ShellRoot {
    id: root

    property string fuente: "JetBrainsMono Nerd Font"
    property color colorError: "#ffb4ab"

    Component.onCompleted: Quickshell.watchFiles = false

    // ===== Colores de matugen (leídos del archivo, sin recargar el módulo) =====
    QtObject {
        id: colores
        property color surface: "#191114"
        property color surfaceText: "#eedfe3"
        property color primary: "#ffafd3"
        property color primaryText: "#5c0f3d"
        property color secondary: "#edb8ce"
    }
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/hola/Colors.qml"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var t = text()
            for (var nombre of ["surface", "surfaceText", "primary", "primaryText", "secondary"]) {
                var m = new RegExp("property color " + nombre + "\\s*:\\s*\"(#[0-9a-fA-F]{6,8})\"").exec(t)
                if (m) colores[nombre] = m[1]
            }
        }
    }

    function alfa(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function ic(cp) { return String.fromCodePoint(cp) }

    // ===== Agente =====
    PolkitAgent { id: agente }
    readonly property var flujo: agente.flow

    // Lo que se muestra se guarda aparte: así el diálogo no se vacía mientras se desvanece
    property string mensaje: ""
    property string accion: ""
    property string icono: ""
    property bool enviando: false
    property bool fallo: false
    property bool verDetalles: false
    onFlujoChanged: {
        if (!root.flujo) return
        root.mensaje = root.flujo.message
        root.accion = root.flujo.actionId
        root.icono = root.flujo.iconName
        root.enviando = false
        root.fallo = false
        root.verDetalles = false
    }
    Connections {
        target: root.flujo
        ignoreUnknownSignals: true
        function onAuthenticationFailed() { root.enviando = false; root.fallo = true; root.sacudir() }
        function onIsResponseRequiredChanged() { if (root.flujo && root.flujo.isResponseRequired) root.enviando = false }
        function onAuthenticationSucceeded() { root.enviando = false }
    }
    signal sacudir()

    // ----- Traducción de los mensajes más comunes (polkit los manda en inglés: LANG=en_US) -----
    readonly property var frases: ({
        "unlock an encrypted device": "desbloquear un dispositivo cifrado",
        "mount the filesystem": "montar el sistema de archivos",
        "put a drive into standby mode": "poner una unidad en reposo",
        "update the firmware on this machine": "actualizar el firmware de este equipo",
        "update the firmware on a removable device": "actualizar el firmware de un dispositivo extraíble",
        "downgrade the firmware on this machine": "instalar una versión anterior del firmware de este equipo",
        "downgrade the firmware on a removable device": "instalar una versión anterior del firmware de un dispositivo extraíble",
        "update software": "actualizar software",
        "install software": "instalar software",
        "remove software": "desinstalar software",
        "update SMART data": "actualizar los datos SMART",
        "power off a drive": "apagar una unidad",
        "open a device": "abrir un dispositivo",
        "modify a device": "modificar un dispositivo",
        "eject media": "expulsar un medio",
        "change the passphrase for an encrypted device": "cambiar la frase de paso de un dispositivo cifrado",
        "run a program as another user": "ejecutar un programa como otro usuario",
        "format a device": "formatear un dispositivo",
        "unmount a filesystem mounted by another user": "desmontar un sistema de archivos montado por otro usuario"
    })
    function traducir(m) {
        if (!m) return ""
        var s = String(m).trim().replace(/\.$/, "")
        var r = /^Authentication is (?:needed|required) to run [`'‘"](.+)[`'’"] as the super user$/.exec(s)
        if (r) return "Se necesita tu contraseña para ejecutar «" + r[1] + "» como administrador."
        r = /^Authentication is (?:needed|required) to run [`'‘"](.+)[`'’"] as user (.+)$/.exec(s)
        if (r) return "Se necesita tu contraseña para ejecutar «" + r[1] + "» como el usuario " + r[2] + "."
        r = /^Authentication is (?:needed|required) to (.+)$/.exec(s)
        if (r && root.frases[r[1]]) return "Se necesita tu contraseña para " + root.frases[r[1]] + "."
        r = /^Privileges are required to (.+)$/.exec(s)
        if (r) return "Se necesitan permisos de administrador (" + r[1] + ")."
        return m
    }
    function traducirPrompt(p) {
        if (!p || /^\s*password:?\s*$/i.test(p)) return "Contraseña"
        return String(p).replace(/:\s*$/, "")
    }

    // ----- Acciones -----
    function enviar(texto) {
        if (!root.flujo || root.enviando || texto.length === 0) return
        root.enviando = true
        root.fallo = false
        root.flujo.submit(texto)
    }
    function cancelar() {
        if (root.flujo) root.flujo.cancelAuthenticationRequest()
        root.enviando = false
    }

    // ----- Bloq Mayús (LED del teclado, cada 200 ms mientras se ve el diálogo) -----
    property var ledsMayus: []
    property bool mayus: false
    Process {
        running: true
        command: ["sh", "-c", "for l in /sys/class/leds/*::capslock; do [ -e \"$l/brightness\" ] && echo \"$l/brightness\"; done"]
        stdout: StdioCollector { onStreamFinished: root.ledsMayus = this.text.split("\n").filter(l => l.length > 0) }
    }
    Variants {
        id: lectoresMayus
        model: root.ledsMayus
        delegate: FileView {
            required property var modelData
            path: modelData
            blockLoading: true
        }
    }
    Timer {
        interval: 200
        repeat: true
        running: agente.isActive && root.ledsMayus.length > 0
        onTriggered: {
            var encendido = false
            for (var i = 0; i < lectoresMayus.instances.length; i++) {
                var f = lectoresMayus.instances[i]
                f.reload()
                if (parseInt(f.text()) > 0) encendido = true
            }
            root.mayus = encendido
        }
    }

    // ===== Diálogo =====
    PanelWindow {
        id: ventana
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "permisos"
        // Teclado solo para el diálogo mientras está abierto (la contraseña no se escapa a otra app)
        WlrLayershell.keyboardFocus: agente.isActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        visible: p > 0.001

        // Entra en 150 ms y sale en 120 (OutCubic, sin rebote ni zoom)
        property real p: agente.isActive ? 1 : 0
        Behavior on p { NumberAnimation { duration: agente.isActive ? 150 : 120; easing.type: Easing.OutCubic } }
        onPChanged: if (p > 0.5 && agente.isActive && !campo.activeFocus) campo.forceActiveFocus()

        // Velo
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.4 * ventana.p
            MouseArea { anchors.fill: parent }   // los clics fuera no llegan a las apps
        }

        Item {
            id: tarjeta
            width: 440
            height: columna.implicitHeight + 48
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - height) / 2 + (1 - ventana.p) * 14
            opacity: ventana.p

            Rectangle {
                anchors.fill: parent
                radius: 24
                color: root.alfa(colores.surface, 0.96)
                border.color: root.alfa(colores.primary, 0.5)
                border.width: 1.5
            }

            Column {
                id: columna
                x: 24
                y: 24
                width: parent.width - 48
                spacing: 16

                // Icono + título + mensaje
                Row {
                    width: parent.width
                    spacing: 14
                    Rectangle {
                        width: 46
                        height: 46
                        radius: 23
                        color: root.alfa(colores.primary, 0.16)
                        Image {
                            id: iconoApp
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            sourceSize: Qt.size(28, 28)
                            source: root.icono ? Quickshell.iconPath(root.icono, true) : ""
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !iconoApp.visible
                            text: root.ic(0xF099D)      // escudo con candado
                            font.family: root.fuente
                            font.pixelSize: 22
                            color: colores.primary
                        }
                    }
                    Column {
                        width: parent.width - 60
                        spacing: 4
                        Text {
                            width: parent.width
                            text: "Se necesita autorización"
                            font.family: root.fuente
                            font.pixelSize: 16
                            font.bold: true
                            color: colores.surfaceText
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: root.traducir(root.mensaje)
                            font.family: root.fuente
                            font.pixelSize: 12
                            color: root.alfa(colores.surfaceText, 0.8)
                        }
                    }
                }

                // Detalles (identificador técnico de la acción)
                Column {
                    width: parent.width
                    spacing: 4
                    Text {
                        text: (root.verDetalles ? root.ic(0xF0140) : root.ic(0xF0142)) + " Detalles"
                        font.family: root.fuente
                        font.pixelSize: 11
                        color: root.alfa(colores.surfaceText, 0.55)
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.verDetalles = !root.verDetalles
                        }
                    }
                    Text {
                        visible: root.verDetalles
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                        text: "Acción: " + root.accion + (root.mensaje !== root.traducir(root.mensaje) ? "\nMensaje original: " + root.mensaje : "")
                        font.family: root.fuente
                        font.pixelSize: 10
                        color: root.alfa(colores.surfaceText, 0.55)
                    }
                }

                // Cuenta con la que se autoriza (si hay varias, se puede elegir)
                Flow {
                    width: parent.width
                    spacing: 8
                    Text {
                        height: 28
                        verticalAlignment: Text.AlignVCenter
                        text: "Como:"
                        font.family: root.fuente
                        font.pixelSize: 12
                        color: root.alfa(colores.surfaceText, 0.7)
                    }
                    Repeater {
                        model: root.flujo ? root.flujo.identities : []
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool elegida: root.flujo && root.flujo.selectedIdentity === modelData
                            height: 28
                            width: filaChip.implicitWidth + 20
                            radius: 14
                            color: elegida ? root.alfa(colores.primary, 0.22) : root.alfa(colores.surfaceText, 0.06)
                            border.color: elegida ? root.alfa(colores.primary, 0.7) : root.alfa(colores.surfaceText, 0.15)
                            border.width: 1
                            Row {
                                id: filaChip
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.ic(chip.modelData.isGroup ? 0xF0849 : 0xF0004)
                                    font.family: root.fuente
                                    font.pixelSize: 13
                                    color: colores.primary
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, chip.parent ? chip.parent.width - 48 : 300)
                                    elide: Text.ElideRight
                                    text: chip.modelData.displayName || chip.modelData.string || ("uid " + chip.modelData.id)
                                    font.family: root.fuente
                                    font.pixelSize: 12
                                    color: colores.surfaceText
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: root.flujo && root.flujo.identities.length > 1
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: { root.flujo.selectedIdentity = chip.modelData; campo.text = ""; campo.forceActiveFocus() }
                            }
                        }
                    }
                }

                // Contraseña
                Item {
                    width: parent.width
                    height: 46
                    Rectangle {
                        id: pildora
                        width: parent.width
                        height: parent.height
                        radius: height / 2
                        color: root.alfa(colores.surfaceText, 0.05)
                        border.width: 1.5
                        border.color: root.fallo ? root.colorError
                                    : campo.activeFocus ? root.alfa(colores.primary, 0.7) : root.alfa(colores.primary, 0.3)
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        SequentialAnimation on x {
                            id: animSacudir
                            running: false
                            NumberAnimation { to: -10; duration: 50; easing.type: Easing.OutCubic }
                            NumberAnimation { to: 8; duration: 70 }
                            NumberAnimation { to: -5; duration: 60 }
                            NumberAnimation { to: 0; duration: 60; easing.type: Easing.OutCubic }
                        }
                        Connections { target: root; function onSacudir() { animSacudir.restart() } }

                        TextInput {
                            id: campo
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            verticalAlignment: TextInput.AlignVCenter
                            // Si polkit pide algo visible (no una contraseña), se ve el texto
                            readonly property bool visibleTexto: !!(root.flujo && root.flujo.responseVisible)
                            opacity: visibleTexto ? 1 : 0
                            echoMode: visibleTexto ? TextInput.Normal : TextInput.Password
                            color: colores.surfaceText
                            font.family: root.fuente
                            font.pixelSize: 13
                            enabled: agente.isActive && !root.enviando
                            focus: true
                            onAccepted: { var t = text; text = ""; root.enviar(t) }
                            Keys.onEscapePressed: { text = ""; root.cancelar() }
                        }
                        Row {
                            visible: !campo.visibleTexto && campo.text.length > 0
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            Repeater {
                                model: Math.min(campo.text.length, 24)
                                delegate: Rectangle { width: 8; height: 8; radius: 4; color: colores.primary }
                            }
                        }
                        Text {
                            visible: campo.text.length === 0
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.enviando ? "Comprobando…" : root.traducirPrompt(root.flujo ? root.flujo.inputPrompt : "")
                            font.family: root.fuente
                            font.pixelSize: 13
                            color: root.alfa(colores.surfaceText, 0.45)
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: campo.forceActiveFocus() }
                }

                // Mensajes: error, mensaje extra de polkit, Bloq Mayús
                Column {
                    width: parent.width
                    spacing: 4
                    visible: root.fallo || root.mayus || !!(root.flujo && root.flujo.supplementaryMessage)
                    Text {
                        visible: root.fallo
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Contraseña incorrecta. Inténtalo de nuevo."
                        font.family: root.fuente
                        font.pixelSize: 12
                        color: root.colorError
                    }
                    Text {
                        visible: !!(root.flujo && root.flujo.supplementaryMessage) && !root.fallo
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: root.flujo ? root.flujo.supplementaryMessage : ""
                        font.family: root.fuente
                        font.pixelSize: 12
                        color: root.flujo && root.flujo.supplementaryIsError ? root.colorError : root.alfa(colores.surfaceText, 0.75)
                    }
                    Text {
                        visible: root.mayus
                        width: parent.width
                        text: root.ic(0xF0632) + "  Bloq Mayús activado"
                        font.family: root.fuente
                        font.pixelSize: 12
                        color: root.alfa(colores.surfaceText, 0.75)
                    }
                }

                // Botones
                Row {
                    anchors.right: parent.right
                    spacing: 10
                    Repeater {
                        model: [ { id: "cancelar", texto: "Cancelar" }, { id: "autorizar", texto: "Autorizar" } ]
                        delegate: Rectangle {
                            id: boton
                            required property var modelData
                            readonly property bool principal: modelData.id === "autorizar"
                            readonly property bool activo: !principal || (campo.text.length > 0 && !root.enviando)
                            width: textoBoton.implicitWidth + 32
                            height: 36
                            radius: 18
                            opacity: activo ? 1 : 0.5
                            color: principal ? colores.primary
                                 : zona.containsMouse ? root.alfa(colores.primary, 0.18) : root.alfa(colores.surfaceText, 0.07)
                            Text {
                                id: textoBoton
                                anchors.centerIn: parent
                                text: boton.modelData.texto
                                font.family: root.fuente
                                font.pixelSize: 13
                                font.bold: boton.principal
                                color: boton.principal ? colores.primaryText : colores.surfaceText
                            }
                            MouseArea {
                                id: zona
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: boton.activo
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (boton.principal) { var t = campo.text; campo.text = ""; root.enviar(t); campo.forceActiveFocus() }
                                    else { campo.text = ""; root.cancelar() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ===== IPC: qs -c permisos ipc call permisos <función> =====
    IpcHandler {
        target: "permisos"
        function info(): string {
            return JSON.stringify({
                registrado: agente.isRegistered, activo: agente.isActive,
                accion: root.flujo ? root.flujo.actionId : "", mensaje: root.flujo ? root.traducir(root.flujo.message) : "",
                pideRespuesta: root.flujo ? root.flujo.isResponseRequired : false,
                fallo: root.fallo, enviando: root.enviando, mayus: root.mayus
            })
        }
        function cancelar(): string { if (!agente.isActive) return "no hay petición"; root.cancelar(); return "cancelada" }
        // Solo para pruebas: envía una contraseña inventada (siempre incorrecta) para ver el error.
        function probarIncorrecta(): string {
            if (!agente.isActive) return "no hay petición"
            root.enviar("prueba-incorrecta-" + Date.now())
            return "enviada una contraseña inventada"
        }
    }
}
