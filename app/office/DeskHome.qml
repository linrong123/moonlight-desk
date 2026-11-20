import QtQuick 2.9
import QtQuick.Controls 2.5
import QtQuick.Controls.Material 2.2
import "deskstyle.js" as Style
import "desklogic.js" as Logic

// Desk workbench view. Pure view: data comes in through properties and every
// action leaves through a signal, so tests can drive it with plain objects.
Rectangle {
    id: home
    objectName: "远程桌面"
    Material.accent: Style.accent
    color: Style.background

    // [{uuid, name, address, addresses, online, paired, wakeable, statusUnknown, serverSupported}]
    property var devices: []
    // uuid -> session status text, only for devices with an open session.
    property var sessionStates: ({})
    property bool connecting: false
    property string connectStatus: ""
    property alias addressText: addressInput.text

    signal connectRequested(string address)
    signal openDevice(string uuid)
    signal pairDevice(string uuid)
    signal wakeDevice(string uuid)
    signal renameDevice(string uuid)
    signal removeDevice(string uuid)
    signal disconnectDevice(string uuid)
    signal settings()
    signal quitRequested()

    readonly property int deviceCount: devices ? devices.length : 0

    function device(uuid) { return Logic.findDevice(devices, uuid) }
    function sessionActive(uuid) { return !!(sessionStates && sessionStates[uuid]) }
    function menuActions(uuid) { return Logic.menuActions(device(uuid), sessionActive(uuid)) }
    function primaryAction(uuid) { return Logic.primaryAction(device(uuid), sessionActive(uuid)) }

    function submitAddress() {
        if (connecting) return
        connectRequested(addressInput.text.trim())
    }

    // Runs one card/menu action after re-checking it is still allowed.
    function trigger(uuid, action) {
        var d = device(uuid)
        if (!d) return false
        var active = sessionActive(uuid)
        var allowed = action === "open" ? Logic.primaryAction(d, active).action === "open"
                    : Logic.hasAction(Logic.menuActions(d, active), action) ||
                      Logic.primaryAction(d, active).action === action
        if (!allowed) return false
        if (action === "open") openDevice(uuid)
        else if (action === "pair") pairDevice(uuid)
        else if (action === "wake") wakeDevice(uuid)
        else if (action === "rename") renameDevice(uuid)
        else if (action === "remove") removeDevice(uuid)
        else if (action === "disconnect") disconnectDevice(uuid)
        else return false
        return true
    }

    function showMenu(uuid, item) {
        deviceMenu.uuid = uuid
        deviceMenu.items = menuActions(uuid)
        deviceMenu.popup(item, 0, item.height)
    }

    // Top bar ------------------------------------------------------------------
    Item {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 64
        Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.pageMargin
            anchors.verticalCenter: parent.verticalCenter
            text: "Moonlight Desk"
            font.pixelSize: Style.fontTitle
            font.bold: true
            color: Style.text
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.pageMargin - 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            DeskButton {
                objectName: "settingsButton"
                kind: "ghost"
                text: "⚙  设置"
                onClicked: home.settings()
            }
            DeskButton {
                objectName: "quitButton"
                kind: "ghost"
                text: "退出"
                onClicked: home.quitRequested()
            }
        }
    }

    Flickable {
        id: page
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: content.height + Style.pageMargin
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        Column {
            id: content
            x: Style.pageMargin
            width: page.width - 2 * Style.pageMargin
            spacing: Style.spacingLarge

            // Connect card --------------------------------------------------------
            Rectangle {
                width: parent.width
                height: connectColumn.height + 48
                radius: Style.radiusLarge
                color: Style.surface
                border.color: Style.border

                Column {
                    id: connectColumn
                    x: 24
                    y: 24
                    width: parent.width - 48
                    spacing: Style.spacing

                    Text {
                        text: "连接远程桌面"
                        font.pixelSize: Style.fontHeadline
                        font.bold: true
                        color: Style.text
                    }
                    Text {
                        width: parent.width
                        text: "输入被控电脑的 IP 地址或域名。新设备会先配对，配对后直接进入桌面。"
                        font.pixelSize: Style.fontBody
                        color: Style.textMuted
                        wrapMode: Text.Wrap
                    }
                    Row {
                        width: parent.width
                        spacing: Style.spacing
                        TextField {
                            id: addressInput
                            objectName: "addressInput"
                            width: parent.width - connectButton.width - parent.spacing
                            height: Style.inputHeight
                            placeholderText: "输入被控端 IP 或域名"
                            placeholderTextColor: Style.textFaint
                            color: Style.text
                            font.pixelSize: 16
                            leftPadding: 14
                            rightPadding: 14
                            topPadding: 0
                            bottomPadding: 0
                            verticalAlignment: TextInput.AlignVCenter
                            selectByMouse: true
                            enabled: !home.connecting
                            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                            background: Rectangle {
                                radius: Style.radius
                                color: Style.surfaceAlt
                                border.width: addressInput.activeFocus ? 2 : 1
                                border.color: addressInput.activeFocus ? Style.accent : Style.border
                            }
                            Keys.onReturnPressed: home.submitAddress()
                            Keys.onEnterPressed: home.submitAddress()
                        }
                        DeskButton {
                            id: connectButton
                            objectName: "connectButton"
                            kind: "primary"
                            width: 112
                            height: Style.inputHeight
                            font.pixelSize: 16
                            text: home.connecting ? "连接中…" : "连接"
                            enabled: !home.connecting
                            onClicked: home.submitAddress()
                        }
                    }
                    Text {
                        objectName: "connectStatus"
                        width: parent.width
                        visible: text !== ""
                        text: home.connectStatus
                        font.pixelSize: Style.fontSmall + 1
                        color: Style.accent
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Devices ---------------------------------------------------------------
            Row {
                spacing: Style.spacingSmall
                Text {
                    text: "我的设备"
                    font.pixelSize: Style.fontTitle
                    font.bold: true
                    color: Style.text
                }
                Text {
                    anchors.baseline: parent.children[0].baseline
                    text: home.deviceCount > 0 ? home.deviceCount + " 台" : ""
                    font.pixelSize: Style.fontBody
                    color: Style.textFaint
                }
            }

            Rectangle {
                objectName: "emptyState"
                width: parent.width
                height: 168
                visible: home.deviceCount === 0
                radius: Style.radiusLarge
                color: "transparent"
                border.color: Style.borderStrong
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    spacing: Style.spacingSmall
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "还没有设备"
                        font.pixelSize: 16
                        font.bold: true
                        color: Style.text
                    }
                    Text {
                        objectName: "emptyHint"
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "在上方输入被控电脑的 IP 地址或域名，点击“连接”。\n被控电脑需要先安装并运行 Sunshine Desk。"
                        font.pixelSize: Style.fontBody
                        lineHeight: 1.3
                        color: Style.textMuted
                        wrapMode: Text.Wrap
                    }
                }
            }

            Flow {
                id: deviceList
                objectName: "deviceList"
                width: parent.width
                spacing: Style.spacing
                visible: home.deviceCount > 0
                readonly property int columns: Math.max(1, Math.floor((width + spacing) / (260 + spacing)))
                readonly property real cardWidth: (width - (columns - 1) * spacing) / columns

                Repeater {
                    id: cards
                    model: home.devices
                    delegate: Rectangle {
                        id: card
                        objectName: "deviceCard"
                        readonly property var device: modelData
                        readonly property string uuid: modelData.uuid
                        readonly property string session: home.sessionStates && home.sessionStates[uuid] ? home.sessionStates[uuid] : ""
                        readonly property var primary: Logic.primaryAction(device, session !== "")
                        width: deviceList.cardWidth
                        height: 156
                        radius: Style.radiusLarge
                        color: Style.surface
                        border.width: session !== "" ? 2 : 1
                        border.color: session !== "" ? Style.accent : cardMouse.containsMouse ? Style.borderStrong : Style.border

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) home.showMenu(card.uuid, menuButton)
                            }
                            onDoubleClicked: if (card.primary.action === "open") home.trigger(card.uuid, "open")
                        }

                        Rectangle {
                            id: dot
                            x: 20
                            y: 26
                            width: 10
                            height: 10
                            radius: 5
                            color: Style.stateColor(Logic.stateKind(card.device, card.session))
                        }
                        Text {
                            objectName: "deviceName"
                            anchors.left: dot.right
                            anchors.leftMargin: 10
                            anchors.right: menuButton.left
                            anchors.rightMargin: 4
                            anchors.verticalCenter: dot.verticalCenter
                            text: card.device.name || "未命名设备"
                            font.pixelSize: 16
                            font.bold: true
                            color: Style.text
                            elide: Text.ElideRight
                        }
                        DeskButton {
                            id: menuButton
                            objectName: "cardMenuButton"
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: dot.verticalCenter
                            kind: "ghost"
                            implicitWidth: 36
                            leftPadding: 0
                            rightPadding: 0
                            text: "⋯"
                            font.pixelSize: 18
                            onClicked: home.showMenu(card.uuid, menuButton)
                        }
                        Text {
                            objectName: "deviceAddress"
                            x: 40
                            y: 50
                            width: parent.width - 60
                            text: Logic.displayAddress(card.device.address) || " "
                            font.pixelSize: Style.fontSmall + 1
                            color: Style.textMuted
                            elide: Text.ElideMiddle
                        }
                        Text {
                            objectName: "deviceState"
                            x: 40
                            y: 72
                            width: parent.width - 60
                            text: Logic.stateText(card.device, card.session)
                            font.pixelSize: Style.fontSmall + 1
                            color: card.session !== "" ? Style.accent : Style.textFaint
                            elide: Text.ElideRight
                        }
                        DeskButton {
                            objectName: "cardPrimary"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 16
                            kind: card.primary.action === "open" ? "primary" : "secondary"
                            text: card.primary.text
                            enabled: card.primary.enabled
                            onClicked: home.trigger(card.uuid, card.primary.action)
                        }
                    }
                }
            }
        }
    }

    Menu {
        id: deviceMenu
        objectName: "deviceMenu"
        property string uuid: ""
        property var items: []
        function has(action) { return Logic.hasAction(items, action) }

        MenuItem { text: "断开"; visible: deviceMenu.has("disconnect"); height: visible ? implicitHeight : 0; onTriggered: home.trigger(deviceMenu.uuid, "disconnect") }
        MenuItem { text: "配对"; visible: deviceMenu.has("pair"); height: visible ? implicitHeight : 0; onTriggered: home.trigger(deviceMenu.uuid, "pair") }
        MenuItem { text: "唤醒"; visible: deviceMenu.has("wake"); height: visible ? implicitHeight : 0; onTriggered: home.trigger(deviceMenu.uuid, "wake") }
        MenuItem { text: "重命名"; visible: deviceMenu.has("rename"); height: visible ? implicitHeight : 0; onTriggered: home.trigger(deviceMenu.uuid, "rename") }
        MenuItem { text: "移除"; visible: deviceMenu.has("remove"); height: visible ? implicitHeight : 0; onTriggered: home.trigger(deviceMenu.uuid, "remove") }
    }
}
