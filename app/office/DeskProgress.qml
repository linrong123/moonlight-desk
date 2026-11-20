import QtQuick 2.9
import QtQuick.Controls 2.5
import "deskstyle.js" as Style
import "desklogic.js" as Logic

// Light full-page progress screen for the connect / recover / quit
// transitions. Upstream segues keep their own spinner and label (hidden) and
// feed the stage text through `stage`; English stage texts fall back to a
// Chinese title. Buttons placed above it by the segue stay clickable.
Rectangle {
    id: progress
    property string stage: ""
    property string fallback: "正在连接远程桌面…"
    property string detail: ""
    property bool busy: true
    readonly property string title: Logic.progressTitle(stage, fallback)

    color: Style.background

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.verticalCenter
        anchors.bottomMargin: 16
        width: Math.min(480, parent.width - 48)
        spacing: Style.spacing

        BusyIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 48
            height: 48
            running: progress.busy && progress.visible
            visible: progress.busy
        }
        Text {
            objectName: "deskProgressTitle"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: progress.title
            font.pixelSize: Style.fontTitle + 2
            font.bold: true
            color: Style.text
            wrapMode: Text.Wrap
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: text !== ""
            text: progress.detail
            font.pixelSize: Style.fontBody
            color: Style.textMuted
            wrapMode: Text.Wrap
        }
    }
}
