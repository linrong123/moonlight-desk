import QtQuick 2.0
import QtQuick.Controls 2.2
import "deskstyle.js" as Style

// Shown while the host user decides whether to allow this connection
// (CONNECTION.md §2). Cancel is forwarded once; Session withdraws the request.
Column {
    id: approval
    property bool waiting: false
    property bool cancelling: false
    signal cancelRequested()

    visible: waiting
    spacing: 12
    onWaitingChanged: if (!waiting) cancelling = false

    function cancel() {
        if (!waiting || cancelling)
            return
        cancelling = true
        cancelRequested()
    }

    Text {
        objectName: "approvalHint"
        anchors.horizontalCenter: parent.horizontalCenter
        text: approval.cancelling ? qsTr("正在取消…") : qsTr("被控端用户允许后将自动连接，最长等待 60 秒")
        font.pixelSize: Style.fontBody
        color: Style.textMuted
    }

    DeskButton {
        objectName: "approvalCancel"
        anchors.horizontalCenter: parent.horizontalCenter
        text: qsTr("取消")
        enabled: !approval.cancelling
        onClicked: approval.cancel()
    }
}
