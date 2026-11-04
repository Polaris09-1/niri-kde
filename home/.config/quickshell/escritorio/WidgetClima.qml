import Quickshell
import Quickshell.Io
import QtQuick

// Clima con Open-Meteo (sin cuenta ni API key). Solo se envían las coordenadas de la ciudad elegida.
// La ciudad vive en clima-ciudad.json (no sube al repo). Última respuesta en ~/.cache/escritorio/clima.json:
// sin conexión sigue mostrando eso con su antigüedad. Actualiza cada 30 min; si una ventana tapa el
// escritorio no consulta nada y se pone al día al destaparse.
TarjetaWidget {
    id: w
    required property string fuente
    property string tam: "M"
    property var opciones: ({})
    property bool activo: true
    readonly property bool usaTarjeta: true

    readonly property string rutaCiudad: Quickshell.env("HOME") + "/.config/quickshell/escritorio/clima-ciudad.json"
    readonly property string rutaCache: Quickshell.env("HOME") + "/.cache/escritorio/clima.json"
    readonly property int cadaMs: 30 * 60 * 1000
    readonly property int reintentoMs: 5 * 60 * 1000
    readonly property bool conPronostico: w.opciones.pronostico !== false
    readonly property bool fahrenheit: w.opciones.fahrenheit === true

    property var ciudad: null               // { nombre, region, lat, lon }
    property var datos: null                // respuesta de Open-Meteo
    property real recibido: 0               // ms de la última respuesta buena
    property real intentado: 0
    property bool fallo: false
    property var resultados: []             // búsqueda de ciudad
    property bool buscando: false

    function grados(c) { return Math.round(w.fahrenheit ? c * 9 / 5 + 32 : c) + "°" }

    function descripcion(c) {
        if (c === 0) return "Despejado"
        if (c === 1) return "Casi despejado"
        if (c === 2) return "Parcialmente nublado"
        if (c === 3) return "Nublado"
        if (c === 45 || c === 48) return "Niebla"
        if (c >= 51 && c <= 55) return "Llovizna"
        if (c === 56 || c === 57) return "Llovizna helada"
        if (c >= 61 && c <= 65) return "Lluvia"
        if (c === 66 || c === 67) return "Lluvia helada"
        if (c >= 71 && c <= 77) return "Nieve"
        if (c >= 80 && c <= 82) return "Chubascos"
        if (c === 85 || c === 86) return "Chubascos de nieve"
        if (c === 95) return "Tormenta"
        if (c === 96 || c === 99) return "Tormenta con granizo"
        return "—"
    }
    function icono(c, dia) {
        if (c === 0 || c === 1) return String.fromCodePoint(dia ? 0xF0599 : 0xF0594)
        if (c === 2) return String.fromCodePoint(dia ? 0xF0595 : 0xF0F31)
        if (c === 3) return String.fromCodePoint(0xF0590)
        if (c === 45 || c === 48) return String.fromCodePoint(0xF0591)
        if ((c >= 51 && c <= 57) || c === 61 || c === 80) return String.fromCodePoint(0xF0597)
        if ((c >= 63 && c <= 67) || c === 81 || c === 82) return String.fromCodePoint(0xF0596)
        if ((c >= 71 && c <= 77) || c === 85 || c === 86) return String.fromCodePoint(0xF0598)
        if (c === 95) return String.fromCodePoint(0xF0593)
        if (c === 96 || c === 99) return String.fromCodePoint(0xF067E)
        return String.fromCodePoint(0xF0590)
    }

    // Próximas horas y próximos días a partir de la respuesta
    readonly property var horas: {
        if (!w.datos || !w.datos.hourly) return []
        var h = w.datos.hourly, ahora = w.datos.current.time.slice(0, 13)
        var i = h.time.findIndex(t => t.slice(0, 13) === ahora)
        if (i < 0) return []
        var l = []
        for (var k = i + 1; k <= i + 5 && k < h.time.length; k++)
            l.push({ t: h.time[k].slice(11, 13) + "h", c: h.temperature_2m[k], w: h.weather_code[k], dia: h.is_day[k] === 1 })
        return l
    }
    readonly property var dias: {
        if (!w.datos || !w.datos.daily) return []
        var d = w.datos.daily, l = []
        for (var k = 1; k < d.time.length; k++) {
            var p = d.time[k].split("-")
            var f = new Date(+p[0], +p[1] - 1, +p[2]).toLocaleDateString(Qt.locale("es_EC"), "ddd")
            l.push({ t: f.charAt(0).toUpperCase() + f.slice(1), w: d.weather_code[k], max: d.temperature_2m_max[k],
                     min: d.temperature_2m_min[k], p: d.precipitation_probability_max[k] })
        }
        return l
    }
    readonly property string antiguedad: {
        reloj.date
        if (!w.recibido) return ""
        var m = Math.floor((Date.now() - w.recibido) / 60000)
        if (m < 60) return "hace " + m + " min"
        if (m < 2880) return "hace " + Math.floor(m / 60) + " h"
        return "hace " + Math.floor(m / 1440) + " días"
    }

    function consultar() {
        if (!w.ciudad || pConsulta.running) return
        w.intentado = Date.now()
        var c = w.ciudad
        pConsulta.lat = c.lat
        pConsulta.lon = c.lon
        pConsulta.command = ["curl", "-sS", "--fail", "--max-time", "20", "-G", "https://api.open-meteo.com/v1/forecast",
            "--data-urlencode", "latitude=" + c.lat, "--data-urlencode", "longitude=" + c.lon,
            "-d", "current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day",
            "-d", "hourly=temperature_2m,weather_code,is_day",
            "-d", "daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
            "-d", "forecast_days=6", "-d", "timezone=auto"]
        pConsulta.running = true
    }
    function buscarCiudad(texto) {
        var t = texto.trim()
        if (t.length < 2) { w.resultados = []; return }
        pBusca.command = ["curl", "-sS", "--fail", "--max-time", "15", "-G", "https://geocoding-api.open-meteo.com/v1/search",
            "--data-urlencode", "name=" + t, "-d", "count=6", "-d", "language=es", "-d", "format=json"]
        w.buscando = true
        pBusca.running = false
        pBusca.running = true
    }
    function elegirCiudad(r) {
        w.ciudad = r
        w.resultados = []
        w.datos = null
        w.recibido = 0
        archivoCiudad.setText(JSON.stringify(r) + "\n")
        w.consultar()
    }

    SystemClock { id: reloj; enabled: w.activo; precision: SystemClock.Minutes }
    // Cada minuto mira si toca actualizar; también cubre volver de una suspensión o del estado tapado
    onActivoChanged: revisar()
    Connections { target: reloj; function onDateChanged() { w.revisar() } }
    function revisar() {
        if (!w.activo || !w.ciudad) return
        var ahora = Date.now()
        if (ahora - w.recibido >= w.cadaMs && ahora - w.intentado >= (w.fallo ? w.reintentoMs : 60000)) w.consultar()
    }

    FileView {
        id: archivoCiudad
        path: w.rutaCiudad
        printErrors: false
        onLoaded: {
            try { w.ciudad = JSON.parse(text()); archivoCache.reload() }
            catch (e) { console.warn("clima: clima-ciudad.json no se pudo leer") }
        }
    }
    FileView {
        id: archivoCache
        path: w.rutaCache
        printErrors: false
        blockLoading: false
        onLoaded: {
            try {
                var c = JSON.parse(text())
                if (w.ciudad && Math.abs(c.lat - w.ciudad.lat) < 0.01 && Math.abs(c.lon - w.ciudad.lon) < 0.01) {
                    w.datos = c.datos
                    w.recibido = c.recibido
                }
            } catch (e) {}
            w.revisar()
        }
        onLoadFailed: w.revisar()
    }
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.cache/escritorio"])

    Process {
        id: pConsulta
        property real lat: 0
        property real lon: 0
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    if (!d.current) throw "sin datos"
                    w.datos = d
                    w.recibido = Date.now()
                    w.fallo = false
                    archivoCache.setText(JSON.stringify({ lat: pConsulta.lat, lon: pConsulta.lon, recibido: w.recibido, datos: d }))
                } catch (e) {
                    w.fallo = true
                }
            }
        }
        onExited: code => { if (code !== 0) w.fallo = true }
    }
    Process {
        id: pBusca
        stdout: StdioCollector {
            onStreamFinished: {
                w.buscando = false
                try {
                    var r = JSON.parse(text).results || []
                    w.resultados = r.map(x => ({ nombre: x.name, lat: x.latitude, lon: x.longitude,
                        region: [x.admin1, x.country].filter(v => v).join(", ") }))
                } catch (e) { w.resultados = [] }
            }
        }
    }

    // ----- Sin ciudad -----
    Text {
        visible: !w.ciudad
        anchors.fill: parent
        wrapMode: Text.Wrap
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        text: "Elige una ciudad con ⚙ en el modo edición"
        font.family: w.fuente; font.pixelSize: 12
        color: w.tema.surfaceText
    }

    Column {
        visible: !!w.ciudad
        anchors.fill: parent
        spacing: 8

        // Ahora
        Item {
            width: parent.width
            height: w.tam === "S" ? parent.height : 84
            Column {
                anchors.left: parent.left
                anchors.top: parent.top
                spacing: 0
                Text {
                    width: w.width - 2 * w.relleno
                    elide: Text.ElideRight
                    text: w.ciudad ? w.ciudad.nombre : ""
                    font.family: w.fuente; font.pixelSize: 12; font.bold: true
                    color: w.tema.surfaceText
                }
                Text {
                    text: w.datos ? w.grados(w.datos.current.temperature_2m) : "—"
                    font.family: w.fuente; font.pixelSize: w.tam === "S" ? 46 : 42; font.weight: Font.Light
                    color: w.tema.surfaceText
                }
            }
            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 18
                text: w.datos ? w.icono(w.datos.current.weather_code, w.datos.current.is_day === 1) : ""
                font.family: w.fuente; font.pixelSize: w.tam === "S" ? 38 : 44
                color: w.tema.primary
            }
            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                elide: Text.ElideRight
                text: !w.datos ? (w.fallo ? "Sin conexión" : "Cargando…")
                    : w.fallo ? "Sin conexión · " + w.antiguedad
                    : w.descripcion(w.datos.current.weather_code)
                      + (w.tam === "S" ? "" : " · sensación " + w.grados(w.datos.current.apparent_temperature)
                                              + " · " + w.datos.current.relative_humidity_2m + " %")
                font.family: w.fuente; font.pixelSize: 11
                color: w.tema.surfaceText
                opacity: 0.8
            }
        }

        // Próximas horas
        Row {
            visible: w.tam !== "S" && w.conPronostico && w.horas.length > 0
            width: parent.width
            Repeater {
                model: w.horas
                delegate: Column {
                    id: ch
                    required property var modelData
                    width: parent.width / 5
                    spacing: 1
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: ch.modelData.t; font.family: w.fuente; font.pixelSize: 10; color: w.tema.surfaceText; opacity: 0.75 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: w.icono(ch.modelData.w, ch.modelData.dia); font.family: w.fuente; font.pixelSize: 17; color: w.tema.primary }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: w.grados(ch.modelData.c); font.family: w.fuente; font.pixelSize: 11; color: w.tema.surfaceText }
                }
            }
        }

        // Próximos días
        Column {
            visible: w.tam === "L" && w.conPronostico
            width: parent.width
            spacing: 2
            Repeater {
                model: w.dias
                delegate: Item {
                    id: cd
                    required property var modelData
                    width: parent.width
                    height: 25
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 44; text: cd.modelData.t; font.family: w.fuente; font.pixelSize: 11; color: w.tema.surfaceText }
                    Text { anchors.verticalCenter: parent.verticalCenter; x: 46; text: w.icono(cd.modelData.w, true); font.family: w.fuente; font.pixelSize: 16; color: w.tema.primary }
                    Text { anchors.verticalCenter: parent.verticalCenter; x: 74; text: cd.modelData.p !== null ? cd.modelData.p + " %" : ""; font.family: w.fuente; font.pixelSize: 10; color: w.tema.surfaceText; opacity: 0.7 }
                    Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; text: w.grados(cd.modelData.min) + "  " + w.grados(cd.modelData.max); font.family: w.fuente; font.pixelSize: 11; color: w.tema.surfaceText }
                }
            }
        }
    }
}
