import QtQuick 2.9
import "desklogic.js" as Logic

// Address bar flow: find or add the device, pair it when needed, then open
// the desktop. One attempt per submit; failures are reported once and never
// retried automatically (pairing/auth errors included).
//
// ComputerManager's add and pairing results carry no request identity, so at
// most one add and one pairing request are in flight at a time. cancel() only
// abandons the attempt locally: the request keeps running and its late result
// is swallowed ("stale"). Asking to pair the same device again while its
// abandoned request is still running resumes waiting on it (same PIN).
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
    // Requests sent to ComputerManager that have not reported back yet.
    property bool addInFlight: false
    property string pairInFlightUuid: ""
    readonly property bool busy: phase !== "idle"
    readonly property string statusText: phase === "adding" ? "正在查找这台电脑…"
                                        : phase === "locating" ? "正在读取设备信息…"
                                        : phase === "pairing" ? "等待配对完成…"
                                        : phase === "confirming" ? "配对成功，正在连接…"
                                        : ""

    signal requestAdd(string address)
    // resume: a pairing request for this device is still running; show its
    // PIN again instead of starting a new one.
    signal requestPair(string uuid, bool resume)
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
        var existing = Logic.findDeviceByAddress(devices, input)
        if (!existing && addInFlight) {
            failed("上一次查找还没有结束，请稍候再试。")
            return false
        }
        pendingAddress = input
        if (existing) {
            targetUuid = existing.uuid
            proceed()
        } else {
            targetUuid = ""
            phase = "adding"
            addInFlight = true
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

    // Result handlers return "handled" (live attempt), "stale" (result of a
    // cancelled attempt, ignored) or "" (no request of ours was in flight).
    function addCompleted(success, detectedPortBlocking) {
        if (!addInFlight) return ""
        addInFlight = false
        if (phase !== "adding") return "stale"
        if (!success) {
            finish()
            failed(Logic.addFailedText(detectedPortBlocking))
            return "handled"
        }
        phase = "locating"
        timer.interval = locateTimeout
        timer.restart()
        locate()
        return "handled"
    }

    function pairingCompleted(error) {
        if (pairInFlightUuid === "") return ""
        pairInFlightUuid = ""
        if (phase !== "pairing") return "stale"
        if (error !== undefined && error !== null && error !== "") {
            finish()
            failed("配对失败：" + error)
            return "handled"
        }
        phase = "confirming"
        timer.interval = pairedTimeout
        timer.restart()
        proceed()
        return "handled"
    }

    // Abandon the current attempt without an error; the address bar is free again.
    function cancel() {
        finish()
    }

    onDevicesChanged: {
        if (phase === "locating") locate()
        else if (phase === "confirming") proceed()
    }

    function locate() {
        // Card entries have no address: wait on the known device instead.
        if (pendingAddress !== "") {
            var device = Logic.findDeviceByAddress(devices, pendingAddress)
            if (!device) return
            targetUuid = device.uuid
        }
        proceed()
    }

    function proceed() {
        var device = Logic.findDevice(devices, targetUuid)
        if (!device) {
            if (phase === "confirming" || phase === "locating") {
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
            if (pairInFlightUuid !== "" && pairInFlightUuid !== device.uuid) {
                finish()
                failed("另一台电脑的配对还没有结束。请先在那台电脑上输入验证码，或稍后再试。")
                return
            }
            var resume = pairInFlightUuid === device.uuid
            timer.stop()
            phase = "pairing"
            pairInFlightUuid = device.uuid
            requestPair(device.uuid, resume)
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
