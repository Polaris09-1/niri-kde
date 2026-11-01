import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import QtQuick

// Pantalla de bloqueo y bloqueo automático (2026-11-01, puntos 2+7 del plan 10/10).
//
// Seguridad:
// - WlSessionLock (ext-session-lock): si este módulo se cae estando bloqueado, niri MANTIENE la
//   sesión bloqueada y deja que otro bloqueo (swaylock) ocupe su lugar (atajo de rescate en niri).
// - La contraseña se comprueba con PAM, servicio "swaylock" (/etc/pam.d/swaylock → login →
//   system-auth, con faillock: 5 fallos = 2 min de espera). Solo vive en el campo de texto hasta
//   pulsar Enter; nunca va a registros, archivos ni IPC. El campo se vacía en cada intento.
// - Este módulo NO se recarga solo (Quickshell.watchFiles = false): matugen reescribe Colors.qml al
//   cambiar el fondo y una recarga con la sesión bloqueada tiraría la pantalla de bloqueo. Los
//   colores se leen con FileView. Tras editar este archivo:
//   pkill -f -- '-c bloqueo$'; setsid qs -c bloqueo &
//
// Inactividad (elegido: 10 min): atenuar a los 9:30, bloquear a los 10:00, apagar la pantalla
// 30 s después de bloquear si nadie la toca, suspender a los 30 min solo con batería.
// "Bloquear antes de suspender" (tapa) lo hace swayidle -w con ~/.local/bin/bloquear.sh.
ShellRoot {
    id: root

    // ===== Ajustes =====
    property int atenuarSeg: 570          // 9:30
    property int bloquearSeg: 600         // 10:00
    property int apagarPantallaSeg: 30    // con la sesión bloqueada y sin tocar nada
    property int suspenderSeg: 1800       // 30 min, solo con batería
    property real opacidadAtenuado: 0.55
    property string servicioPam: "swaylock"
    property string fuente: "JetBrainsMono Nerd Font"
    property color colorError: "#ffb4ab"
    readonly property string usuario: Quickshell.env("USER") || "usuario"

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

    // Imagen fija del fondo actual (para vídeo/GIF es su fotograma)
    property string rutaFondo: ""
    FileView {
        path: Quickshell.env("HOME") + "/.cache/wallpaper-imagen"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.rutaFondo = text().trim()
    }

    // ===== Estado =====
    property bool bloqueado: false
    // Avisa al fondo animado para que pause el vídeo mientras está bloqueado (y con la pantalla apagada)
    onBloqueadoChanged: Quickshell.execDetached(["qs", "-c", "fondo", "ipc", "call", "fondo", "bloqueo", root.bloqueado ? "si" : "no"])
    property real horaBloqueo: 0
    property bool verificando: false
    property string error: ""
    property string mensajePam: ""
    signal fallo()

    SystemClock { id: reloj; precision: SystemClock.Seconds }
    readonly property date ahora: reloj.date

    // Batería (UPower) y wifi (nmcli, solo mientras se ve la pantalla)
    readonly property var bat: UPower.displayDevice
    readonly property bool hayBateria: !!(root.bat && root.bat.isLaptopBattery)
    readonly property int bateria: root.bat ? Math.round(root.bat.percentage > 1 ? root.bat.percentage : root.bat.percentage * 100) : 0
    readonly property bool cargando: root.bat ? root.bat.state === UPowerDeviceState.Charging : false
    property int wifiSenal: -1
    Process {
        id: pWifi
        command: ["sh", "-c", "nmcli -t -f ACTIVE,SIGNAL dev wifi list --rescan no | grep '^yes' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var c = this.text.trim().split(":")
                root.wifiSenal = c.length >= 2 ? (parseInt(c[1]) || 0) : -1
            }
        }
    }
    Timer {
        interval: 20000
        repeat: true
        triggeredOnStart: true
        running: root.bloqueado || root.vista
        onTriggered: pWifi.running = true
    }

    // Música (MPRIS)
    readonly property var jugador: {
        var l = Mpris.players.values
        return l.length ? (l.find(j => j.isPlaying) || l[0]) : null
    }
    function musica(accion) {
        if (!root.jugador) return
        if (accion === "anterior" && root.jugador.canGoPrevious) root.jugador.previous()
        else if (accion === "siguiente" && root.jugador.canGoNext) root.jugador.next()
        else if (accion === "pausa" && root.jugador.canTogglePlaying) root.jugador.togglePlaying()
    }

    // Avisos que llegaron mientras estaba bloqueado (solo se cuentan)
    property var historial: []
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/avisos/historial.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.historial = JSON.parse(text()) } catch (e) { root.historial = [] } }
    }
    readonly property int avisosNuevos: (root.bloqueado || root.vista)
        ? root.historial.filter(a => a && a.hora > root.horaBloqueo).length : 0

    // Bloq Mayús (LED del teclado, cada 200 ms mientras se ve la pantalla)
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
        running: (root.bloqueado || root.vista) && root.ledsMayus.length > 0
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

    // ===== Bloqueo =====
    function bloquear() {
        if (root.bloqueado) return "ya-bloqueado"
        root.horaBloqueo = Date.now()
        root.error = ""
        root.mensajePam = ""
        root.verificando = false
        root.bloqueado = true
        return "bloqueando"
    }
    function desbloquear() {
        root.verificando = false
        root.error = ""
        root.bloqueado = false
    }

    WlSessionLock {
        id: candado
        locked: root.bloqueado

        WlSessionLockSurface {
            color: "black"
            Pantalla {
                anchors.fill: parent
                s: root
                tema: colores
            }
        }
    }

    // ===== Contraseña (PAM) =====
    property string pendiente: ""         // solo entre Enter y la respuesta a PAM
    function intentar(texto) {
        if (!root.bloqueado || root.verificando || texto.length === 0) return
        root.error = ""
        root.mensajePam = ""
        root.pendiente = texto
        root.verificando = true
        if (!pam.start()) {
            root.pendiente = ""
            root.verificando = false
            root.error = "No se pudo comprobar la contraseña"
            root.fallo()
        }
    }
    PamContext {
        id: pam
        config: root.servicioPam
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.pendiente)
                root.pendiente = ""
            } else if (this.message) {
                root.mensajePam = this.message
            }
        }
        onCompleted: result => {
            root.pendiente = ""
            if (result === PamResult.Success) { root.desbloquear(); return }
            root.verificando = false
            var m = root.mensajePam.toLowerCase()
            if (result === PamResult.MaxTries || m.indexOf("locked") >= 0 || m.indexOf("bloque") >= 0)
                root.error = "Demasiados intentos: espera unos minutos y vuelve a probar"
            else if (result === PamResult.Failed)
                root.error = "Contraseña incorrecta"
            else
                root.error = "No se pudo comprobar la contraseña"
            root.fallo()
        }
        onError: err => {
            root.pendiente = ""
            root.verificando = false
            root.error = "No se pudo comprobar la contraseña"
            root.fallo()
        }
    }

    // ===== Energía =====
    function energia(id) {
        var cmd = { suspender: ["systemctl", "suspend"], reiniciar: ["systemctl", "reboot"],
                    apagar: ["systemctl", "poweroff"] }[id]
        if (cmd) Quickshell.execDetached(cmd)
    }

    // ===== Inactividad =====
    IdleMonitor {
        id: inactivoAtenuar
        enabled: !root.bloqueado
        timeout: root.atenuarSeg
        respectInhibitors: true
    }
    IdleMonitor {
        id: inactivoBloquear
        enabled: !root.bloqueado
        timeout: root.bloquearSeg
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.bloquear()
    }
    IdleMonitor {
        id: inactivoPantalla
        enabled: root.bloqueado
        timeout: root.apagarPantallaSeg
        respectInhibitors: false
        onIsIdleChanged: if (isIdle) Quickshell.execDetached(["niri", "msg", "action", "power-off-monitors"])
    }
    IdleMonitor {
        id: inactivoSuspender
        enabled: UPower.onBattery
        timeout: root.suspenderSeg
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.energia("suspender")
    }

    // Atenuado antes de bloquear: se oscurece poco a poco durante 30 s; cualquier tecla o
    // movimiento del mouse lo quita al instante. No atrapa el mouse.
    property bool probandoAtenuado: false
    readonly property bool atenuar: (inactivoAtenuar.isIdle && !root.bloqueado) || root.probandoAtenuado
    Timer { id: finPrueba; interval: 2500; onTriggered: root.probandoAtenuado = false }
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: capaAtenuado
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "bloqueo-atenuado"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}
            visible: velo.opacity > 0.001
            Rectangle {
                id: velo
                anchors.fill: parent
                color: "black"
                opacity: 0
            }
            // Dos animaciones explícitas: oscurecer despacio (hasta el bloqueo) y aclarar en 200 ms
            // en cuanto hay actividad. (Un Behavior con duración variable tomaba la duración vieja.)
            NumberAnimation {
                id: oscurecer
                target: velo
                property: "opacity"
                to: root.opacidadAtenuado
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                id: aclarar
                target: velo
                property: "opacity"
                to: 0
                duration: 200
                easing.type: Easing.OutCubic
            }
            Connections {
                target: root
                function onAtenuarChanged() {
                    if (root.atenuar) {
                        aclarar.stop()
                        oscurecer.duration = root.probandoAtenuado ? 1200 : (root.bloquearSeg - root.atenuarSeg) * 1000
                        oscurecer.restart()
                    } else {
                        oscurecer.stop()
                        aclarar.restart()
                    }
                }
            }
        }
    }

    // ===== Vista previa (sin bloquear de verdad; solo para mirar el diseño) =====
    property bool vista: false
    property string mensajeVista: ""
    function avisoVista() { root.mensajeVista = "Vista previa: no se comprueba la contraseña" }
    Timer { id: finVista; onTriggered: { root.vista = false; root.mensajeVista = "" } }
    PanelWindow {
        visible: root.vista
        anchors { top: true; bottom: true; left: true; right: true }
        color: "black"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bloqueo-vista-previa"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Loader {
            anchors.fill: parent
            active: root.vista
            sourceComponent: Pantalla {
                s: root
                tema: colores
                vistaPrevia: true
            }
        }
    }

    // ===== Prueba de la conexión con PAM (sin tocar la cuenta real) =====
    // Solo acepta un directorio de configuración propio (p. ej. con pam_permit o pam_deny):
    // sirve para comprobar el flujo sin gastar intentos de faillock. Nunca desbloquea nada.
    property string resultadoPrueba: ""
    PamContext {
        id: pamPrueba
        config: "prueba"
        onPamMessage: if (this.responseRequired) this.respond("prueba")
        onCompleted: result => root.resultadoPrueba = PamResult.toString(result)
        onError: err => root.resultadoPrueba = "error: " + PamError.toString(err)
    }

    // ===== IPC: qs -c bloqueo ipc call bloqueo <función> =====
    IpcHandler {
        target: "bloqueo"
        function bloquear(): string { return root.bloquear() }
        // "seguro" cuando niri confirmó el bloqueo (lo espera bloquear.sh antes de suspender)
        function estado(): string {
            return !root.bloqueado ? "desbloqueado" : (candado.secure ? "seguro" : "bloqueando")
        }
        function vistaPrevia(segundos: int): string {
            root.horaBloqueo = Date.now() - 3600 * 1000
            root.vista = true
            finVista.interval = Math.max(1, segundos) * 1000
            finVista.restart()
            return "vista previa " + segundos + " s"
        }
        function probarAtenuado(): string { root.probandoAtenuado = true; finPrueba.restart(); return "atenuando 2,5 s" }
        function probarPam(directorio: string): string {
            if (!directorio || directorio === "/etc/pam.d") return "usa un directorio de prueba propio"
            root.resultadoPrueba = "en curso"
            pamPrueba.configDirectory = directorio
            return pamPrueba.start() ? "iniciado" : "no se pudo iniciar"
        }
        function info(): string {
            return JSON.stringify({
                bloqueado: root.bloqueado, seguro: candado.secure, verificando: root.verificando,
                error: root.error, avisosNuevos: root.avisosNuevos, mayus: root.mayus,
                bateria: root.bateria, enBateria: UPower.onBattery, wifi: root.wifiSenal,
                fondo: root.rutaFondo, vista: root.vista, atenuar: root.atenuar,
                inactivo: { atenuar: inactivoAtenuar.isIdle, bloquear: inactivoBloquear.isIdle,
                            suspender: inactivoSuspender.isIdle },
                pruebaPam: root.resultadoPrueba
            })
        }
    }
}
