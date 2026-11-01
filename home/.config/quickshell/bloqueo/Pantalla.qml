import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects

// Pantalla de bloqueo, diseño "tarjeta lateral" (elegido el 2026-11-01): fondo casi nítido y una
// tarjeta translúcida (centrada) con hora, fecha, música, avisos sin ver, usuario, contraseña y
// botones de energía (centrada desde el 2026-11-01). La usan el bloqueo real (WlSessionLockSurface) y la vista previa.
Item {
    id: p

    property var s                       // shell.qml (estado y funciones)
    property var tema
    property bool vistaPrevia: false

    readonly property string fuente: s.fuente
    function alfa(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function ic(cp) { return String.fromCodePoint(cp) }

    // ----- Energía (reiniciar/apagar con confirmación y cuenta atrás de 5 s) -----
    property string pendiente: ""         // "" | "reiniciar" | "apagar"
    property int cuenta: 5
    function pedirEnergia(id) {
        if (id === "suspender") { if (!p.vistaPrevia) p.s.energia("suspender"); return }
        p.pendiente = id
        p.cuenta = 5
        cuentaAtras.restart()
    }
    Timer {
        id: cuentaAtras
        interval: 1000
        repeat: true
        onTriggered: {
            p.cuenta--
            if (p.cuenta <= 0) { stop(); var id = p.pendiente; p.pendiente = ""; if (!p.vistaPrevia) p.s.energia(id) }
        }
    }

    // ----- Contraseña -----
    function enviar() {
        if (p.vistaPrevia) { campo.text = ""; p.s.avisoVista(); return }
        var t = campo.text
        campo.text = ""                   // el campo se vacía en cada intento
        p.s.intentar(t)
    }
    Connections {
        target: p.s
        function onFallo() { sacudir.restart() }
    }

    // ===== Fondo casi nítido =====
    // La imagen no se dibuja sola: la dibuja el efecto de abajo, del mismo tamaño que la pantalla
    // (sin relleno automático, que la desplazaba y ampliaba). Sin zoom: solo recorte para llenar.
    Image {
        id: imagenFondo
        anchors.fill: parent
        source: p.s.rutaFondo ? "file://" + p.s.rutaFondo : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
        visible: false
    }
    MultiEffect {
        id: fondo
        anchors.fill: parent
        source: imagenFondo
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 0.25
        blurMax: 32
    }
    Rectangle {
        anchors.fill: parent
        color: p.alfa(p.tema.surface, 0.22)
    }

    // ===== Batería y wifi (arriba a la derecha, sobre una pastilla para que se lean en fondos claros) =====
    Rectangle {
        anchors.fill: estadoArriba
        anchors.margins: -8
        anchors.leftMargin: -12
        anchors.rightMargin: -12
        radius: height / 2
        visible: estadoArriba.visibleChildren.length > 0
        color: p.alfa(p.tema.surface, 0.6)
        border.color: p.alfa(p.tema.primary, 0.25)
        border.width: 1
    }
    Row {
        id: estadoArriba
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 22
        anchors.rightMargin: 30
        spacing: 14
        Text {
            visible: p.s.wifiSenal >= 0
            text: p.ic(p.s.wifiSenal > 66 ? 0xF0928 : p.s.wifiSenal > 33 ? 0xF0925 : 0xF0922)
            font.family: p.fuente
            font.pixelSize: 15
            color: p.alfa(p.tema.surfaceText, 0.85)
        }
        Row {
            visible: p.s.hayBateria
            spacing: 5
            Text {
                text: p.ic(p.s.cargando ? 0xF0084 : p.s.bateria > 80 ? 0xF0079 : p.s.bateria > 50 ? 0xF0080
                           : p.s.bateria > 20 ? 0xF007C : 0xF0083)
                font.family: p.fuente
                font.pixelSize: 15
                color: !p.s.cargando && p.s.bateria <= 20 ? p.s.colorError : p.alfa(p.tema.surfaceText, 0.85)
            }
            Text {
                text: p.s.bateria + "%"
                font.family: p.fuente
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
                color: p.alfa(p.tema.surfaceText, 0.85)
            }
        }
    }

    // ===== Tarjeta =====
    // Fondo de la tarjeta: el mismo fondo muy difuminado, recortado con esquinas redondeadas
    Item {
        id: fondoTarjeta
        anchors.fill: tarjeta
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mascaraTarjeta
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        MultiEffect {
            anchors.fill: parent
            source: ShaderEffectSource {
                sourceItem: fondo
                sourceRect: Qt.rect(tarjeta.x, tarjeta.y, tarjeta.width, tarjeta.height)
            }
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1.0
            blurMax: 64
        }
        Rectangle {
            anchors.fill: parent
            color: p.alfa(p.tema.surface, 0.62)
        }
    }
    Rectangle {
        id: mascaraTarjeta
        anchors.fill: tarjeta
        radius: 28
        visible: false
        layer.enabled: true
    }
    Rectangle {
        anchors.fill: tarjeta
        radius: 28
        color: "transparent"
        border.color: p.alfa(p.tema.primary, 0.35)
        border.width: 1
    }

    Item {
        id: tarjeta
        width: 380
        height: columna.implicitHeight + 56
        // Centrada en la pantalla (2026-11-01, pedido del usuario; antes a la derecha)
        anchors.centerIn: parent

        Column {
            id: columna
            x: 28
            y: 28
            width: parent.width - 56
            spacing: 18

            // Hora y fecha
            Column {
                width: parent.width
                spacing: 2
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatTime(p.s.ahora, "HH:mm")
                    font.family: p.fuente
                    font.pixelSize: 72
                    font.weight: Font.Light
                    color: p.tema.surfaceText
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        var t = Qt.locale("es_ES").toString(p.s.ahora, "dddd, d 'de' MMMM")
                        return t.charAt(0).toUpperCase() + t.slice(1)
                    }
                    font.family: p.fuente
                    font.pixelSize: 14
                    color: p.alfa(p.tema.surfaceText, 0.7)
                }
            }

            // Música (solo si hay un reproductor)
            Rectangle {
                visible: !!p.s.jugador
                width: parent.width
                height: 76
                radius: 18
                color: p.alfa(p.tema.surface, 0.45)
                border.color: p.alfa(p.tema.primary, 0.18)
                border.width: 1

                Item {
                    id: caratula
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 56
                    height: 56
                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: p.alfa(p.tema.primary, 0.15)
                        Text {
                            anchors.centerIn: parent
                            text: p.ic(0xF075A)
                            font.family: p.fuente
                            font.pixelSize: 22
                            color: p.tema.primary
                        }
                    }
                    Image {
                        id: imgCaratula
                        anchors.fill: parent
                        source: p.s.jugador ? (p.s.jugador.trackArtUrl || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: false
                        asynchronous: true
                    }
                    MultiEffect {
                        anchors.fill: parent
                        visible: imgCaratula.status === Image.Ready
                        source: imgCaratula
                        maskEnabled: true
                        maskSource: mascaraCaratula
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                    Rectangle {
                        id: mascaraCaratula
                        anchors.fill: parent
                        radius: 12
                        visible: false
                        layer.enabled: true
                    }
                }
                Column {
                    anchors.left: caratula.right
                    anchors.leftMargin: 12
                    anchors.right: controles.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: p.s.jugador ? (p.s.jugador.trackTitle || "Sin título") : ""
                        font.family: p.fuente
                        font.pixelSize: 13
                        color: p.tema.surfaceText
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: p.s.jugador ? (p.s.jugador.trackArtist || p.s.jugador.identity || "") : ""
                        font.family: p.fuente
                        font.pixelSize: 11
                        color: p.alfa(p.tema.surfaceText, 0.65)
                    }
                }
                Row {
                    id: controles
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: [
                            { id: "anterior", icono: 0xF04AE },
                            { id: "pausa", icono: 0 },
                            { id: "siguiente", icono: 0xF04AD }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 30
                            height: 30
                            radius: 15
                            color: zonaMusica.containsMouse ? p.alfa(p.tema.primary, 0.18) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: p.ic(modelData.icono !== 0 ? modelData.icono
                                           : (p.s.jugador && p.s.jugador.isPlaying ? 0xF03E4 : 0xF040A))
                                font.family: p.fuente
                                font.pixelSize: 16
                                color: p.tema.primary
                            }
                            MouseArea {
                                id: zonaMusica
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (!p.vistaPrevia) p.s.musica(modelData.id)
                            }
                        }
                    }
                }
            }

            // Avisos que llegaron mientras estaba bloqueado (solo el número)
            Row {
                visible: p.s.avisosNuevos > 0
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Text {
                    text: p.ic(0xF009A)
                    font.family: p.fuente
                    font.pixelSize: 14
                    color: p.tema.primary
                }
                Text {
                    text: p.s.avisosNuevos === 1 ? "1 aviso nuevo" : p.s.avisosNuevos + " avisos nuevos"
                    font.family: p.fuente
                    font.pixelSize: 12
                    color: p.alfa(p.tema.surfaceText, 0.8)
                }
            }

            // Usuario
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: p.tema.primary
                    Text {
                        anchors.centerIn: parent
                        text: p.s.usuario.charAt(0).toUpperCase()
                        font.family: p.fuente
                        font.pixelSize: 18
                        font.bold: true
                        color: p.tema.primaryText
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: p.s.usuario
                    font.family: p.fuente
                    font.pixelSize: 15
                    color: p.tema.surfaceText
                }
            }

            // Contraseña
            Item {
                width: parent.width
                height: 48
                Rectangle {
                    id: pildora
                    width: parent.width
                    height: parent.height
                    radius: height / 2
                    color: p.alfa(p.tema.surface, 0.55)
                    border.width: 1.5
                    border.color: p.s.error !== "" ? p.s.colorError
                                : campo.activeFocus ? p.alfa(p.tema.primary, 0.7) : p.alfa(p.tema.primary, 0.3)
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    SequentialAnimation on x {
                        id: sacudir
                        running: false
                        NumberAnimation { to: -10; duration: 50; easing.type: Easing.OutCubic }
                        NumberAnimation { to: 8; duration: 70 }
                        NumberAnimation { to: -5; duration: 60 }
                        NumberAnimation { to: 0; duration: 60; easing.type: Easing.OutCubic }
                    }

                    // Entrada real (invisible): la contraseña solo vive aquí hasta pulsar Enter
                    TextInput {
                        id: campo
                        anchors.fill: parent
                        opacity: 0
                        echoMode: TextInput.Password
                        focus: true
                        enabled: !p.s.verificando
                        onAccepted: p.enviar()
                        Keys.onEscapePressed: text = ""
                        Component.onCompleted: forceActiveFocus()
                    }

                    // Puntos (uno por carácter, máx. 18 a la vista)
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7
                        visible: campo.text.length > 0
                        Repeater {
                            model: Math.min(campo.text.length, 18)
                            delegate: Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: p.tema.primary
                            }
                        }
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        visible: campo.text.length === 0
                        text: p.s.verificando ? "Comprobando…" : "Contraseña"
                        font.family: p.fuente
                        font.pixelSize: 13
                        color: p.alfa(p.tema.surfaceText, 0.5)
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        radius: 18
                        color: campo.text.length > 0 ? p.tema.primary : p.alfa(p.tema.primary, 0.15)
                        Text {
                            anchors.centerIn: parent
                            text: p.ic(p.s.verificando ? 0xF0772 : 0xF0054)
                            font.family: p.fuente
                            font.pixelSize: 16
                            color: campo.text.length > 0 ? p.tema.primaryText : p.tema.primary
                            RotationAnimation on rotation {
                                running: p.s.verificando
                                from: 0; to: 360; duration: 900; loops: Animation.Infinite
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { p.enviar(); campo.forceActiveFocus() }
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: 48
                    onClicked: campo.forceActiveFocus()
                }
            }

            // Mensajes: error de contraseña y Bloq Mayús
            Column {
                width: parent.width
                spacing: 4
                visible: p.s.error !== "" || p.s.mayus || p.vistaPrevia && p.s.mensajeVista !== ""
                Text {
                    visible: p.s.error !== ""
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: p.s.error
                    font.family: p.fuente
                    font.pixelSize: 12
                    color: p.s.colorError
                }
                Text {
                    visible: p.s.mayus
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: p.ic(0xF0632) + "  Bloq Mayús activado"
                    font.family: p.fuente
                    font.pixelSize: 12
                    color: p.alfa(p.tema.surfaceText, 0.75)
                }
                Text {
                    visible: p.vistaPrevia && p.s.mensajeVista !== ""
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: p.s.mensajeVista
                    font.family: p.fuente
                    font.pixelSize: 12
                    color: p.alfa(p.tema.surfaceText, 0.75)
                }
            }

            // Energía: botones o confirmación con cuenta atrás
            Item {
                width: parent.width
                height: 40
                Row {
                    visible: p.pendiente === ""
                    anchors.centerIn: parent
                    spacing: 18
                    Repeater {
                        model: [
                            { id: "suspender", icono: 0xF0904, texto: "Suspender" },
                            { id: "reiniciar", icono: 0xF0709, texto: "Reiniciar" },
                            { id: "apagar", icono: 0xF0425, texto: "Apagar" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 40
                            height: 40
                            radius: 20
                            color: zonaEnergia.containsMouse ? p.alfa(p.tema.primary, 0.2) : p.alfa(p.tema.surface, 0.45)
                            border.color: p.alfa(p.tema.primary, 0.25)
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: p.ic(modelData.icono)
                                font.family: p.fuente
                                font.pixelSize: 17
                                color: p.alfa(p.tema.surfaceText, 0.85)
                            }
                            MouseArea {
                                id: zonaEnergia
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: p.pedirEnergia(modelData.id)
                            }
                        }
                    }
                }
                Row {
                    visible: p.pendiente !== ""
                    anchors.centerIn: parent
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (p.pendiente === "apagar" ? "Se apagará en " : "Se reiniciará en ") + p.cuenta + " s"
                        font.family: p.fuente
                        font.pixelSize: 12
                        color: p.tema.surfaceText
                    }
                    Repeater {
                        model: [ { id: "cancelar", texto: "Cancelar" }, { id: "ahora", texto: "Ahora" } ]
                        delegate: Rectangle {
                            required property var modelData
                            width: textoBoton.implicitWidth + 24
                            height: 30
                            radius: 15
                            color: modelData.id === "ahora" ? p.alfa(p.s.colorError, 0.85)
                                 : zonaConfirmar.containsMouse ? p.alfa(p.tema.primary, 0.2) : p.alfa(p.tema.surface, 0.5)
                            Text {
                                id: textoBoton
                                anchors.centerIn: parent
                                text: modelData.texto
                                font.family: p.fuente
                                font.pixelSize: 12
                                color: modelData.id === "ahora" ? "#3b0a0a" : p.tema.surfaceText
                            }
                            MouseArea {
                                id: zonaConfirmar
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    cuentaAtras.stop()
                                    var id = p.pendiente
                                    p.pendiente = ""
                                    if (modelData.id === "ahora" && !p.vistaPrevia) p.s.energia(id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
