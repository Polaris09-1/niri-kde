import QtQuick

// Fila: [icono o imagen (clic = mudo)] [nombre opcional encima] [slider] [porcentaje]
// El volumen cambia en vivo mientras arrastras.
Item {
    id: f

    property var s
    property var tema
    property var nodo
    property string icono: ""
    property string imagen: ""
    property string titulo: ""
    signal cambiar(real v)
    signal alternarMudo()

    property bool mudo: f.nodo && f.nodo.audio ? f.nodo.audio.muted : false
    property real volumen: f.nodo && f.nodo.audio ? f.nodo.audio.volume : 0

    height: f.titulo !== "" ? 50 : 34

    Boton {
        id: btn
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        tema: f.tema
        icono: f.imagen === "" ? f.icono : ""
        imagen: f.imagen
        opacity: f.mudo ? 0.5 : 1
        onClic: f.alternarMudo()
    }

    Text {
        visible: f.titulo !== ""
        anchors.left: desl.left
        anchors.top: parent.top
        width: desl.width
        elide: Text.ElideRight
        text: f.titulo
        font.family: f.s.fuente
        font.pixelSize: 11
        color: f.s.alfa(f.tema.surfaceText, 0.75)
    }

    Deslizador {
        id: desl
        anchors.left: btn.right
        anchors.leftMargin: 8
        anchors.right: pct.left
        anchors.rightMargin: 8
        anchors.verticalCenter: btn.verticalCenter
        tema: f.tema
        valor: f.mudo ? 0 : f.volumen
        onMovido: v => f.cambiar(v)
        onSoltado: v => f.cambiar(v)
    }

    Text {
        id: pct
        anchors.right: parent.right
        anchors.verticalCenter: btn.verticalCenter
        width: 40
        horizontalAlignment: Text.AlignRight
        text: desl.arrastrando ? Math.round(desl.vista * 100) + "%" : (f.mudo ? "mudo" : Math.round(f.volumen * 100) + "%")
        font.family: f.s.fuente
        font.pixelSize: 12
        color: f.tema.surfaceText
    }
}
