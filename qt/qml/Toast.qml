// qml/Toast.qml
import QtQuick 2.12

Rectangle {
    id: toast
    property bool successMode: false
    property string message: ""

    width: toastText.implicitWidth + 32; height: 36; radius: 8
    color: successMode ? "#1f0d10" : "#1a0a0a"
    border.color: successMode ? "#ab3d4c" : "#ff4757"; border.width: 1
    opacity: 0; visible: opacity > 0

    Text {
        id: toastText
        anchors.centerIn: parent
        text: toast.message
        color: successMode ? "#c9505f" : "#ff6b7a"; font.pixelSize: 12
    }

    function show(msg) {
        if (msg !== undefined) message = msg
        anim.restart()
    }

    SequentialAnimation {
        id: anim
        NumberAnimation { target: toast; property: "opacity"; to: 1; duration: 180 }
        PauseAnimation  { duration: 2200 }
        NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 300 }
    }
}
