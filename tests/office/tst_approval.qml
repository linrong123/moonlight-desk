import QtQuick 2.9
import QtTest 1.2
import "../../app/office" as Office

TestCase {
    name: "ApprovalWaiting"
    when: windowShown
    visible: true
    width: 400
    height: 200

    Office.ApprovalWaiting { id: approval }
    SignalSpy { id: cancelSpy; target: approval; signalName: "cancelRequested" }

    function init() {
        approval.waiting = false
        cancelSpy.clear()
        wait(20)
    }

    function test_hiddenUntilWaiting() {
        verify(!approval.visible)
        approval.cancel()
        compare(cancelSpy.count, 0)
        approval.waiting = true
        verify(approval.visible)
        verify(findChild(approval, "approvalCancel").enabled)
    }

    function test_cancelOnce() {
        approval.waiting = true
        wait(20)
        var button = findChild(approval, "approvalCancel")
        mouseClick(button)
        compare(cancelSpy.count, 1)
        verify(!button.enabled)
        compare(findChild(approval, "approvalHint").text, "正在取消…")
        approval.cancel()
        mouseClick(button)
        compare(cancelSpy.count, 1)
    }

    function test_resetWhenWaitingEnds() {
        approval.waiting = true
        approval.cancel()
        approval.waiting = false
        verify(!approval.visible)
        verify(!approval.cancelling)
        approval.waiting = true
        approval.cancel()
        compare(cancelSpy.count, 2)
    }
}
