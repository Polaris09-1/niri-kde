import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: config.surface

    Image {
        anchors.fill: parent
        source: "background.jpg"
        fillMode: Image.PreserveAspectCrop
    }

    Text {
        id: clock
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 60
        font.pixelSize: 64
        color: config.onSurface
     style: Text.Outline
        styleColor: config.surface
        text: Qt.formatTime(new Date(), "hh:mm")
        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clock.text = Qt.formatTime(new Date(), "hh:mm")
        }
     }

     Rectangle {
         width: 380
         height: 300
         radius: 16
         anchors.centerIn: parent
         color: config.card
         border.color: config.primary
         border.width: 2

         Column {
             anchors.centerIn: parent
             spacing: 14
             width: 320

             TextField {
                 id: userField
                 width: parent.width
                 text: userModel.lastUser
                 placeholderText: "Usuario"
             }
             TextField {
                 id: passField
                 width: parent.width
                 echoMode: TextInput.Password
                 placeholderText: "Contraseña"
                 focus: true
                 onAccepted: sddm.login(userField.text, passField.text, sessionBox.currentIndex)
             }
             ComboBox {
                 id: sessionBox
                 width: parent.width
                 model: sessionModel
                 textRole: "name"
                 currentIndex: sessionModel.lastIndex
             }
             Button {
                 width: parent.width
                 text: "Entrar"
                 onClicked: sddm.login(userField.text, passField.text, sessionBox.currentIndex)
             }
             Text {
                id: msg
                color: config.primary
                text: ""
             }
         }
     }

     Connections {
         target: sddm
         function onLoginFailed() {
             msg.text = "Contraseña incorrecta"
             passField.text = ""
             passField.forceActiveFocus()
         }
     }
}
