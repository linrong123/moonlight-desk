import QtQuick 2.9
import QtQuick.Controls 2.2
import "deskstyle.js" as Style

// Flat button for the Desk UI. kind: "primary" | "secondary" | "ghost" | "danger"
Button {
    id: control
    property string kind: "secondary"
    readonly property bool primary: kind === "primary"

    implicitHeight: Style.controlHeight
    implicitWidth: Math.max(72, contentItem.implicitWidth + leftPadding + rightPadding)
    leftPadding: 16
    rightPadding: 16
    topPadding: 0
    bottomPadding: 0
    font.pixelSize: Style.fontBody
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Keys.onReturnPressed: if (enabled) clicked()
    Keys.onEnterPressed: if (enabled) clicked()

    contentItem: Text {
        text: control.text
        font: control.font
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: !control.enabled ? Style.textFaint
             : control.primary ? "#ffffff"
             : control.kind === "danger" ? Style.danger
             : control.kind === "ghost" ? Style.textMuted
             : Style.text
    }

    background: Rectangle {
        radius: Style.radiusSmall
        color: {
            if (control.primary)
                return !control.enabled ? Style.borderStrong
                     : control.down ? Style.accentPressed : Style.accent
            if (control.kind === "danger")
                return control.down ? "#f9dcdc" : control.hovered ? Style.dangerSoft : Style.surface
            if (control.kind === "ghost")
                return control.down ? Style.border : control.hovered ? Style.surfaceAlt : "transparent"
            return control.down ? Style.border : control.hovered ? Style.surfaceAlt : Style.surface
        }
        border.width: control.primary || control.kind === "ghost" ? 0 : 1
        border.color: control.kind === "danger" ? "#f0c4c4" : Style.border
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: parent.radius + 3
            color: "transparent"
            border.width: 2
            border.color: Style.accentSoft
            visible: control.visualFocus
        }
    }
}
