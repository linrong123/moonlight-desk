import QtQuick 2.0

// Owns only recovery sequencing. Session owns retry policy and its shared budget.
Item {
    id: recovery
    property var session: null
    property bool recovering: false
    property bool cancelled: false
    property bool cleanupReady: false
    property bool finishedSeen: false
    property bool completedSeen: false
    property int retryDelay: -1
    signal retryReady(var nextSession)
    signal completed()

    function finished() {
        if (finishedSeen || completedSeen)
            return
        finishedSeen = true
        retryDelay = cancelled ? -1 : session.officeRetryDelay()
        recovering = retryDelay >= 0
    }

    function ready() {
        if (completedSeen)
            return
        cleanupReady = true
        if (retryDelay >= 0 && !cancelled) {
            retryTimer.interval = retryDelay
            retryTimer.start()
        } else {
            complete()
        }
    }

    function complete() {
        if (completedSeen)
            return
        completedSeen = true
        retryTimer.stop()
        recovering = false
        session = null
        completed()
    }

    function cancel() {
        if (completedSeen || cancelled)
            return
        cancelled = true
        retryDelay = -1
        retryTimer.stop()
        if (session)
            session.officeCancelRecovery()
        if (cleanupReady)
            complete()
    }

    // StreamSegue forwards these before its StackView can navigate away.
    // Cancellation keeps both owners alive until ready() confirms cleanup.
    Keys.onEscapePressed: function(event) { cancel(); event.accepted = true }
    Keys.onBackPressed: function(event) { cancel(); event.accepted = true }
    Keys.onMenuPressed: function(event) { event.accepted = true }
    Keys.onHangupPressed: function(event) { event.accepted = true }

    Timer {
        id: retryTimer
        onTriggered: {
            // ready() is the sole entry to this timer: never overlap SDL sessions.
            var nextSession = recovery.session.officeNextSession()
            if (!nextSession) {
                recovery.complete()
                return
            }
            recovery.session = nextSession
            recovery.cleanupReady = false
            recovery.finishedSeen = false
            recovery.retryDelay = -1
            recovery.retryReady(nextSession)
        }
    }
}
