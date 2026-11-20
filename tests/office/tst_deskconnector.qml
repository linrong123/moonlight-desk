import QtQuick 2.9
import QtTest 1.2
import "../../app/office"

TestCase {
    name: "DeskConnector"

    DeskConnector { id: connector; locateTimeout: 200; pairedTimeout: 200 }
    SignalSpy { id: addSpy; target: connector; signalName: "requestAdd" }
    SignalSpy { id: pairSpy; target: connector; signalName: "requestPair" }
    SignalSpy { id: openSpy; target: connector; signalName: "requestOpen" }
    SignalSpy { id: failSpy; target: connector; signalName: "failed" }

    function dev(uuid, address, extra) {
        var d = { uuid: uuid, name: "PC " + uuid, address: address, addresses: [address],
                  online: true, paired: true, wakeable: false, statusUnknown: false, serverSupported: true }
        for (var k in extra) d[k] = extra[k]
        return d
    }

    function init() {
        connector.cancel()
        connector.addInFlight = false
        connector.pairInFlightUuid = ""
        connector.devices = []
        connector.sessionStates = {}
        addSpy.clear(); pairSpy.clear(); openSpy.clear(); failSpy.clear()
    }

    function test_rejectsBadInput() {
        verify(!connector.submit("  "))
        compare(failSpy.count, 1)
        verify(!connector.submit("a b"))
        compare(failSpy.count, 2)
        compare(addSpy.count, 0)
        verify(!connector.busy)
    }

    function test_existingPairedOpensDirectly() {
        connector.devices = [dev("a", "10.0.0.5:47989")]
        verify(connector.submit("10.0.0.5"))
        compare(openSpy.count, 1)
        compare(openSpy.signalArguments[0][0], "a")
        compare(addSpy.count, 0)
        verify(!connector.busy)
    }

    function test_existingSessionFocuses() {
        connector.devices = [dev("a", "10.0.0.5:47989", { paired: false })]
        connector.sessionStates = { "a": "远程桌面已打开" }
        connector.submit("10.0.0.5")
        compare(openSpy.count, 1)
        compare(pairSpy.count, 0)
    }

    function test_newAddressAddsPairsThenOpens() {
        verify(connector.submit("10.0.0.9"))
        compare(connector.phase, "adding")
        compare(addSpy.signalArguments[0][0], "10.0.0.9")
        verify(!connector.submit("10.0.0.9")) // busy: no second attempt
        compare(addSpy.count, 1)

        verify(connector.addCompleted(true, false))
        compare(connector.phase, "locating")
        connector.devices = [dev("n", "10.0.0.9:47989", { paired: false })]
        compare(connector.phase, "pairing")
        compare(pairSpy.signalArguments[0][0], "n")
        compare(pairSpy.signalArguments[0][1], false)

        verify(connector.pairingCompleted(""))
        compare(connector.phase, "confirming")
        compare(openSpy.count, 0) // still unpaired in the model
        connector.devices = [dev("n", "10.0.0.9:47989", { paired: true })]
        compare(openSpy.count, 1)
        compare(openSpy.signalArguments[0][0], "n")
        verify(!connector.busy)
        compare(failSpy.count, 0)
    }

    function test_addFailureReportedOnce() {
        connector.submit("10.0.0.9")
        verify(connector.addCompleted(false, true))
        compare(failSpy.count, 1)
        verify(String(failSpy.signalArguments[0][0]).indexOf("网络") >= 0)
        verify(!connector.busy)
        verify(!connector.addCompleted(false, true)) // late signal ignored
        compare(failSpy.count, 1)
        compare(addSpy.count, 1)
    }

    function test_pairingFailureNotRetried() {
        connector.devices = [dev("a", "10.0.0.5:47989", { paired: false })]
        connector.submit("10.0.0.5")
        compare(pairSpy.count, 1)
        verify(connector.pairingCompleted("PIN 错误"))
        compare(failSpy.count, 1)
        compare(failSpy.signalArguments[0][0], "配对失败：PIN 错误")
        verify(!connector.busy)
        connector.devices = [dev("a", "10.0.0.5:47989", { paired: false })]
        wait(300)
        compare(pairSpy.count, 1)
        compare(openSpy.count, 0)
        verify(!connector.pairingCompleted(""))
    }

    function test_offlineAndUnsupported() {
        connector.devices = [dev("a", "10.0.0.5:47989", { online: false, wakeable: true })]
        connector.submit("10.0.0.5")
        compare(failSpy.count, 1)
        verify(String(failSpy.signalArguments[0][0]).indexOf("唤醒") >= 0)
        connector.devices = [dev("a", "10.0.0.5:47989", { serverSupported: false })]
        connector.submit("10.0.0.5")
        compare(failSpy.count, 2)
        compare(openSpy.count, 0)
    }

    function test_locateTimeout() {
        connector.submit("10.0.0.9")
        connector.addCompleted(true, false)
        tryCompare(connector, "phase", "idle", 2000)
        compare(failSpy.count, 1)
        compare(pairSpy.count, 0)
    }

    function test_unknownStatusWaitsThenProceeds() {
        connector.devices = [dev("a", "10.0.0.5:47989", { statusUnknown: true })]
        connector.submit("10.0.0.5")
        compare(connector.phase, "locating")
        connector.devices = [dev("a", "10.0.0.5:47989")]
        compare(openSpy.count, 1)
        verify(!connector.busy)
    }

    function test_startFromCard() {
        connector.devices = [dev("a", "10.0.0.5:47989", { paired: false })]
        verify(!connector.start("missing"))
        verify(connector.start("a"))
        compare(connector.pendingAddress, "")
        compare(pairSpy.count, 1)
        verify(connector.pairingCompleted(""))
        connector.devices = [dev("a", "10.0.0.5:47989")]
        compare(openSpy.count, 1)
    }

    function test_removedWhileConfirming() {
        connector.devices = [dev("a", "10.0.0.5:47989", { paired: false })]
        connector.start("a")
        connector.pairingCompleted("")
        connector.devices = []
        compare(failSpy.count, 1)
        compare(failSpy.signalArguments[0][0], "设备已被移除。")
        verify(!connector.busy)
    }

    function test_startFromCardWaitsForUnknownStatus() {
        connector.devices = [dev("a", "10.0.0.5:47989", { statusUnknown: true, paired: false })]
        verify(connector.start("a"))
        compare(connector.phase, "locating")
        connector.devices = [dev("a", "10.0.0.5:47989", { paired: false })]
        compare(connector.phase, "pairing")
        compare(pairSpy.signalArguments[0][0], "a")
        connector.cancel()
        connector.pairingCompleted("")

        connector.devices = [dev("b", "10.0.0.6:47989", { statusUnknown: true })]
        verify(connector.start("b"))
        connector.devices = [dev("b", "10.0.0.6:47989")]
        compare(openSpy.count, 1)
        compare(openSpy.signalArguments[0][0], "b")
        verify(!connector.busy)
        compare(failSpy.count, 0)
    }

    function test_startFromCardUnknownThenRemoved() {
        connector.devices = [dev("a", "10.0.0.5:47989", { statusUnknown: true })]
        connector.start("a")
        connector.devices = []
        compare(failSpy.count, 1)
        compare(failSpy.signalArguments[0][0], "设备已被移除。")
        verify(!connector.busy)
    }

    function test_startFromCardUnknownTimesOut() {
        connector.devices = [dev("a", "10.0.0.5:47989", { statusUnknown: true })]
        connector.start("a")
        tryCompare(connector, "phase", "idle", 2000)
        compare(failSpy.count, 1)
        compare(openSpy.count, 0)
    }

    function test_cancelIsSilentAndFreesInput() {
        connector.submit("10.0.0.9")
        verify(connector.busy)
        connector.cancel()
        verify(!connector.busy)
        compare(connector.phase, "idle")
        compare(connector.statusText, "")
        compare(failSpy.count, 0)
        // Existing devices still connect while the abandoned add is running.
        connector.devices = [dev("a", "10.0.0.5:47989")]
        verify(connector.submit("10.0.0.5"))
        compare(openSpy.count, 1)
    }

    function test_cancelledAddResultIgnored() {
        connector.submit("10.0.0.9")
        connector.cancel()
        // Only one add may run: a new address waits for the abandoned one.
        verify(!connector.submit("10.0.0.10"))
        compare(failSpy.count, 1)
        compare(addSpy.count, 1)

        compare(connector.addCompleted(true, false), "stale")
        compare(connector.phase, "idle")
        connector.devices = [dev("n", "10.0.0.9:47989", { paired: false })]
        compare(pairSpy.count, 0)
        compare(openSpy.count, 0)
        compare(connector.addCompleted(false, true), "") // nothing in flight
        compare(failSpy.count, 1)

        verify(connector.submit("10.0.0.10"))
        compare(addSpy.count, 2)
        compare(connector.addCompleted(false, false), "handled")
        compare(failSpy.count, 2)
    }

    function test_cancelledPairingResultIgnored() {
        connector.devices = [dev("a", "10.0.0.5:47989", { paired: false })]
        connector.start("a")
        compare(connector.phase, "pairing")
        connector.cancel()
        verify(!connector.busy)
        compare(connector.pairingCompleted(""), "stale")
        compare(connector.phase, "idle")
        connector.devices = [dev("a", "10.0.0.5:47989")]
        compare(openSpy.count, 0)
        compare(failSpy.count, 0)
        compare(connector.pairingCompleted("PIN 错误"), "")

        connector.devices = [dev("a", "10.0.0.5:47989", { paired: false })]
        connector.start("a")
        connector.cancel()
        compare(connector.pairingCompleted("PIN 错误"), "stale") // late error: no prompt
        compare(failSpy.count, 0)
    }

    function test_pairingAgainResumesAbandonedRequest() {
        connector.devices = [dev("a", "10.0.0.5:47989", { paired: false })]
        connector.start("a")
        connector.cancel()
        connector.submit("10.0.0.5")
        compare(pairSpy.count, 2)
        compare(pairSpy.signalArguments[1][0], "a")
        compare(pairSpy.signalArguments[1][1], true)
        compare(connector.pairingCompleted(""), "handled")
        connector.devices = [dev("a", "10.0.0.5:47989")]
        compare(openSpy.count, 1)
        compare(failSpy.count, 0)
    }

    function test_otherPairingWaitsForAbandonedRequest() {
        connector.devices = [dev("a", "10.0.0.5:47989", { paired: false }),
                             dev("b", "10.0.0.6:47989", { paired: false })]
        connector.start("a")
        connector.cancel()
        verify(connector.start("b"))
        compare(failSpy.count, 1)
        verify(String(failSpy.signalArguments[0][0]).indexOf("另一台电脑") >= 0)
        compare(pairSpy.count, 1)
        verify(!connector.busy)
        compare(connector.pairingCompleted("PIN 错误"), "stale")
        connector.start("b")
        compare(pairSpy.count, 2)
        compare(pairSpy.signalArguments[1][0], "b")
        compare(pairSpy.signalArguments[1][1], false)
    }

    function test_ipv6Input() {
        connector.devices = [dev("v6", "[fe80::1]:47989"),
                             dev("p", "[2001:db8::5]:48000")]
        var same = ["fe80::1", "FE80:0:0::1", "[fe80::1]", "[fe80:0::0001]:47989"]
        for (var i = 0; i < same.length; ++i) {
            verify(connector.submit(same[i]), same[i])
            compare(openSpy.count, i + 1)
            compare(openSpy.signalArguments[i][0], "v6")
        }
        verify(connector.submit("[2001:db8:0:0:0:0:0:5]:48000"))
        compare(openSpy.signalArguments[4][0], "p")
        compare(addSpy.count, 0)

        // Different port: a new device, passed on exactly as typed.
        verify(connector.submit("[fe80::1]:48000"))
        compare(addSpy.signalArguments[0][0], "[fe80::1]:48000")
        connector.addCompleted(true, false)
        connector.devices = [dev("n", "[FE80::0:1]:48000", { paired: true })]
        compare(openSpy.count, 6)
        compare(openSpy.signalArguments[5][0], "n")

        verify(!connector.submit("fe80:::1"))
        verify(!connector.submit("[fe80::1"))
        verify(!connector.submit("1:2:3:4:5:6:7:8:9"))
        compare(failSpy.count, 3)
    }
}
