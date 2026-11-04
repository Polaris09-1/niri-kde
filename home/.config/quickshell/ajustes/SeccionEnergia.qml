import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Energía: perfiles, límite de carga y cafeína. Los tiempos de bloqueo los pinta el catálogo debajo.
Column {
    id: c

    property var raiz
    spacing: 8

    // ----- Perfil -----
    readonly property string perfil: PowerProfiles.profile === PowerProfile.PowerSaver ? "ahorro"
        : PowerProfiles.profile === PowerProfile.Performance ? "rendimiento" : "equilibrado"

    Etiqueta { s: c.raiz; tema: c.raiz.tema; texto: "Modo de energía" }
    Ancla {
        raiz: c.raiz
        opId: "energia.perfil"
        Flow {
            width: parent.width
            spacing: 6
            Repeater {
                model: [{ v: "ahorro", t: "Ahorro" }, { v: "equilibrado", t: "Equilibrado" }, { v: "rendimiento", t: "Rendimiento" }]
                delegate: Chip {
                    required property var modelData
                    visible: modelData.v !== "rendimiento" || PowerProfiles.hasPerformanceProfile
                    s: c.raiz; tema: c.raiz.tema
                    texto: modelData.t
                    elegido: c.perfil === modelData.v
                    onClic: {
                        if (elegido) return
                        c.raiz.registrar("Modo de energía: " + modelData.t, [{ clave: "ext.perfil", antes: c.perfil }])
                        c.raiz.ponerPerfil(modelData.v)
                    }
                }
            }
        }
    }

    // ----- Batería -----
    property var limite: null
    Process {
        id: pLimite
        command: ["qs", "-c", "hola", "ipc", "call", "hola", "bateriaLimite", "info"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { c.limite = JSON.parse(text) } catch (e) {} } }
    }
    Timer { id: releerLimite; interval: 1500; onTriggered: pLimite.running = true }

    Etiqueta { visible: !!c.limite && c.limite.soportado === true; s: c.raiz; tema: c.raiz.tema; texto: "Batería" }
    Ancla {
        visible: !!c.limite && c.limite.soportado === true
        raiz: c.raiz
        opId: "energia.limite"
        FilaSimple {
            raiz: c.raiz
            t: "Cargar solo hasta el " + (c.limite ? c.limite.fin : 80) + " %"
            a: "Alarga la vida de la batería si pasas mucho tiempo enchufado. Apágalo antes de un viaje."
                + (c.limite && c.limite.salud >= 0 ? " Salud: " + c.limite.salud + " % de su capacidad original." : "")
            Interruptor {
                tema: c.raiz.tema
                activo: !!c.limite && c.limite.activo === true
                onCambiado: v => {
                    c.raiz.registrar("Límite de carga", [{ clave: "ext.limite", antes: c.limite.activo }])
                    c.raiz.ejecutar(["qs", "-c", "hola", "ipc", "call", "hola", "bateriaLimite", v ? "si" : "no"])
                    releerLimite.restart()
                }
            }
        }
    }

    // ----- Cafeína (la lleva "bloqueo") -----
    property bool cafeina: false
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/bloqueo-despierto.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { c.cafeina = JSON.parse(text()).cafeina === true } catch (e) {} }
    }
    Etiqueta { s: c.raiz; tema: c.raiz.tema; texto: "Cafeína" }
    Ancla {
        raiz: c.raiz
        opId: "energia.cafeina"
        FilaSimple {
            raiz: c.raiz
            t: "Mantener despierto"
            a: "No se bloquea ni se suspende solo hasta que lo apagues o reinicies el equipo."
            Interruptor {
                tema: c.raiz.tema
                activo: c.cafeina
                onCambiado: v => {
                    c.raiz.registrar("Mantener despierto", [{ clave: "ext.cafeina", antes: c.cafeina }])
                    c.raiz.ejecutar(["qs", "-c", "bloqueo", "ipc", "call", "bloqueo", "cafeina", v ? "si" : "no"])
                }
            }
        }
    }
}
