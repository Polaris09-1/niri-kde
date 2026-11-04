import QtQuick

// Tarjeta de una sección propia, con ancla para que el buscador pueda saltar a ella y resaltarla.
Rectangle {
    id: a

    property var raiz
    property string opId: ""
    default property alias dentro: cuerpo.data

    width: parent ? parent.width : 400
    height: cuerpo.implicitHeight + 20
    radius: 14
    readonly property bool resaltada: a.opId !== "" && a.raiz.resaltada === a.opId
    color: a.raiz.alfa(a.raiz.tema.primary, a.resaltada ? 0.28 : 0.07)
    border.color: a.resaltada ? a.raiz.tema.primary : "transparent"
    border.width: 1.5
    Behavior on color { ColorAnimation { duration: 200 } }
    Component.onCompleted: if (a.opId !== "") a.raiz.registrarFila(a.opId, a)
    Component.onDestruction: if (a.opId !== "") a.raiz.quitarFila(a.opId, a)

    Column {
        id: cuerpo
        x: 14
        y: 10
        width: parent.width - 28
        spacing: 8
    }
}
