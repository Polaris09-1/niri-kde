import QtQuick

// Base translúcida de los widgets. El desenfoque real lo pone niri por detrás (ver regionBlur en
// Elemento.qml), así que aquí solo va el tinte y el borde.
Item {
    id: t
    required property var tema
    default property alias contenido: interior.data
    property int relleno: 14

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: Qt.rgba(t.tema.surface.r, t.tema.surface.g, t.tema.surface.b, 0.5)
        border.width: 1
        border.color: Qt.rgba(t.tema.primary.r, t.tema.primary.g, t.tema.primary.b, 0.28)
    }
    Item {
        id: interior
        anchors.fill: parent
        anchors.margins: t.relleno
    }
}
