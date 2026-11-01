import QtQuick

// Título pequeño de sección
Text {
    property var s
    property var tema
    property string texto: ""
    text: texto
    topPadding: 4
    leftPadding: 4
    font.family: s.fuente
    font.pixelSize: 11
    font.bold: true
    font.letterSpacing: 0.5
    color: s.alfa(tema.primary, 0.85)
}
