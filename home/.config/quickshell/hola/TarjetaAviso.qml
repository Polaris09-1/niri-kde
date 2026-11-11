import QtQuick
import QtQuick.Effects

// Tarjeta de una notificación: icono + app + hora, título, texto, imagen y botones de acción.
// La usan los popups (enPopup) y el historial del panel del reloj.
Rectangle {
    id: t

    property var s                 // root de hola (fuente, alfa, ic)
    property var tema
    property var av                // servicio Avisos
    property var d                 // fila del modelo
    property date ahora: new Date()
    property bool enPopup: false
    property bool encima: ma.containsMouse || cerrarBtn.containsMouse
    readonly property var acciones: {
        try { return JSON.parse(t.d.acciones || "[]").filter(a => a.id !== "default" && a.texto !== "") }
        catch (e) { return [] }
    }
    // Botones propios de la barra (Editar, Carpeta): sirven también tras recargar
    readonly property var propios: {
        try { return JSON.parse(t.d.botones || "[]") } catch (e) { return [] }
    }
    readonly property var botones: (t.d.vivo ? t.acciones : []).concat(t.propios)
    readonly property bool urgente: t.d.urgencia === 2

    signal cerrar()
    signal accion(string id)
    signal clicCuerpo()

    implicitHeight: col.implicitHeight + 24
    radius: 18
    color: t.enPopup ? Qt.rgba(t.tema.surface.r, t.tema.surface.g, t.tema.surface.b, 0.96)
        : t.s.alfa(t.tema.primary, ma.containsMouse ? 0.14 : 0.08)
    border.color: t.urgente ? "#e05555" : t.s.alfa(t.tema.primary, t.enPopup ? 0.55 : 0.18)
    border.width: t.urgente ? 2 : 1.5
    Behavior on color {
        ColorAnimation { duration: 150 }
    }

    // Clic en la tarjeta (debajo de los botones)
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: m => { if (m.button === Qt.MiddleButton) t.cerrar(); else t.clicCuerpo() }
    }

    Column {
        id: col
        x: 14
        y: 12
        width: parent.width - 28
        spacing: 6

        // Cabecera: icono · app · hora · ✕
        Item {
            width: parent.width
            height: 20

            Image {
                id: icono
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                sourceSize.width: 36
                sourceSize.height: 36
                source: t.d.icono || ""
                visible: status === Image.Ready
                smooth: true
            }
            Text {
                id: icFalso
                anchors.verticalCenter: parent.verticalCenter
                visible: !icono.visible
                text: t.s.ic(t.urgente ? 0xF0028 : 0xF009A)
                font.family: t.s.fuente
                font.pixelSize: 15
                color: t.urgente ? "#ff6b6b" : t.tema.primary
            }
            Text {
                anchors.left: icono.visible ? icono.right : icFalso.right
                anchors.leftMargin: 8
                anchors.right: cerrarBtn.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: t.d.app + "  ·  " + t.av.hace(t.d.hora, t.ahora)
                font.family: t.s.fuente
                font.pixelSize: 11
                font.bold: true
                color: t.s.alfa(t.tema.primary, 0.9)
            }

            // ✕ descartar
            Rectangle {
                id: cerrarBtn
                property bool containsMouse: maCerrar.containsMouse
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                radius: 11
                color: t.s.alfa(t.tema.primary, maCerrar.containsMouse ? 0.25 : 0)
                opacity: t.encima || !t.enPopup ? 1 : 0.45
                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
                Text {
                    anchors.centerIn: parent
                    text: t.s.ic(0xF0156)
                    font.family: t.s.fuente
                    font.pixelSize: 13
                    color: t.tema.surfaceText
                }
                MouseArea {
                    id: maCerrar
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: t.cerrar()
                }
            }
        }

        // Título + texto, con la imagen a la derecha
        Item {
            width: parent.width
            height: Math.max(textos.implicitHeight, foto.visible ? 52 : 0)

            Column {
                id: textos
                anchors.left: parent.left
                anchors.right: foto.visible ? foto.left : parent.right
                anchors.rightMargin: foto.visible ? 10 : 0
                spacing: 3

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: t.d.resumen
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: t.s.fuente
                    font.pixelSize: 13
                    font.bold: true
                    color: t.tema.surfaceText
                }
                Text {
                    width: parent.width
                    visible: t.d.cuerpo !== ""
                    text: t.d.cuerpo.replace(/\n/g, "<br>")
                    wrapMode: Text.Wrap
                    maximumLineCount: t.enPopup ? 4 : 3
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    linkColor: t.tema.primary
                    onLinkActivated: url => Qt.openUrlExternally(url)
                    font.family: t.s.fuente
                    font.pixelSize: 12
                    color: t.s.alfa(t.tema.surfaceText, 0.75)
                }
            }

            // Imagen con esquinas redondeadas
            Item {
                id: foto
                anchors.right: parent.right
                anchors.top: parent.top
                width: 52
                height: 52
                visible: t.d.imagen !== "" && img.status === Image.Ready
                Image {
                    id: img
                    anchors.fill: parent
                    source: t.d.imagen || ""
                    sourceSize.width: 104
                    sourceSize.height: 104
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                Rectangle {
                    id: mascara
                    anchors.fill: parent
                    radius: 12
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: img
                    maskEnabled: true
                    maskSource: mascara
                }
            }
        }

        // Por qué no se pudo abrir (archivo borrado, programa sin instalar)
        Text {
            width: parent.width
            visible: (t.d.nota || "") !== ""
            text: "✕  " + (t.d.nota || "")
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: t.s.fuente
            font.pixelSize: 11
            color: "#ff8a80"
        }

        // Botones de acción: los de la app (si sigue viva) y los propios
        Flow {
            width: parent.width
            spacing: 6
            topPadding: 2
            visible: t.botones.length > 0
            Repeater {
                model: t.botones
                delegate: BotonTexto {
                    required property var modelData
                    required property int index
                    tema: t.tema
                    texto: modelData.texto
                    anchoMax: col.width
                    lleno: index === 0
                    height: 28
                    onClic: t.accion(modelData.id)
                }
            }
        }
    }
}
