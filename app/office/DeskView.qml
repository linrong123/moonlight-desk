import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQml.Models 2.2
import ComputerModel 1.0
import ComputerManager 1.0

DeskHome {
    id: desk
    property string selectedUuid: ""
    property int modelRevision: 0
    devices: computers
    selectedIndex: {
        modelRevision
        for (var i = 0; i < deviceRows.count; ++i) {
            if (computers.get(i).uuid === selectedUuid) return i
        }
        return -1
    }
    selectedDevice: {
        modelRevision
        return selectedIndex >= 0 ? computers.get(selectedIndex) : ({})
    }
    sessionStates: {
        DeskSessions.revision
        modelRevision
        var states = {}
        for (var i = 0; i < deviceRows.count; ++i) {
            var uuid = computers.get(i).uuid
            if (DeskSessions.isActive(uuid)) states[uuid] = DeskSessions.status(uuid)
        }
        return states
    }
    sessionCount: DeskSessions.count
    sessionActive: { DeskSessions.revision; return !!selectedUuid && DeskSessions.isActive(selectedUuid) }
    sessionStatus: { DeskSessions.revision; return selectedUuid ? DeskSessions.status(selectedUuid) : "" }
    ComputerModel { id: computers }
    // Instantiator tracks the real model count, including discovery and removal.
    Instantiator { id: deviceRows; model: computers; delegate: QtObject {} onCountChanged: Qt.callLater(desk.refreshSelection) }
    function refreshSelection() {
        modelRevision++
        if (selectedIndex < 0 && deviceRows.count > 0) selectedUuid = computers.get(0).uuid
        if (deviceRows.count === 0) selectedUuid = ""
    }
    Component.onCompleted: { computers.initialize(ComputerManager); refreshSelection() }
    Connections {
        target: computers
        function onDataChanged() { desk.modelRevision++ }
        function onModelReset() { Qt.callLater(desk.refreshSelection) }
        function onPairingCompleted(error) {
            pairDialog.close()
            pairDialog.pin = ""
            if (error !== undefined && error !== null && error !== "") desk.showError(error)
        }
    }
    Connections {
        target: ComputerManager
        function onComputerAddCompleted(success, detectedPortBlocking) {
            if (!success) desk.showError(detectedPortBlocking ? "无法连接这台电脑，网络可能阻止了连接。请检查主机地址与网络。" : "无法连接这台电脑，请检查主机地址，并确认串流服务已开启。")
        }
    }
    Connections { target: DeskSessions; function onLaunchError(text) { desk.showError(text) } }
    function showError(text) { errorText.text = text; errorDialog.open() }
    onSelectDevice: function(index) { selectedUuid = computers.get(index).uuid }
    onAddDevice: window.openDeskAddPc()
    onSettings: window.openDeskSettings()
    onQuitRequested: window.requestDeskQuit()
    onEnterDesktop: {
        if (sessionActive) DeskSessions.focus(selectedUuid)
        else if (selectedIndex >= 0 && selectedDevice.online && selectedDevice.paired && !selectedDevice.statusUnknown && selectedDevice.serverSupported) DeskSessions.open(selectedUuid, selectedDevice.name)
    }
    onDisconnectDesktop: DeskSessions.disconnectSession(selectedUuid)
    onPairDevice: {
        if (selectedIndex < 0 || !selectedDevice.online || selectedDevice.paired) return
        pairDialog.pin = computers.generatePinString()
        pairDialog.open()
        computers.pairComputer(selectedIndex, pairDialog.pin)
    }
    onWakeDevice: { if (selectedIndex >= 0) computers.wakeComputer(selectedIndex) }
    onRenameDevice: { renameDialog.deviceUuid = selectedUuid; renameField.text = selectedDevice.name; renameDialog.open() }
    onRemoveDevice: { if (!sessionActive) { removeDialog.deviceUuid = selectedUuid; removeDialog.deviceName = selectedDevice.name; removeDialog.open() } }
    function indexForUuid(uuid) {
        for (var i = 0; i < deviceRows.count; ++i) if (computers.get(i).uuid === uuid) return i
        return -1
    }
    Dialog {
        id: pairDialog
        property string pin: ""
        anchors.centerIn: parent
        width: Math.min(420, desk.width - 40)
        title: "配对电脑"
        modal: true
        closePolicy: Popup.NoAutoClose
        contentItem: Column {
            spacing: 18
            Text { width: parent.width; text: "在远端电脑的 Sunshine 管理页面中输入此 PIN。配对完成后本窗口会自动关闭。"; wrapMode: Text.Wrap; color: "#55647a"; font.pixelSize: 14 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: pairDialog.pin; font.pixelSize: 34; font.letterSpacing: 8; color: "#4674ef" }
        }
    }
    Dialog {
        id: errorDialog
        anchors.centerIn: parent
        width: Math.min(440, desk.width - 40)
        title: "连接提示"
        modal: true
        standardButtons: Dialog.Ok
        Text { id: errorText; width: parent.width; wrapMode: Text.Wrap; color: "#55647a" }
    }
    Dialog {
        id: renameDialog
        property string deviceUuid
        anchors.centerIn: parent
        title: "重命名设备"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        TextField { id: renameField; width: 300; selectByMouse: true; maximumLength: 100 }
        onOpened: { renameField.forceActiveFocus(); renameField.selectAll() }
        onAccepted: { var idx = desk.indexForUuid(deviceUuid); if (idx >= 0 && renameField.text.trim()) computers.renameComputer(idx, renameField.text.trim()) }
    }
    Dialog {
        id: removeDialog
        property string deviceUuid
        property string deviceName
        anchors.centerIn: parent
        title: "移除设备"
        modal: true
        standardButtons: Dialog.Yes | Dialog.No
        Text { text: "从设备列表移除“" + removeDialog.deviceName + "”？"; color: "#55647a" }
        onAccepted: { var idx = desk.indexForUuid(deviceUuid); if (idx >= 0 && !DeskSessions.isActive(deviceUuid)) computers.deleteComputer(idx) }
    }
}
