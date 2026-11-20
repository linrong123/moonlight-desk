import QtQuick 2.9
import QtQuick.Controls 2.5
import QtQml.Models 2.2
import ComputerModel 1.0
import ComputerManager 1.0
import "deskstyle.js" as Style
import "desklogic.js" as Logic

// Wires the pure DeskHome view and DeskConnector flow to ComputerModel,
// ComputerManager and DeskSessions (manager process only).
DeskHome {
    id: desk
    property int modelRevision: 0

    devices: {
        modelRevision
        var list = []
        for (var i = 0; i < deviceRows.count; ++i) list.push(computers.get(i))
        return list
    }
    sessionStates: {
        DeskSessions.revision
        var states = {}
        for (var i = 0; i < devices.length; ++i) {
            var uuid = devices[i].uuid
            if (DeskSessions.isActive(uuid)) states[uuid] = DeskSessions.status(uuid) || "远程桌面已打开"
        }
        return states
    }
    connecting: connector.busy
    connectStatus: connector.statusText

    ComputerModel { id: computers }
    // Instantiator tracks the real model count, including discovery and removal.
    Instantiator { id: deviceRows; model: computers; delegate: QtObject {} onCountChanged: Qt.callLater(desk.bump) }
    function bump() { modelRevision++ }
    Component.onCompleted: { computers.initialize(ComputerManager); bump() }

    DeskConnector {
        id: connector
        devices: desk.devices
        sessionStates: desk.sessionStates
        onRequestAdd: function(address) { ComputerManager.addNewHostManually(address) }
        onRequestPair: function(uuid) { desk.beginPairing(uuid) }
        onRequestOpen: function(uuid) {
            if (pendingAddress !== "") desk.addressText = ""
            desk.openSession(uuid)
        }
        onFailed: function(message) { desk.showError(message) }
    }

    Connections {
        target: computers
        function onDataChanged() { desk.bump() }
        function onModelReset() { Qt.callLater(desk.bump) }
        function onPairingCompleted(error) {
            pairDialog.close()
            pairDialog.pin = ""
            if (!connector.pairingCompleted(error) && error !== undefined && error !== null && error !== "")
                desk.showError("配对失败：" + error)
        }
    }
    Connections {
        target: ComputerManager
        function onComputerAddCompleted(success, detectedPortBlocking) {
            if (!connector.addCompleted(success, detectedPortBlocking) && !success)
                desk.showError(Logic.addFailedText(detectedPortBlocking))
        }
    }
    Connections { target: DeskSessions; function onLaunchError(text) { desk.showError(text) } }

    function indexForUuid(uuid) {
        for (var i = 0; i < deviceRows.count; ++i) if (computers.get(i).uuid === uuid) return i
        return -1
    }
    function showError(text) { errorDialog.message = text; errorDialog.open() }
    function beginPairing(uuid) {
        var idx = indexForUuid(uuid)
        if (idx < 0) { connector.pairingCompleted("设备已被移除。"); return }
        pairDialog.pin = computers.generatePinString()
        pairDialog.open()
        computers.pairComputer(idx, pairDialog.pin)
    }
    function openSession(uuid) {
        if (DeskSessions.isActive(uuid)) { DeskSessions.focus(uuid); return }
        var d = device(uuid)
        if (d) DeskSessions.open(uuid, d.name)
    }

    onConnectRequested: function(address) { connector.submit(address) }
    onOpenDevice: function(uuid) {
        if (DeskSessions.isActive(uuid)) DeskSessions.focus(uuid)
        else connector.start(uuid)
    }
    onPairDevice: function(uuid) { connector.start(uuid) }
    onWakeDevice: function(uuid) { var idx = indexForUuid(uuid); if (idx >= 0) computers.wakeComputer(idx) }
    onDisconnectDevice: function(uuid) { DeskSessions.disconnectSession(uuid) }
    onRenameDevice: function(uuid) {
        var d = device(uuid)
        if (!d) return
        renameDialog.deviceUuid = uuid
        renameField.text = d.name
        renameDialog.open()
    }
    onRemoveDevice: function(uuid) {
        var d = device(uuid)
        if (!d || DeskSessions.isActive(uuid)) return
        removeDialog.deviceUuid = uuid
        removeDialog.message = "从“我的设备”中移除“" + d.name + "”？再次连接需要重新配对。"
        removeDialog.open()
    }
    onSettings: window.openDeskSettings()
    onQuitRequested: window.requestDeskQuit()

    DeskDialog {
        id: pairDialog
        objectName: "pairDialog"
        property string pin: ""
        title: "配对电脑"
        acceptText: ""
        closePolicy: Popup.NoAutoClose
        Text {
            objectName: "pairPrompt"
            width: parent.width
            text: "请在被控电脑弹出的窗口中输入验证码 " + pairDialog.pin
            wrapMode: Text.Wrap
            color: Style.text
            font.pixelSize: 15
        }
        Rectangle {
            width: parent.width
            height: 76
            radius: Style.radius
            color: Style.accentSoft
            Text {
                anchors.centerIn: parent
                text: pairDialog.pin
                font.pixelSize: 36
                font.bold: true
                font.letterSpacing: 10
                color: Style.accent
            }
        }
        Text {
            objectName: "pairFallback"
            width: parent.width
            text: "若被控端没有弹窗（旧版或原版 Sunshine），请在它的网页管理后台 PIN 页面输入。"
            wrapMode: Text.Wrap
            color: Style.textMuted
            font.pixelSize: Style.fontSmall
        }
    }
    DeskDialog {
        id: errorDialog
        objectName: "errorDialog"
        title: "连接提示"
    }
    DeskDialog {
        id: renameDialog
        property string deviceUuid
        title: "重命名设备"
        rejectText: "取消"
        acceptText: "保存"
        acceptEnabled: renameField.text.trim() !== ""
        TextField {
            id: renameField
            width: parent.width
            selectByMouse: true
            maximumLength: 100
            color: Style.text
            Keys.onReturnPressed: if (renameDialog.acceptEnabled) renameDialog.accept()
            Keys.onEnterPressed: if (renameDialog.acceptEnabled) renameDialog.accept()
        }
        onOpened: { renameField.forceActiveFocus(); renameField.selectAll() }
        onAccepted: {
            var idx = desk.indexForUuid(deviceUuid)
            if (idx >= 0 && renameField.text.trim()) computers.renameComputer(idx, renameField.text.trim())
        }
    }
    DeskDialog {
        id: removeDialog
        property string deviceUuid
        title: "移除设备"
        rejectText: "取消"
        acceptText: "移除"
        acceptKind: "danger"
        onAccepted: {
            var idx = desk.indexForUuid(deviceUuid)
            if (idx >= 0 && !DeskSessions.isActive(deviceUuid)) computers.deleteComputer(idx)
        }
    }
}
