import QtQuick
import Quickshell
import Quickshell.Io

// Pantalla: salidas de niri, brillo y luz nocturna.
// Un cambio de salida se prueba sin guardar y pide confirmación (ver root.probarPantalla).
Column {
    id: c

    property var raiz
    spacing: 8

    // ===== Salidas =====
    property var reales: []
    // id = cómo lo reconoce niri aunque cambie de puerto; sin marca y modelo, el nombre del conector
    // Un monitor sin marca ni modelo (virtual, o sin EDID) dice "Unknown": se reconoce por su conector
    function dato(t) { return t && t !== "Unknown" ? t : "" }
    readonly property var salidas: (c.raiz.salidasSimuladas || c.reales).map(o =>
        Object.assign({}, o, { id: c.dato(o.make) && c.dato(o.model) ? o.make + " " + o.model + " " + (o.serial || "Unknown") : o.name }))
    function nombreDe(o) {
        var n = [c.dato(o.make), c.dato(o.model)].filter(x => !!x).join(" ")
        return n || (/^Virtual/i.test(o.name) ? "Monitor virtual" : o.name)
    }
    property string elegida: ""
    // Sin elegir: el principal, si no la pantalla del portátil, si no la primera encendida
    readonly property var activa: c.salidas.find(o => o.name === c.elegida) || c.salidas.find(o => o.id === c.principal)
        || c.salidas.find(o => /^eDP/.test(o.name)) || c.salidas.find(o => !!o.logical) || c.salidas[0] || null
    onSalidasChanged: c.leerGpus()

    // A qué GPU va cada conector
    property var gpus: ({})
    Process {
        id: pGpus
        command: ["sh", "-c", "for d in /sys/class/drm/card*-*; do b=${d##*/}; t=${b%%-*}; v=$(cat \"/sys/class/drm/$t/device/vendor\" 2>/dev/null); echo \"${b#*-} $v\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var g = {}
                text.trim().split("\n").forEach(l => {
                    var p = l.split(" ")
                    g[p[0]] = p[1] === "0x10de" ? "RTX 4050" : p[1] === "0x1002" ? "Radeon 680M" : "Virtual"
                })
                c.gpus = g
            }
        }
    }
    function leerGpus() { if (!pGpus.running) pGpus.running = true }
    function leer() { if (!pSalidas.running) pSalidas.running = true }
    Process {
        id: pSalidas
        command: ["niri", "msg", "-j", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    var l = Object.keys(d).map(k => d[k]).sort((a, b) => a.name < b.name ? -1 : 1)
                    if (JSON.stringify(l) !== JSON.stringify(c.reales)) c.reales = l
                } catch (e) {}
            }
        }
    }
    Timer { interval: 3000; repeat: true; running: true; triggeredOnStart: true; onTriggered: c.leer() }
    Connections {
        target: c.raiz
        function onPantallaResuelta() { c.leer() }
    }
    readonly property int encendidas: c.salidas.filter(s => !!s.logical).length

    function textoModo(m) { return m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3) }
    function modoActual(o) { return o.current_mode !== null && o.current_mode !== undefined ? o.modes[o.current_mode] : null }
    function resoluciones(o) {
        var l = []
        o.modes.forEach(m => { var t = m.width + "x" + m.height; if (l.indexOf(t) < 0) l.push(t) })
        return l
    }
    function frecuencias(o) {
        var a = c.modoActual(o)
        if (!a) return []
        return o.modes.filter(m => m.width === a.width && m.height === a.height).sort((x, y) => y.refresh_rate - x.refresh_rate)
    }
    function normalTransform(t) {
        var v = String(t || "Normal").toLowerCase().replace(/^_/, "")
        return v
    }

    // Cambios: nuevo y vuelta atrás para niri, y lo que se guardará si conservas
    function op(o, clave, valor, args, volver) { return { salida: o.name, id: o.id, clave: clave, valor: valor, args: args, volver: volver } }
    function modo(o, m) {
        var a = c.modoActual(o)
        c.raiz.probarPantalla([c.op(o, "mode", c.textoModo(m), ["mode", c.textoModo(m)], ["mode", a ? c.textoModo(a) : "auto"])],
            "Modo de " + o.name + ": " + m.width + "×" + m.height + " a " + Math.round(m.refresh_rate / 1000) + " Hz")
    }
    function escala(o, v) {
        c.raiz.probarPantalla([c.op(o, "scale", v, ["scale", String(v)], ["scale", String(o.logical.scale)])], "Escala de " + o.name + ": " + v)
    }
    function giro(o, v) {
        c.raiz.probarPantalla([c.op(o, "transform", v, ["transform", v], ["transform", c.normalTransform(o.logical.transform)])], "Orientación de " + o.name)
    }
    function vrr(o, v) {
        c.raiz.probarPantalla([c.op(o, "vrr", v, ["vrr", v ? "on" : "off"], ["vrr", o.vrr_enabled ? "on" : "off"])], "Frecuencia variable de " + o.name)
    }
    function encender(o, v) {
        c.raiz.probarPantalla([c.op(o, "off", !v, [v ? "on" : "off"], [v ? "off" : "on"])], (v ? "Encender " : "Apagar ") + o.name)
    }
    // Colocar varios a la vez, con una sola confirmación
    function ordenar(rects) {
        var ops = []
        rects.forEach(r => {
            var o = c.salidas.find(x => x.name === r.n)
            if (!o || !o.logical || (o.logical.x === r.x && o.logical.y === r.y)) return
            ops.push(c.op(o, "position", [r.x, r.y], ["position", "set", String(r.x), String(r.y)],
                ["position", "set", String(o.logical.x), String(o.logical.y)]))
        })
        if (ops.length) c.raiz.probarPantalla(ops, "Orden de los monitores")
    }
    readonly property string principal: c.raiz.valor("niri.principal") || ""

    component Lista: Flow {
        width: parent ? parent.width : 300
        spacing: 6
    }
    component Rotulo: Text {
        width: parent ? parent.width : 300
        wrapMode: Text.Wrap
        font.family: c.raiz.fuente
        font.pixelSize: 11
        color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.7)
    }

    Etiqueta { s: c.raiz; tema: c.raiz.tema; texto: "Monitores" }
    Ancla {
        raiz: c.raiz
        opId: "pantalla.orden"
        VistaMonitores {
            width: parent.width
            raiz: c.raiz
            salidas: c.salidas.filter(o => !!o.logical)
            elegida: c.activa ? c.activa.name : ""
            principal: c.principal
            onElegir: n => c.elegida = n
            onOrdenado: r => c.ordenar(r)
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: c.salidas.length > 1 ? "Arrastra un monitor para ordenarlo. Haz clic en uno para ver sus ajustes."
                : "Al conectar otro monitor aparecerá aquí, y podrás arrastrarlo para ordenarlo."
            font.family: c.raiz.fuente
            font.pixelSize: 10
            color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.62)
        }
        // Las apagadas no están en el mapa: se eligen aquí
        Flow {
            visible: c.salidas.some(o => !o.logical)
            width: parent.width
            spacing: 6
            Repeater {
                model: c.salidas.filter(o => !o.logical)
                delegate: Chip {
                    required property var modelData
                    s: c.raiz; tema: c.raiz.tema
                    texto: modelData.name + " (apagada)"
                    elegido: !!c.activa && c.activa.name === modelData.name
                    onClic: c.elegida = modelData.name
                }
            }
        }
    }
    Repeater {
        model: c.activa ? [c.activa] : []
        delegate: Ancla {
            id: tarjeta
            required property var modelData
            readonly property var o: modelData
            readonly property var actual: c.modoActual(o)
            raiz: c.raiz
            opId: "pantalla.monitores"

            FilaSimple {
                raiz: c.raiz
                t: c.nombreDe(tarjeta.o)
                a: tarjeta.o.name + (c.gpus[tarjeta.o.name] ? " · " + c.gpus[tarjeta.o.name] : "")
                    + (tarjeta.actual ? " · " + tarjeta.actual.width + "×" + tarjeta.actual.height
                    + " a " + Math.round(tarjeta.actual.refresh_rate / 1000) + " Hz" : " · apagada")
                    + (tarjeta.o.logical && c.encendidas <= 1 ? " · no se puede apagar: es la única encendida" : "")
                Interruptor {
                    tema: c.raiz.tema
                    activo: !!tarjeta.o.logical
                    // Nunca apagar la única encendida: te quedarías sin pantalla
                    enabled: !tarjeta.o.logical || c.encendidas > 1
                    opacity: enabled ? 1 : 0.4
                    onCambiado: v => c.encender(tarjeta.o, v)
                }
            }

            FilaSimple {
                visible: c.salidas.length > 1
                raiz: c.raiz
                t: "Monitor principal"
                a: c.principal === tarjeta.o.id ? "Es este. Aquí arranca el foco al iniciar sesión." : "Aquí arrancará el foco al iniciar sesión."
                BotonTexto {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: c.principal !== tarjeta.o.id
                    tema: c.raiz.tema
                    fuente: c.raiz.fuente
                    texto: "Hacer principal"
                    onClic: c.raiz.cambiar("niri.principal", tarjeta.o.id)
                }
            }

            Column {
                visible: !!tarjeta.o.logical
                width: parent.width
                spacing: 8

                Rotulo { text: "Resolución" }
                Lista {
                    Repeater {
                        model: c.resoluciones(tarjeta.o)
                        delegate: Chip {
                            required property var modelData
                            s: c.raiz; tema: c.raiz.tema
                            texto: modelData.replace("x", "×")
                            elegido: !!tarjeta.actual && modelData === tarjeta.actual.width + "x" + tarjeta.actual.height
                            onClic: {
                                if (elegido) return
                                var res = modelData
                                c.modo(tarjeta.o, tarjeta.o.modes.filter(m => m.width + "x" + m.height === res)
                                    .sort((x, y) => y.refresh_rate - x.refresh_rate)[0])
                            }
                        }
                    }
                }
                Rotulo { text: "Frecuencia" }
                Lista {
                    Repeater {
                        model: c.frecuencias(tarjeta.o)
                        delegate: Chip {
                            required property var modelData
                            s: c.raiz; tema: c.raiz.tema
                            texto: Math.round(modelData.refresh_rate / 1000) + " Hz"
                            elegido: !!tarjeta.actual && modelData.refresh_rate === tarjeta.actual.refresh_rate
                            onClic: if (!elegido) c.modo(tarjeta.o, modelData)
                        }
                    }
                }
                Rotulo { text: "Escala" }
                Lista {
                    Repeater {
                        model: [1, 1.25, 1.5, 1.75, 2, 2.5, 3]
                        delegate: Chip {
                            required property var modelData
                            s: c.raiz; tema: c.raiz.tema
                            texto: modelData + " ×"
                            elegido: !!tarjeta.o.logical && Math.abs(tarjeta.o.logical.scale - modelData) < 0.01
                            onClic: if (!elegido) c.escala(tarjeta.o, modelData)
                        }
                    }
                }
                Rotulo { text: "Orientación" }
                Lista {
                    Repeater {
                        model: [{ v: "normal", t: "Normal" }, { v: "90", t: "90°" }, { v: "180", t: "180°" }, { v: "270", t: "270°" }]
                        delegate: Chip {
                            required property var modelData
                            s: c.raiz; tema: c.raiz.tema
                            texto: modelData.t
                            elegido: !!tarjeta.o.logical && c.normalTransform(tarjeta.o.logical.transform) === modelData.v
                            onClic: if (!elegido) c.giro(tarjeta.o, modelData.v)
                        }
                    }
                }
                FilaSimple {
                    visible: tarjeta.o.vrr_supported === true
                    raiz: c.raiz
                    t: "Frecuencia variable (VRR)"
                    a: "Evita cortes en juegos y vídeo si la pantalla lo admite."
                    Interruptor {
                        tema: c.raiz.tema
                        activo: tarjeta.o.vrr_enabled === true
                        onCambiado: v => c.vrr(tarjeta.o, v)
                    }
                }
            }
        }
    }

    // ===== Brillo =====
    property int brillo: -1
    property int brilloMax: 0
    property int brilloAntes: -1
    Process {
        id: pBrillo
        command: ["brightnessctl", "-m"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var m = /,(\d+)%,/.exec(text)
                if (m) c.brillo = parseInt(m[1])
            }
        }
    }
    Timer {
        id: registrarBrillo
        interval: 800
        onTriggered: {
            if (c.brilloAntes >= 0) c.raiz.registrar("Brillo", [{ clave: "ext.brillo", antes: c.brilloAntes }])
            c.brilloAntes = -1
        }
    }
    function ponerBrillo(p) {
        p = Math.max(1, Math.round(p))
        if (c.brilloAntes < 0) c.brilloAntes = c.brillo
        c.brillo = p
        c.raiz.ejecutar(["brightnessctl", "-q", "set", p + "%"])
        registrarBrillo.restart()
    }
    Etiqueta { visible: c.brillo >= 0; s: c.raiz; tema: c.raiz.tema; texto: "Brillo" }
    Ancla {
        visible: c.brillo >= 0
        raiz: c.raiz
        opId: "pantalla.brillo"
        FilaSimple {
            raiz: c.raiz
            t: "Brillo de la pantalla"
            Deslizador {
                id: deslBrillo
                anchors.verticalCenter: parent.verticalCenter
                width: 220
                tema: c.raiz.tema
                conRueda: false
                valor: c.brillo / 100
                onMovido: v => c.ponerBrillo(v * 100)
                onSoltado: v => c.ponerBrillo(v * 100)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 42
                horizontalAlignment: Text.AlignRight
                text: c.brillo + " %"
                font.family: c.raiz.fuente
                font.pixelSize: 11
                color: c.raiz.tema.surfaceText
            }
        }
    }

    // ===== Luz nocturna (la lleva "hola", que tiene wlsunset) =====
    property var luz: null
    Process {
        id: pLuz
        command: ["qs", "-c", "hola", "ipc", "call", "hola", "luzNocturna", "info"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { c.luz = JSON.parse(text) } catch (e) {} } }
    }
    Timer { id: releerLuz; interval: 400; onTriggered: pLuz.running = true }
    function leerLuz() { releerLuz.restart() }
    readonly property string modoLuz: c.luz ? c.luz.modo : "apagada"

    Etiqueta { s: c.raiz; tema: c.raiz.tema; texto: "Luz nocturna" }
    Ancla {
        raiz: c.raiz
        opId: "pantalla.luz"
        Text {
            visible: !c.luz
            width: parent.width
            wrapMode: Text.Wrap
            text: "No se pudo leer el estado de la barra."
            font.family: c.raiz.fuente
            font.pixelSize: 12
            color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.6)
        }
        Rotulo { text: "Cuándo" }
        Lista {
            Repeater {
                model: [{ v: "apagada", t: "Apagada" }, { v: "sol", t: "Según el sol" }, { v: "siempre", t: "Siempre" }]
                delegate: Chip {
                    required property var modelData
                    s: c.raiz; tema: c.raiz.tema
                    texto: modelData.t
                    elegido: c.modoLuz === modelData.v
                    onClic: {
                        if (elegido) return
                        c.raiz.registrar("Luz nocturna: " + modelData.t, [{ clave: "ext.luzModo", antes: c.modoLuz }])
                        c.raiz.ejecutar(["qs", "-c", "hola", "ipc", "call", "hola", "luzNocturna", modelData.v])
                        c.leerLuz()
                    }
                }
            }
        }
        FilaSimple {
            raiz: c.raiz
            t: "Calidez"
            a: c.luz && c.luz.atardecer ? "Atardecer " + c.luz.atardecer + " · amanecer " + c.luz.amanecer : "Menos kelvin = más cálida. Recomendado: 4000 K."
            Deslizador {
                id: deslLuz
                anchors.verticalCenter: parent.verticalCenter
                width: 220
                tema: c.raiz.tema
                conRueda: false
                valor: c.luz ? (5500 - c.luz.temperatura) / 2500 : 0
                onSoltado: v => {
                    var k = Math.round((5500 - v * 2500) / 100) * 100
                    c.raiz.registrar("Calidez de la luz nocturna", [{ clave: "ext.luzTemp", antes: c.luz.temperatura }])
                    c.raiz.ejecutar(["qs", "-c", "hola", "ipc", "call", "hola", "temperaturaNocturna", String(k)])
                    c.leerLuz()
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 58
                horizontalAlignment: Text.AlignRight
                text: (deslLuz.arrastrando ? Math.round((5500 - deslLuz.vista * 2500) / 100) * 100 : (c.luz ? c.luz.temperatura : 0)) + " K"
                font.family: c.raiz.fuente
                font.pixelSize: 11
                color: c.raiz.tema.surfaceText
            }
        }
        // La ubicación vive en hola/luz-nocturna.json, que nunca sube al repo
        FilaSimple {
            raiz: c.raiz
            t: "Ubicación para calcular el sol"
            a: "Latitud y longitud. Solo se guardan en este equipo."
            Repeater {
                model: [{ k: "lat", min: -90, max: 90 }, { k: "lon", min: -180, max: 180 }]
                delegate: Rectangle {
                    id: cajaUbic
                    required property var modelData
                    width: 84
                    height: 30
                    radius: 10
                    color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.07)
                    border.width: 1
                    border.color: campoUbic.activeFocus ? c.raiz.tema.primary : c.raiz.alfa(c.raiz.tema.primary, 0.35)
                    TextInput {
                        id: campoUbic
                        anchors.fill: parent
                        anchors.margins: 6
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        validator: DoubleValidator { bottom: cajaUbic.modelData.min; top: cajaUbic.modelData.max; decimals: 4; notation: DoubleValidator.StandardNotation; locale: "C" }
                        font.family: c.raiz.fuente
                        font.pixelSize: 12
                        color: c.raiz.tema.surfaceText
                        text: c.luz && c.luz[cajaUbic.modelData.k] !== undefined ? String(c.luz[cajaUbic.modelData.k]) : ""
                        onAccepted: {
                            var n = Number(text)
                            var lat = cajaUbic.modelData.k === "lat" ? n : c.luz.lat
                            var lon = cajaUbic.modelData.k === "lon" ? n : c.luz.lon
                            c.raiz.registrar("Ubicación de la luz nocturna", [{ clave: "ext.luzUbic", lat: c.luz.lat, lon: c.luz.lon }])
                            c.raiz.ejecutar(["qs", "-c", "hola", "ipc", "call", "hola", "ubicacionNocturna", String(lat), String(lon)])
                            c.leerLuz()
                            c.raiz.soltarFoco()
                        }
                    }
                }
            }
        }
    }
}
