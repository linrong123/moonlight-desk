import QtQuick 2.9
import "desklogic.js" as Logic

// Address bar flow: find or add the device, pair it when needed, then open
// the desktop. One attempt per submit; failures are reported once and never
// retried automatically (pairing/auth errors included).
QtObject {
    id: connector

    // Inputs (bound by DeskView; plain objects in tests).
    property var devices: []
    property var sessionStates: ({})
    property int locateTimeout: 15000
    property int pairedTimeout: 30000

    // "idle" | "adding" | "locating" | "pairing" | "confirming"
    property string phase: "idle"
    property string pendingAddress: ""
    property string targetUuid: ""
    readonly property bool busy: phase !== "idle"
    readonly property string statusText: phase === "adding" ? "正在查找这台电脑…"
                                        : phase === "locating" ? "正在读取设备信息…"
                                        : phase === "pairing" ? "等待配对完成…"
                                        : phase === "confirming" ? "配对成功，正在连接…"
                                        : ""

    signal requestAdd(string address)
    signal requestPair(string uuid)
    signal requestOpen(string uuid)
    signal failed(string message)

    property Timer timer: Timer {
        repeat: false
        onTriggered: connector.timedOut()
    }

    function submit(text) {
        if (busy) return false
        var input = String(text || "").trim()
        if (!input) {
            failed("请输入被控端的 IP 地址或域名。")
            return false
        }
        if (!Logic.normalizeAddress(input)) {
            failed("地址格式不正确。请输入 IP 地址或域名，例如 192.168.1.20。")
            return false
        }
        pendingAddress = input
        var existing = Logic.findDeviceByAddress(devices, input)
        if (existing) {
            targetUuid = existing.uuid
            proceed()
        } else {
            phase = "adding"
            requestAdd(input)
        }
        return true
    }

    // Card entry: same checks as the address flow, starting from a known device.
    function start(uuid) {
        if (busy || !Logic.findDevice(devices, uuid)) return false
        pendingAddress = ""
        targetUuid = uuid
        proceed()
        return true
    }

    function addCompleted(success, detectedPortBlocking) {
        if (phase !== "adding") return false
        if (!success) {
            finish()
            failed(Logic.addFailedText(detectedPortBlocking))
            return true
        }
        phase = "locating"
        timer.interval = locateTimeout
        timer.restart()
        locate()
        return true
    }

    function pairingCompleted(error) {
        if (phase !== "pairing") return false
        if (error !== undefined && error !== null && error !== "") {
            finish()
            failed("配对失败：" + error)
            return true
        }
        phase = "confirming"
        timer.interval = pairedTimeout
        timer.restart()
        proceed()
        return true
    }

    function cancel() {
        finish()
    }

    onDevicesChanged: {
        if (phase === "locating") locate()
        else if (phase === "confirming") proceed()
    }

    function locate() {
        var device = Logic.findDeviceByAddress(devices, pendingAddress)
        if (!device) return
        targetUuid = device.uuid
        proceed()
    }

    function proceed() {
        var device = Logic.findDevice(devices, targetUuid)
        if (!device) {
            if (phase === "confirming") {
                finish()
                failed("设备已被移除。")
            }
            return
        }
        if (sessionStates && sessionStates[device.uuid]) {
            open(device.uuid)
            return
        }
        if (device.statusUnknown) {
            // Wait for the first status poll; bounded by the timer.
            if (phase === "idle") {
                phase = "locating"
                timer.interval = locateTimeout
                timer.restart()
            }
            return
        }
        if (!device.online) {
            finish()
            failed(Logic.offlineText(device))
            return
        }
        if (device.serverSupported === false) {
            finish()
            failed("被控端的版本不受支持，请更新被控端后再连接。")
            return
        }
        if (!device.paired) {
            if (phase === "confirming") return // Pair phase is refreshed by the next poll.
            timer.stop()
            phase = "pairing"
            requestPair(device.uuid)
            return
        }
        open(device.uuid)
    }

    function open(uuid) {
        finish()
        requestOpen(uuid)
    }

    function finish() {
        timer.stop()
        phase = "idle"
    }

    function timedOut() {
        var was = phase
        if (was !== "locating" && was !== "confirming") return
        finish()
        failed(was === "confirming" ? "配对已完成，但暂时无法确认设备状态。请稍后在“我的设备”中连接。"
                                    : "暂时无法确认这台电脑的状态。请稍后在“我的设备”中重试。")
    }
}
