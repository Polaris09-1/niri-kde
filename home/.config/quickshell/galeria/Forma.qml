import QtQuick

// Elemento de dibujo de la galería: tarjeta.frag con sus parámetros.
// La fuente debe tener mipmap: true para que el desenfoque sea suave.
ShaderEffect {
    property var fuente
    readonly property size tam: Qt.size(width, height)
    property size caja: Qt.size(width, height)
    property real sesgo: 0
    property real radio: 0
    property real desenfoque: 0
    property real relacion: 16 / 9
    property real grosorBorde: 0
    property real alfaBorde: 0
    property real alfaSombra: 0
    property real alcanceSombra: 1
    property color colorBorde: "white"
    property color colorSombra: "black"
    fragmentShader: "tarjeta.frag.qsb"
}
