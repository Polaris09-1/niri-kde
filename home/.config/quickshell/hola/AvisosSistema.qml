import QtQuick
import Quickshell

// Avisos propios del sistema que llevan a su página del panel (pista x-hola-destino, ver Avisos.qml):
// - Batería baja al bajar del 15 % y del 5 % sin cargar → página Energía.
// - Wi-Fi conectado, cambiado o desconectado → página Wi-Fi.
// - Bluetooth: un dispositivo emparejado se conecta o se desconecta → página Bluetooth.
// Durante los primeros 15 s tras arrancar o recargar no avisa: al cambiar de fondo, matugen recarga
// la barra y los avisos se repetirían. Probar sin tocar nada: hola probarAvisoSistema <tipo> <valor>.
Scope {
    id: a

    property int bateria: 0
    property bool cargando: false
    property string wifi: ""
    property var adaptador: null     // Bluetooth.defaultAdapter

    readonly property var umbrales: [15, 5]
    property bool listo: false
    property int bateriaPrevia: -1
    property string wifiPrevio: ""
    property var btPrevios: []

    Timer {
        interval: 15000
        running: true
        onTriggered: {
            a.bateriaPrevia = a.bateria
            a.wifiPrevio = a.wifi
            a.btPrevios = a.btActuales()
            a.listo = true
        }
    }

    function avisar(app, icono, destino, titulo, texto, urgente) {
        var cmd = ["notify-send", "-a", app, "-i", icono, "-h", "string:x-hola-destino:" + destino]
        if (urgente) cmd.push("-u", "critical")
        else cmd.push("-t", "5000")
        Quickshell.execDetached(cmd.concat(["--", titulo, texto]))
    }

    // ----- Batería -----
    function revisarBateria(pct, carga) {
        if (pct <= 0) return     // sin batería (o aún sin leer)
        if (!carga && a.bateriaPrevia > 0) {
            for (var i = 0; i < a.umbrales.length; i++) {
                var u = a.umbrales[i]
                if (a.bateriaPrevia > u && pct <= u) {
                    a.avisar("Energía", u <= 5 ? "battery-empty" : "battery-caution", "pagina:energia",
                             "Batería al " + pct + " %",
                             u <= 5 ? "Conecta el cargador ya: el equipo puede apagarse."
                                    : "Conecta el cargador pronto.", u <= 5)
                    break
                }
            }
        }
        a.bateriaPrevia = pct
    }
    onBateriaChanged: if (a.listo) a.revisarBateria(a.bateria, a.cargando)
    // Al enchufar, la próxima bajada vuelve a avisar
    onCargandoChanged: if (a.listo && a.cargando) a.bateriaPrevia = 100

    // ----- Wi-Fi -----
    function revisarWifi(nombre) {
        var antes = a.wifiPrevio
        a.wifiPrevio = nombre
        if (nombre === antes) return
        if (nombre === "")
            a.avisar("Wi-Fi", "network-wireless-offline", "pagina:wifi", "Wi-Fi desconectado", "Ya no estás conectado a " + antes + ".", false)
        else
            a.avisar("Wi-Fi", "network-wireless", "pagina:wifi", "Wi-Fi conectado", "Conectado a " + nombre + ".", false)
    }
    onWifiChanged: if (a.listo) a.revisarWifi(a.wifi)

    // ----- Bluetooth -----
    function btActuales() {
        if (!a.adaptador) return []
        return a.adaptador.devices.values.filter(d => d.connected && d.paired).map(d => d.name || d.address)
    }
    readonly property string btFirma: {
        if (!a.adaptador) return ""
        return a.adaptador.devices.values.filter(d => d.connected && d.paired).map(d => d.name || d.address).sort().join("\n")
    }
    function revisarBt(ahora) {
        var antes = a.btPrevios
        a.btPrevios = ahora
        ahora.filter(n => antes.indexOf(n) < 0).forEach(n =>
            a.avisar("Bluetooth", "bluetooth-active", "pagina:bluetooth", "Bluetooth conectado", n + " está conectado.", false))
        antes.filter(n => ahora.indexOf(n) < 0).forEach(n =>
            a.avisar("Bluetooth", "bluetooth-disabled", "pagina:bluetooth", "Bluetooth desconectado", n + " se desconectó.", false))
    }
    onBtFirmaChanged: if (a.listo) a.revisarBt(a.btActuales())

    // Para el IPC de prueba: pasa valores inventados por la misma lógica
    function probar(tipo, valor) {
        if (tipo === "bateria") {
            var partes = valor.split(",")
            a.bateriaPrevia = parseInt(partes[0])
            a.revisarBateria(parseInt(partes[1]), false)
        } else if (tipo === "wifi") {
            var w = valor.split(",")
            a.wifiPrevio = w[0]
            a.revisarWifi(w[1] || "")
        } else if (tipo === "bt") {
            var b = valor.split(",")
            a.btPrevios = b[0] ? b[0].split("+") : []
            a.revisarBt(b[1] ? b[1].split("+") : [])
            a.btPrevios = a.btActuales()
        } else return "tipos: bateria <antes,ahora> · wifi <antes,ahora> · bt <a+b,a>"
        return "ok"
    }
}
