import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

// Popups de notificaciones: arriba a la derecha, debajo de la barra.
// Entran deslizándose desde el borde; al irse salen hacia la derecha y los demás suben.
PanelWindow {
    screen: Principal.porNombre(w.salida) || Principal.pantalla
    id: w

    // Salen en el monitor enfocado cuando llega el aviso; si ya hay alguno a la vista, se van todos con el último
    property string salida: ""
    Connections {
        target: w.av
        function onVaAMostrar() {
            if (w.salida === w.s.salidaEnfocada) return
            w.salida = w.s.salidaEnfocada
            w.recrearTarjetas()
        }
    }
    // Al recrearse la ventana (otro monitor, o cambian las pantallas) las tarjetas que había siguen en la lista pero dejan de
    // verse: se vuelven a crear, entran deslizándose y su tiempo empieza de nuevo
    function recrearTarjetas() {
        if (w.av.emergentes.count === 0) return
        repetidor.model = null
        repetidor.model = Qt.binding(() => w.av.emergentes)
    }
    Connections {
        target: Principal
        function onListaChanged() { if (Principal.lista) w.recrearTarjetas() }
    }

    property var s
    property var tema
    property var av
    property date ahora: new Date()
    property bool oculto: false        // p. ej. con el panel del reloj abierto (ahí ya se ven)

    anchors {
        top: true
        right: true
    }
    margins.top: 4
    margins.right: 4
    implicitWidth: 400
    // Alto fijo (la máscara deja pasar los clics fuera de las tarjetas): redimensionar
    // la ventana en cada fotograma de la animación daría tirones
    implicitHeight: w.screen ? Math.round(w.screen.height * 0.85) : 900
    visible: Principal.lista && (w.av.emergentes.count > 0 && !w.oculto)
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hola-avisos"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Solo las tarjetas atrapan el mouse; el resto deja pasar los clics
    mask: Region { item: pila }

    Column {
        id: pila
        x: 12
        y: 8
        width: w.width - 24
        spacing: 0

        Repeater {
            id: repetidor
            model: w.av.emergentes

            delegate: Item {
                id: hueco
                required property var model
                required property int index
                property var fila: model
                property bool entrado: false
                property bool saliendo: model.saliendo
                // 0..1: cuánto espacio ocupa (para que los demás se muevan suave)
                property real alto: 0
                width: pila.width
                height: (tarjeta.implicitHeight + 10) * alto
                clip: false

                // Una tarjeta recreada puede venir ya de salida: entonces no entra, solo se va
                Component.onCompleted: { if (saliendo) { alto = 1; desliz.x = 0; salir.start() } else entrar.start() }
                onSaliendoChanged: if (saliendo) { entrar.stop(); salir.start() }

                ParallelAnimation {
                    id: entrar
                    NumberAnimation { target: hueco; property: "alto"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        PauseAnimation { duration: 60 }
                        NumberAnimation { target: desliz; property: "x"; from: pila.width + 30; to: 0; duration: 480; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                    }
                    onFinished: hueco.entrado = true
                }
                SequentialAnimation {
                    id: salir
                    ParallelAnimation {
                        NumberAnimation { target: desliz; property: "x"; to: pila.width + 30; duration: 260; easing.type: Easing.InCubic }
                        NumberAnimation { target: tarjeta; property: "opacity"; to: 0; duration: 260 }
                    }
                    NumberAnimation { target: hueco; property: "alto"; to: 0; duration: 200; easing.type: Easing.InOutCubic }
                    ScriptAction { script: w.av.borrarEmergente(hueco.fila.clave) }
                }

                // Tiempo restante (se pausa con el mouse encima)
                property real restante: 1
                NumberAnimation on restante {
                    id: cuenta
                    running: hueco.fila.duracion > 0 && !hueco.saliendo
                    paused: running && tarjeta.encima
                    from: 1
                    to: 0
                    duration: Math.max(1000, hueco.fila.duracion)
                    onFinished: w.av.quitarEmergente(hueco.fila.clave)
                }
                // Si la app la actualiza, el tiempo vuelve a empezar
                Connections {
                    target: hueco.fila
                    function onResumenChanged() { cuenta.restart() }
                    function onCuerpoChanged() { cuenta.restart() }
                }

                Item {
                    id: desliz
                    x: pila.width + 30
                    width: parent.width
                    height: tarjeta.implicitHeight

                    // Sombra
                    Rectangle {
                        anchors.fill: tarjeta
                        radius: tarjeta.radius
                        color: w.tema.surface
                        opacity: tarjeta.opacity
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: "black"
                            shadowOpacity: 0.4
                            shadowBlur: 0.7
                            shadowVerticalOffset: 4
                        }
                    }

                    TarjetaAviso {
                        id: tarjeta
                        width: parent.width
                        s: w.s
                        tema: w.tema
                        av: w.av
                        d: hueco.fila
                        ahora: w.ahora
                        enPopup: true
                        onCerrar: w.av.descartar(hueco.fila.clave)
                        onAccion: id => w.av.invocar(hueco.fila.clave, id)
                        onClicCuerpo: w.av.clicCuerpo(hueco.fila.clave)

                        // Barra fina de tiempo restante
                        Rectangle {
                            visible: hueco.fila.duracion > 0
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 5
                            x: 18
                            width: (parent.width - 36) * hueco.restante
                            height: 2
                            radius: 1
                            color: w.s.alfa(w.tema.primary, 0.6)
                        }
                    }
                }
            }
        }
    }
}
