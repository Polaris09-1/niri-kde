pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// La pantalla donde va cada ventana del shell. Toda PanelWindow suelta debe llevar `screen: Principal.pantalla`:
// niri cierra las capas de una salida que se apaga, y solo una ventana enlazada a una pantalla se recrea sola
// (se muda a otra al apagarse y vuelve al encenderse). Sin esto, los módulos desaparecen hasta reiniciarlos.
// Además `visible: Principal.lista && …`: el enlace solo no basta. Al cambiar las pantallas, `lista` baja un instante
// y la capa se recrea sin perder el contenido de la ventana. Probado apagando y encendiendo una salida 5 veces seguidas.
// Orden: el monitor principal de Ajustes, la pantalla del portátil, la primera encendida.
// Enlace simbólico en cada módulo, como Colors.qml.
Singleton {
    id: p

    property string elegida: ""       // "Marca Modelo Serie" o conector (niri.principal en ajustes.json)
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/ajustes/ajustes.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { p.elegida = JSON.parse(text())["niri.principal"] || "" } catch (e) { p.elegida = "" }
        }
    }

    property bool lista: true
    Connections {
        target: Quickshell
        function onScreensChanged() { p.lista = false; volver.restart() }
    }
    Timer { id: volver; interval: 120; onTriggered: p.lista = true }

    function coincide(s) {
        if (p.elegida === "") return false
        if (p.elegida === s.name) return true
        return !!s.model && s.model !== "Unknown" && p.elegida.indexOf(s.model) >= 0
    }
    readonly property var pantalla: {
        var l = Quickshell.screens
        return l.find(s => p.coincide(s)) || l.find(s => /^eDP/.test(s.name)) || l[0] || null
    }
}
