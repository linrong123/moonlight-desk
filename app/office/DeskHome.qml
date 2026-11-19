import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

Rectangle {
    id: home
    objectName: "远程桌面"
    color: "#f5f7fa"
    property var devices
    property var selectedDevice: ({})
    property int selectedIndex: -1
    property int sessionCount: 0
    property bool sessionActive: false
    property string sessionStatus: ""
    property var sessionStates: ({})
    property string searchText: search.text
    signal selectDevice(int index)
    signal addDevice()
    signal settings()
    signal enterDesktop()
    signal disconnectDesktop()
    signal pairDevice()
    signal wakeDevice()
    signal renameDevice()
    signal removeDevice()
    signal quitRequested()
    function stateText(device) {
        if (!device || !device.name) return ""
        if (device.statusUnknown) return "正在检测"
        if (!device.online) return "离线"
        if (!device.paired) return "待配对"
        return "在线"
    }
    function stateColor(device) {
        return device.statusUnknown ? "#a2aaba" : (!device.online ? "#a2aaba" : (!device.paired ? "#d99a32" : "#2fa985"))
    }
    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.preferredWidth: 292
            Layout.fillHeight: true
            color: "#ffffff"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 18
                RowLayout {
                    spacing: 10
                    Rectangle {
                        width: 34; height: 34; radius: 11; color: "#4674ef"
                        Text { anchors.centerIn: parent; text: "D"; color: "white"; font.pixelSize: 20; font.bold: true }
                    }
                    Column {
                        Text { text: "Moonlight Desk"; font.pixelSize: 18; font.bold: true; color: "#25324a" }
                        Text { text: "你的远程工作空间"; font.pixelSize: 11; color: "#8a94a6" }
                    }
                }
                TextField {
                    id: search
                    objectName: "deviceSearch"
                    Layout.fillWidth: true
                    placeholderText: "搜索设备"
                    font.pixelSize: 13
                    selectByMouse: true
                    background: Rectangle { color: "#f4f6f9"; radius: 9; border.color: search.activeFocus ? "#92acf4" : "#edf0f5" }
                    leftPadding: 13
                }
                RowLayout {
                    Text { text: "我的设备"; font.pixelSize: 12; font.bold: true; color: "#8792a4"; Layout.fillWidth: true }
                    Button { text: "+ 添加"; flat: true; font.pixelSize: 12; onClicked: home.addDevice() }
                }
                ListView {
                    id: deviceList
                    objectName: "deviceList"
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    clip: true
                    spacing: 8
                    model: home.devices
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Item {
                        property bool matches: !home.searchText || model.name.toLowerCase().indexOf(home.searchText.toLowerCase()) !== -1
                        width: deviceList.width
                        height: matches ? 76 : 0
                        visible: matches
                        Rectangle {
                            anchors.fill: parent
                            radius: 11
                            color: home.selectedIndex === index ? "#edf2ff" : (deviceMouse.containsMouse ? "#f7f9fc" : "#ffffff")
                            border.color: home.selectedIndex === index ? "#d8e3ff" : "transparent"
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 13; spacing: 12
                                Rectangle {
                                    width: 34; height: 29; radius: 5; color: "transparent"; border.width: 1.5; border.color: home.selectedIndex === index ? "#577fe3" : "#a4afbf"
                                    Rectangle { width: 12; height: 2; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: -5; color: parent.border.color }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 5
                                    Text { text: model.name; color: "#2c3951"; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Row {
                                        spacing: 5
                                        Rectangle { width: 6; height: 6; radius: 3; color: home.sessionStates[model.uuid] ? "#4674ef" : home.stateColor(model); anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: home.sessionStates[model.uuid] || home.stateText(model); color: "#8792a4"; font.pixelSize: 11 }
                                    }
                                }
                            }
                            MouseArea { id: deviceMouse; anchors.fill: parent; hoverEnabled: true; onClicked: home.selectDevice(index) }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: deviceList.count === 0 ? "还没有设备\n添加电脑后，即可开始远程办公" : ""
                        color: "#9aa4b4"; font.pixelSize: 12; lineHeight: 1.6
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: "#eef1f5" }
                RowLayout {
                    Button { text: "设置"; flat: true; onClicked: home.settings() }
                    Item { Layout.fillWidth: true }
                    Button { text: "退出"; flat: true; onClicked: home.quitRequested() }
                }
            }
        }
        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#e7ecf3" }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 38; spacing: 20
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        spacing: 5
                        Text { text: "工作台"; font.pixelSize: 23; font.bold: true; color: "#26334b" }
                        Text { text: "每台电脑，一个独立桌面窗口"; font.pixelSize: 12; color: "#8b96a8" }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: sessionLabel.implicitWidth + 24; height: 29; radius: 14; color: "#e9eef7"
                        Text { id: sessionLabel; anchors.centerIn: parent; text: home.sessionCount > 0 ? home.sessionCount + " 个桌面会话" : "就绪"; color: "#6f809d"; font.pixelSize: 11 }
                    }
                }
                Item { Layout.fillHeight: true; Layout.maximumHeight: 25 }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.maximumHeight: 405
                    Layout.minimumHeight: 330
                    radius: 17; color: "white"; border.color: "#e7ecf3"
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 64
                        spacing: 18
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 94; height: 78; radius: 19; color: "#edf2ff"
                            Rectangle {
                                anchors.centerIn: parent; width: 48; height: 33; radius: 4; color: "#f8faff"; border.color: "#7899ed"; border.width: 2
                                Rectangle { width: 2; height: 7; color: "#7899ed"; anchors.top: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter }
                                Rectangle { width: 22; height: 2; color: "#7899ed"; anchors.top: parent.bottom; anchors.topMargin: 6; anchors.horizontalCenter: parent.horizontalCenter }
                            }
                        }
                        Text {
                            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                            text: home.selectedDevice.name || "连接你的办公电脑"
                            font.pixelSize: 25; font.bold: true; color: "#26334b"; elide: Text.ElideRight
                        }
                        Text {
                            objectName: "deviceStatus"
                            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                            text: !home.selectedDevice.name ? "从左侧选择设备，或添加一台新电脑" : (home.sessionActive ? home.sessionStatus : (home.selectedDevice.statusUnknown ? "正在检测设备状态，请稍候" : (!home.selectedDevice.online ? "设备当前离线，请确认电脑已开机并连接网络" : (!home.selectedDevice.paired ? "首次连接，请先与这台电脑配对" : "设备已就绪，可以进入远程桌面"))))
                            color: "#8b96a8"; font.pixelSize: 13
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter; spacing: 12
                            Button {
                                objectName: "enterDesktopButton"
                                text: home.sessionActive ? "显示桌面窗口" : "进入桌面"
                                visible: !!home.selectedDevice.name && (home.selectedDevice.paired || home.sessionActive)
                                enabled: home.sessionActive || !!(home.selectedDevice.online && !home.selectedDevice.statusUnknown && home.selectedDevice.serverSupported)
                                implicitWidth: 168; implicitHeight: 46
                                contentItem: Text { text: parent.text; color: parent.enabled ? "white" : "#9aa6bf"; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: 10; color: parent.enabled ? (parent.down ? "#365dcc" : "#4674ef") : "#edf1f8" }
                                onClicked: home.enterDesktop()
                            }
                            Button { text: "开始配对"; visible: !!home.selectedDevice.name && home.selectedDevice.online && !home.selectedDevice.statusUnknown && !home.selectedDevice.paired; onClicked: home.pairDevice() }
                            Button { text: "唤醒电脑"; visible: !!home.selectedDevice.name && !home.selectedDevice.online && !home.selectedDevice.statusUnknown && home.selectedDevice.wakeable; onClicked: home.wakeDevice() }
                            Button { text: "添加设备"; visible: !home.selectedDevice.name; onClicked: home.addDevice() }
                            Button { objectName: "disconnectButton"; text: "断开 / 取消"; visible: home.sessionActive; flat: true; onClicked: home.disconnectDesktop() }
                        }
                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: home.selectedDevice.online && !home.selectedDevice.serverSupported ? "此电脑的串流服务版本不受支持，请检查主机端版本" : ""; color: "#b58030"; font.pixelSize: 12; wrapMode: Text.Wrap }
                    }
                }
                RowLayout {
                    visible: !!home.selectedDevice.name
                    Text { text: "设备管理"; color: "#8b96a8"; font.pixelSize: 12; Layout.fillWidth: true }
                    Button { text: "重命名"; flat: true; onClicked: home.renameDevice() }
                    Button { text: "移除设备"; flat: true; enabled: !home.sessionActive; onClicked: home.removeDevice() }
                }
                Item { Layout.fillHeight: true }
                Text { text: "Moonlight Desk  ·  让熟悉的电脑，随时在身边"; color: "#a4adbb"; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
            }
        }
    }
}
