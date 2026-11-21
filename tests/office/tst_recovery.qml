import QtQuick 2.0
import QtTest 1.2
import "../../app/office" as Office

TestCase {
    name: "OfficeRecovery"
    when: windowShown
    visible: true
    width: 100
    height: 100
    property var controller
    property var navigation
    property int navigations: 0
    property int policyCalls: 0
    property int nextCalls: 0
    property int cancelCalls: 0
    property int completions: 0
    property int retries: 0
    property int delay: 0
    property bool allowNext: true
    property bool parked: false
    property int releaseCalls: 0

    function fakeSession() {
        return {
            officeRetryDelay: function() { policyCalls++; return delay },
            officeNextSession: function() { nextCalls++; return allowNext ? fakeSession() : null },
            officeCancelRecovery: function() { cancelCalls++ },
            officeWindowParked: function() { return parked },
            officeReleaseParkedWindow: function() { releaseCalls++ }
        }
    }
    Component {
        id: recoveryComponent
        Office.OfficeRecovery {
            onCompleted: completions++
            onRetryReady: retries++
        }
    }
    Component {
        id: navigationComponent
        Item {
            // Same forwarding boundary as StreamSegue, with a navigation parent.
            Keys.forwardTo: [controller]
            Keys.onEscapePressed: navigations++
            Keys.onBackPressed: navigations++
            Keys.onMenuPressed: navigations++
            Keys.onHangupPressed: navigations++
        }
    }
    function init() {
        policyCalls = 0; nextCalls = 0; cancelCalls = 0
        completions = 0; retries = 0; delay = 0; allowNext = true
        navigations = 0; parked = false; releaseCalls = 0
        controller = recoveryComponent.createObject(this, { session: fakeSession() })
        navigation = navigationComponent.createObject(this)
    }
    function cleanup() { navigation.destroy(); controller.destroy() }

    function test_waitsForActualCleanup() {
        controller.finished()
        controller.finished()
        compare(policyCalls, 1)
        wait(30)
        compare(nextCalls, 0)
        compare(completions, 0)
        controller.ready()
        tryCompare(this, "retries", 1)
        compare(nextCalls, 1)
        compare(controller.cleanupReady, false)
        controller.finished()
        compare(policyCalls, 2)
        wait(30)
        compare(nextCalls, 1)
    }
    function test_cancelBeforeCleanup() {
        controller.finished()
        controller.cancel()
        compare(cancelCalls, 1)
        compare(completions, 0)
        controller.ready()
        compare(completions, 1)
        wait(30)
        compare(nextCalls, 0)
    }
    function test_cancelDuringDelay() {
        delay = 100
        controller.finished()
        controller.ready()
        controller.cancel()
        compare(completions, 1)
        compare(controller.session, null)
        wait(150)
        compare(nextCalls, 0)
    }
    function test_noRetryOnNormalExitOrExhaustion() {
        delay = -1
        controller.finished()
        compare(completions, 0)
        controller.ready()
        compare(completions, 1)
        compare(nextCalls, 0)
        compare(controller.session, null)
    }
    function test_navigationCancel_data() {
        return [{ tag: "Escape", key: Qt.Key_Escape },
                { tag: "Back", key: Qt.Key_Back }]
    }
    function test_navigationCancel(data) {
        controller.finished()
        navigation.forceActiveFocus()
        verify(navigation.activeFocus)
        keyClick(data.key)
        compare(controller.cancelled, true)
        compare(navigations, 0)
        compare(cancelCalls, 1)
        compare(completions, 0) // The view must not pop before deferred cleanup.
        controller.ready()
        compare(completions, 1)
        wait(30)
        compare(nextCalls, 0)
    }
    function test_navigationCancelDuringDelay() {
        delay = 100
        controller.finished()
        controller.ready()
        navigation.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(completions, 1)
        keyClick(Qt.Key_Escape)
        controller.ready() // Late/repeated notifications cannot finish twice.
        compare(completions, 1)
        wait(150)
        compare(nextCalls, 0)
    }
    function test_settingsNavigationBlocked() {
        controller.finished()
        navigation.forceActiveFocus()
        keyClick(Qt.Key_Menu)
        keyClick(Qt.Key_Hangup)
        compare(controller.cancelled, false)
        compare(navigations, 0)
        compare(completions, 0)
        compare(cancelCalls, 0)
    }
    function test_nextSessionRefused() {
        allowNext = false
        controller.finished()
        controller.ready()
        tryCompare(this, "completions", 1)
        compare(retries, 0)
        compare(controller.session, null)
    }

    // In-window reconnect (macOS): StreamSegue keeps its Qt window hidden with
    // window.visible = !streamWindowParked() while the stream window is kept.
    function test_parkedWindowKeepsQtWindowHidden() {
        parked = true
        compare(controller.streamWindowParked(), false) // not recovering yet
        controller.finished()
        compare(controller.recovering, true)
        compare(controller.streamWindowParked(), true)
        controller.ready()
        tryCompare(this, "retries", 1)
        compare(releaseCalls, 0) // the next session adopts the window
    }
    function test_notParkedShowsQtWindow() {
        controller.finished()
        compare(controller.recovering, true)
        compare(controller.streamWindowParked(), false)
        controller.ready()
        tryCompare(this, "retries", 1)
        compare(releaseCalls, 0)
    }
    function test_finalEndNeverParks() {
        parked = true
        delay = -1
        controller.finished()
        compare(controller.streamWindowParked(), false)
        controller.ready()
        compare(completions, 1)
        compare(releaseCalls, 1)
        compare(controller.streamWindowParked(), false)
    }
    function test_cancelReleasesParkedWindow() {
        parked = true
        controller.finished()
        controller.cancel()
        compare(releaseCalls, 0) // old session cleanup still running
        controller.ready()
        compare(completions, 1)
        compare(releaseCalls, 1)
    }
    function test_cancelDuringDelayReleasesParkedWindow() {
        parked = true
        delay = 100
        controller.finished()
        controller.ready()
        controller.cancel()
        compare(completions, 1)
        compare(releaseCalls, 1)
        controller.cancel()
        controller.ready()
        compare(releaseCalls, 1)
        wait(150)
        compare(nextCalls, 0)
    }
    function test_refusedNextSessionReleasesParkedWindow() {
        parked = true
        allowNext = false
        controller.finished()
        controller.ready()
        tryCompare(this, "completions", 1)
        compare(releaseCalls, 1)
    }
}
