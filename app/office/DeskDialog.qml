import QtQuick 2.9
import QtQuick.Controls 2.5
import QtQuick.Controls.Material 2.2
import "deskstyle.js" as Style

// Rounded light dialog used by every Desk prompt. Extra child items are
// placed below the message, inside the content column.
Dialog {
    id: dialog
    property string message: ""
    property string acceptText: "确定"
    property string rejectText: ""
    property string acceptKind: "primary"
    property bool acceptEnabled: true
    property alias acceptButton: acceptButton
    property alias rejectButton: rejectButton

    parent: Overlay.overlay
    Material.theme: Material.Light
    Material.accent: Style.accent
    anchors.centerIn: parent
    width: Math.min(420, parent ? parent.width - 48 : 420)
    modal: true
    focus: true
    closePolicy: rejectText !== "" ? Popup.CloseOnEscape : Popup.NoAutoClose
    padding: 24
    topPadding: 8
    bottomPadding: 20

    background: Rectangle {
        radius: Style.radiusLarge
        color: Style.surface
        border.color: Style.border
    }

    header: Text {
        text: dialog.title
        visible: text !== ""
        leftPadding: 24
        rightPadding: 24
        topPadding: 22
        bottomPadding: 6
        font.pixelSize: Style.fontTitle
        font.bold: true
        color: Style.text
        elide: Text.ElideRight
    }

    contentItem: Column {
        spacing: Style.spacing
        Text {
            objectName: "deskDialogMessage"
            width: parent.width
            visible: dialog.message !== ""
            text: dialog.message
            wrapMode: Text.Wrap
            font.pixelSize: Style.fontBody
            lineHeight: 1.25
            color: Style.textMuted
        }
    }

    footer: Item {
        implicitHeight: buttons.implicitHeight + 20
        Row {
            id: buttons
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.top: parent.top
            spacing: Style.spacingSmall
            DeskButton {
                id: rejectButton
                objectName: "deskDialogReject"
                visible: dialog.rejectText !== ""
                text: dialog.rejectText
                kind: "secondary"
                onClicked: dialog.reject()
            }
            DeskButton {
                id: acceptButton
                objectName: "deskDialogAccept"
                visible: dialog.acceptText !== ""
                text: dialog.acceptText
                kind: dialog.acceptKind
                enabled: dialog.acceptEnabled
                onClicked: dialog.accept()
            }
        }
    }

    onOpened: if (acceptButton.visible) acceptButton.forceActiveFocus()
}
