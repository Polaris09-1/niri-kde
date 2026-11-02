import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Límite de carga de la batería con UPower (EnableChargeThreshold).
// polkit permite esta acción sin contraseña al usuario de la sesión activa
// (org.freedesktop.UPower.enable-charging-limit, allow_active=yes) y UPower lo
// recuerda y lo vuelve a poner en cada arranque. Los topes (75 → 80 %) los pone UPower.
Item {
    id: lc

    // Batería real del portátil (displayDevice es un agregado sin estas propiedades)
    readonly property var dispositivo: UPower.devices.values.find(d => d.isLaptopBattery) || null
    readonly property string ruta: lc.dispositivo ? "/org/freedesktop/UPower/devices/battery_" + lc.dispositivo.nativePath : ""
    readonly property int salud: lc.dispositivo && lc.dispositivo.healthSupported ? Math.round(lc.dispositivo.healthPercentage) : -1

    property bool soportado: false
    property bool activo: false
    property int inicio: 0
    property int fin: 100
    property bool ocupado: setProc.running
    property string error: ""

    onRutaChanged: lc.leer()
    Component.onCompleted: lc.leer()

    function leer() {
        if (lc.ruta === "" || getProc.running) return
        getProc.command = ["gdbus", "call", "--system", "-d", "org.freedesktop.UPower", "-o", lc.ruta,
            "-m", "org.freedesktop.DBus.Properties.GetAll", "org.freedesktop.UPower.Device"]
        getProc.running = true
    }
    function poner(v) {
        if (lc.ruta === "" || setProc.running) return
        lc.error = ""
        setProc.command = ["gdbus", "call", "--system", "-d", "org.freedesktop.UPower", "-o", lc.ruta,
            "-m", "org.freedesktop.UPower.Device.EnableChargeThreshold", v ? "true" : "false"]
        setProc.running = true
    }

    Process {
        id: getProc
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text
                function num(n) { var m = t.match(new RegExp("'" + n + "': <(?:uint32 )?(\\d+)>")); return m ? parseInt(m[1]) : -1 }
                function bool(n) { var m = t.match(new RegExp("'" + n + "': <(true|false)>")); return m ? m[1] === "true" : false }
                lc.soportado = bool("ChargeThresholdSupported")
                lc.activo = bool("ChargeThresholdEnabled")
                lc.inicio = num("ChargeStartThreshold")
                lc.fin = num("ChargeEndThreshold")
            }
        }
    }
    Process {
        id: setProc
        stderr: StdioCollector {
            onStreamFinished: if (this.text.trim() !== "") lc.error = this.text.trim().replace(/^Error: /, "")
        }
        onExited: lc.leer()
    }
    // Por si se cambia desde fuera (otra app, gdbus): relee cada minuto
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: lc.leer()
    }

    function info() {
        return { soportado: lc.soportado, activo: lc.activo, inicio: lc.inicio, fin: lc.fin,
            salud: lc.salud, ruta: lc.ruta, error: lc.error }
    }
}
