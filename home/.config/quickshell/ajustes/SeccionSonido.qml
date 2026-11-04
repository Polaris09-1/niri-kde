import QtQuick
import Quickshell.Services.Pipewire

// Sonido: lo mismo que el panel y más sitio. Va directo a PipeWire; cada cambio entra en el historial.
Column {
    id: c

    property var raiz

    spacing: 8

    readonly property var nodos: Pipewire.nodes.values
    readonly property var salidas: c.nodos.filter(n => n.audio && !n.isStream && n.isSink)
    readonly property var entradas: c.nodos.filter(n => n.audio && !n.isStream && !n.isSink)
    // isSink en un flujo = recibe el sonido de la app que reproduce; cava (solo escucha) y los micrófonos no lo son
    readonly property var apps: c.nodos.filter(n => n.audio && n.isStream && n.isSink)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    PwObjectTracker { objects: c.apps.concat(c.salidas, c.entradas) }

    function nombre(n) { return n.description || n.nickname || n.name || "Dispositivo" }
    function nombreApp(n) {
        var p = n.properties || {}
        return p["application.name"] || p["media.name"] || n.name || "Aplicación"
    }
    function iconoApp(n) {
        var p = n.properties || {}
        var ic = p["application.icon-name"] || p["application.process.binary"] || "audio-x-generic"
        return c.raiz.rutaIcono(ic.toLowerCase())
    }

    // Grupo de filas con ancla para el buscador
    component Ancla: Rectangle {
        property string opId: ""
        default property alias dentro: cuerpo.data
        width: parent ? parent.width : 400
        height: cuerpo.implicitHeight + 20
        radius: 14
        readonly property bool resaltada: c.raiz.resaltada === opId
        color: c.raiz.alfa(c.raiz.tema.primary, resaltada ? 0.28 : 0.07)
        border.color: resaltada ? c.raiz.tema.primary : "transparent"
        border.width: 1.5
        Behavior on color { ColorAnimation { duration: 200 } }
        Component.onCompleted: c.raiz.registrarFila(opId, this)
        Component.onDestruction: c.raiz.quitarFila(opId, this)
        Column { id: cuerpo; x: 12; y: 10; width: parent.width - 24; spacing: 6 }
    }
    component Vacio: Text {
        width: parent ? parent.width : 300
        wrapMode: Text.Wrap
        font.family: c.raiz.fuente
        font.pixelSize: 12
        color: c.raiz.alfa(c.raiz.tema.surfaceText, 0.6)
    }

    Etiqueta { s: c.raiz; tema: c.raiz.tema; texto: "Salida" }
    Ancla {
        opId: "sonido.volSalida"
        FilaVolumen {
            s: c.raiz; tema: c.raiz.tema; conRueda: false
            width: parent.width
            nodo: c.sink
            icono: c.raiz.ic(c.sink && c.sink.audio && c.sink.audio.muted ? 0xF075F : 0xF057E)
            titulo: c.sink ? c.nombre(c.sink) : "Sin salida"
            onCambiar: v => c.raiz.ponerVolumen(c.sink, v, "Volumen de salida")
            onAlternarMudo: c.raiz.alternarMudo(c.sink, "Silencio de la salida")
        }
    }
    Ancla {
        opId: "sonido.salida"
        Repeater {
            model: c.salidas
            delegate: FilaOpcion {
                required property var modelData
                s: c.raiz; tema: c.raiz.tema
                width: parent ? parent.width : 300
                icono: c.raiz.ic(/headphone|headset|auricular|bluetooth/i.test(c.nombre(modelData)) ? 0xF02CB : 0xF04C3)
                texto: c.nombre(modelData)
                elegido: c.sink === modelData
                onClic: c.raiz.ponerDispositivo("sonido.salida", modelData, "Salida de sonido")
            }
        }
    }

    Etiqueta { s: c.raiz; tema: c.raiz.tema; texto: "Aplicaciones" }
    Ancla {
        opId: "sonido.apps"
        Vacio { visible: c.apps.length === 0; text: "Ninguna aplicación está sonando." }
        Repeater {
            model: c.apps
            delegate: FilaVolumen {
                required property var modelData
                s: c.raiz; tema: c.raiz.tema; conRueda: false
                width: parent ? parent.width : 300
                nodo: modelData
                imagen: c.iconoApp(modelData)
                titulo: c.nombreApp(modelData)
                onCambiar: v => c.raiz.ponerVolumen(modelData, v, "Volumen de " + c.nombreApp(modelData))
                onAlternarMudo: c.raiz.alternarMudo(modelData, "Silencio de " + c.nombreApp(modelData))
            }
        }
    }

    Etiqueta { s: c.raiz; tema: c.raiz.tema; texto: "Entrada" }
    Ancla {
        opId: "sonido.volEntrada"
        Vacio { visible: !c.source; text: "No hay ningún micrófono." }
        FilaVolumen {
            visible: !!c.source
            s: c.raiz; tema: c.raiz.tema; conRueda: false
            width: parent.width
            nodo: c.source
            icono: c.raiz.ic(c.source && c.source.audio && c.source.audio.muted ? 0xF036D : 0xF036C)
            titulo: c.source ? c.nombre(c.source) : ""
            onCambiar: v => c.raiz.ponerVolumen(c.source, v, "Volumen del micrófono")
            onAlternarMudo: c.raiz.alternarMudo(c.source, "Silencio del micrófono")
        }
    }
    Ancla {
        opId: "sonido.entrada"
        Vacio { visible: c.entradas.length === 0; text: "No hay dispositivos de entrada." }
        Repeater {
            model: c.entradas
            delegate: FilaOpcion {
                required property var modelData
                s: c.raiz; tema: c.raiz.tema
                width: parent ? parent.width : 300
                icono: c.raiz.ic(0xF036C)
                texto: c.nombre(modelData)
                elegido: c.source === modelData
                onClic: c.raiz.ponerDispositivo("sonido.entrada", modelData, "Entrada de sonido")
            }
        }
    }
}
