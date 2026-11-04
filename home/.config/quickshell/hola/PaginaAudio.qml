import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Página Audio: volumen general, por aplicación y elegir salida/entrada (PipeWire)
Item {
    id: a

    property var s
    property var tema
    property bool activa: false
    signal atras()

    implicitHeight: col.implicitHeight

    property var nodos: Pipewire.nodes.values
    property var salidas: a.nodos.filter(n => n.audio && !n.isStream && n.isSink)
    property var entradas: a.nodos.filter(n => n.audio && !n.isStream && !n.isSink)
    // Sin cava: solo escucha para las ondas de la píldora de música, no es una app con sonido
    property var apps: a.nodos.filter(n => n.audio && n.isStream && !n.isSink && n.name !== "cava")
    property var sink: Pipewire.defaultAudioSink
    property var source: Pipewire.defaultAudioSource

    // Mantiene vivos los datos de volumen de lo que se muestra
    PwObjectTracker {
        objects: a.activa ? a.apps.concat(a.salidas, a.entradas) : []
    }

    function nombreDispositivo(n) {
        return n.description || n.nickname || n.name || "Dispositivo"
    }

    function nombreApp(n) {
        var p = n.properties || {}
        return p["application.name"] || p["media.name"] || n.name || "App"
    }

    function iconoApp(n) {
        var p = n.properties || {}
        var ic = p["application.icon-name"] || p["application.process.binary"] || "audio-x-generic"
        return Quickshell.iconPath(ic.toLowerCase(), "audio-x-generic")
    }

    function poner(n, v) {
        if (!n || !n.audio) return
        n.audio.muted = false
        n.audio.volume = Math.max(0, Math.min(1, v))
    }

    function silenciar(n) {
        if (n && n.audio) n.audio.muted = !n.audio.muted
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        Encabezado {
            tema: a.tema
            titulo: "Audio"
            onAtras: a.atras()
        }

        Flickable {
            width: parent.width
            height: Math.min(cuerpo.implicitHeight, 470)
            contentHeight: cuerpo.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: cuerpo
                width: parent.width
                spacing: 8

                // ---------- Volumen general ----------
                Etiqueta { s: a.s; tema: a.tema; texto: "Salida general" }
                FilaVolumen {
                    s: a.s
                    tema: a.tema
                    width: cuerpo.width
                    nodo: a.sink
                    icono: a.s.ic(a.sink && a.sink.audio && a.sink.audio.muted ? 0xF075F : 0xF057E)
                    onCambiar: v => a.poner(a.sink, v)
                    onAlternarMudo: a.silenciar(a.sink)
                }

                // ---------- Por aplicación ----------
                Etiqueta { s: a.s; tema: a.tema; texto: "Aplicaciones" }
                Text {
                    visible: a.apps.length === 0
                    leftPadding: 4
                    text: "Ninguna aplicación está sonando"
                    font.family: a.s.fuente
                    font.pixelSize: 12
                    color: a.s.alfa(a.tema.surfaceText, 0.55)
                }
                Repeater {
                    model: a.apps
                    delegate: FilaVolumen {
                        required property var modelData
                        s: a.s
                        tema: a.tema
                        width: cuerpo.width
                        nodo: modelData
                        imagen: a.iconoApp(modelData)
                        titulo: a.nombreApp(modelData)
                        onCambiar: v => a.poner(modelData, v)
                        onAlternarMudo: a.silenciar(modelData)
                    }
                }

                // ---------- Dispositivo de salida ----------
                Etiqueta { s: a.s; tema: a.tema; texto: "Salida" }
                Repeater {
                    model: a.salidas
                    delegate: FilaOpcion {
                        required property var modelData
                        s: a.s
                        tema: a.tema
                        width: cuerpo.width
                        icono: a.s.ic(/headphone|headset|auricular/i.test(a.nombreDispositivo(modelData)) ? 0xF02CB : 0xF04C3)
                        texto: a.nombreDispositivo(modelData)
                        elegido: a.sink === modelData
                        onClic: Pipewire.preferredDefaultAudioSink = modelData
                    }
                }

                // ---------- Dispositivo de entrada ----------
                Etiqueta { s: a.s; tema: a.tema; texto: "Micrófono" }
                FilaVolumen {
                    visible: a.source !== null
                    s: a.s
                    tema: a.tema
                    width: cuerpo.width
                    nodo: a.source
                    icono: a.s.ic(a.source && a.source.audio && a.source.audio.muted ? 0xF036D : 0xF036C)
                    onCambiar: v => a.poner(a.source, v)
                    onAlternarMudo: a.silenciar(a.source)
                }
                Repeater {
                    model: a.entradas
                    delegate: FilaOpcion {
                        required property var modelData
                        s: a.s
                        tema: a.tema
                        width: cuerpo.width
                        icono: a.s.ic(0xF036C)
                        texto: a.nombreDispositivo(modelData)
                        elegido: a.source === modelData
                        onClic: Pipewire.preferredDefaultAudioSource = modelData
                    }
                }
            }
        }
    }
}
