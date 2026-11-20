#include "streaming/session.h"
#include "connectconfirm.h"
#include "sessionbridge.h"
#include "videostats.h"

#include <QThread>

bool Session::officeEnabled() const { return bool(m_Office); }

int Session::officeRetryDelay() {
    if (!m_Office) return -1;
    if (m_Office->userStopped) m_Office->recovery.cancel();
    const int delay = m_Office->recovery.nextDelay(office::monotonicMs(),
        m_Office->reconfigure || m_Office->retryable.load());
    if (delay >= 0 && office::SessionBridge::instance())
        office::SessionBridge::instance()->report("recovering");
    return delay;
}

Session* Session::officeNextSession() {
    if (!m_Office || m_Office->userStopped) return nullptr;
    auto next = new Session(m_Computer, m_App, m_Preferences);
    next->m_Office = m_Office;
    next->m_Office->reconfigure = false;
    next->m_Office->retryable = false;
    next->m_Office->hostEnded = false;
    return next;
}

void Session::officeCancelRecovery() {
    if (m_Office) {
        m_Office->userStopped = true;
        m_Office->recovery.cancel();
    }
    if (s_ActiveSession == this) interrupt();
}

// Called on the async connection thread before launch/resume (CONNECTION.md §2).
bool Session::officeAwaitApproval(NvHTTP& http) {
    auto* bridge = office::SessionBridge::instance();
    bool waiting = false;
    office::ApprovalHooks hooks;
    hooks.request = [&http](const QString& action) { return http.requestOfficeConnect(action); };
    hooks.cancelled = [this] { return m_Office->userStopped.load(); };
    hooks.waiting = [this, bridge, &waiting] {
        waiting = true;
        if (bridge) bridge->report("approval");
        emit officeApprovalWaiting(true);
    };
    hooks.now = [] { return office::monotonicMs(); };
    hooks.sleep = [](int ms) { QThread::msleep(ms); };

    const auto finishWaiting = [this, &waiting] {
        if (waiting) emit officeApprovalWaiting(false);
        waiting = false;
    };
    office::ApprovalOutcome outcome;
    try {
        outcome = office::waitForHostApproval(hooks);
    } catch (...) {
        finishWaiting();
        throw;
    }
    // Capture before finishWaiting() clears the flag: the workbench must leave
    // the approval text once the host approved.
    const bool waited = waiting;
    finishWaiting();

    const QString state = office::approvalBridgeState(outcome, waited);
    if (bridge && !state.isEmpty()) bridge->report(state);
    if (outcome == office::ApprovalOutcome::Proceed) return true;
    if (outcome == office::ApprovalOutcome::Cancelled) return false;
    // Host decisions are final: retryable=false ends the recovery chain in
    // officeRetryDelay() (RecoveryPolicy itself is UI-thread only).
    m_Office->retryable = false;
    emit displayLaunchError(office::approvalOutcomeMessage(outcome));
    return false;
}

bool Session::officeApprovalRejected(const GfeHttpResponseException& error) {
    if (!office::isHostApprovalRequired(error.getStatusCode(),
                                        QString::fromUtf8(error.getStatusMessage()))) return false;
    m_Office->retryable = false;
    // The host opens a confirmation dialog on its own after this 403. The
    // client gives up on this attempt, so withdraw that dialog (best effort).
    NvHTTP http(m_Computer);
    office::withdrawApprovalRequest([&http](const QString& action) {
        return http.requestOfficeConnect(action);
    });
    constexpr auto outcome = office::ApprovalOutcome::ApprovalRequired;
    if (auto* bridge = office::SessionBridge::instance())
        bridge->report(office::approvalBridgeState(outcome, false));
    emit displayLaunchError(office::approvalOutcomeMessage(outcome));
    return true;
}

void SdlInputHandler::setOfficeMouseMode(bool absolute, bool localCursor) {
    raiseAllKeys();
    setCaptureActive(false);
    m_AbsoluteMouseMode = absolute;
    m_MouseCursorCapturedVisibilityState = localCursor ? SDL_ENABLE : SDL_DISABLE;
    setCaptureActive(true);
}

void SdlInputHandler::releaseOfficeInput() {
    raiseAllKeys();
    // A button-up delivered to the local sheet must not leave a remote drag held.
    unsigned buttons = m_OfficeMouseButtonsDown;
    m_OfficeMouseButtonsDown = 0;
    if (m_DragButton) buttons |= 1u << m_DragButton;
    if (m_LeftButtonReleaseTimer || m_LongPressTimer) buttons |= 1u << BUTTON_LEFT;
    if (m_RightButtonReleaseTimer || m_LongPressTimer) buttons |= 1u << BUTTON_RIGHT;
    for (const auto timer : {m_LongPressTimer, m_DragTimer,
                            m_LeftButtonReleaseTimer, m_RightButtonReleaseTimer}) SDL_RemoveTimer(timer);
    m_LongPressTimer = m_DragTimer = m_LeftButtonReleaseTimer = m_RightButtonReleaseTimer = 0;
    m_DragButton = 0;
    m_NumFingersDown = 0;
    for (auto& touch : m_TouchDownEvent) touch = {};
    for (int button : {BUTTON_LEFT, BUTTON_MIDDLE, BUTTON_RIGHT, BUTTON_X1, BUTTON_X2})
        if (buttons & (1u << button)) LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, button);
    if (LiGetHostFeatureFlags() & LI_FF_PEN_TOUCH_EVENTS)
        LiSendTouchEvent(LI_TOUCH_EVENT_CANCEL_ALL, 0, 0, 0, 0, 0, 0, 0);
    m_PendingMouseButtonsAllUpOnVideoRegionLeave = false;
    SDL_CaptureMouse(SDL_FALSE);
    setCaptureActive(false);
}

void Session::officeStartUi() {
    if (office::SessionBridge::instance()) office::SessionBridge::instance()->report("connected");
    if (!m_Office) return;
    m_Office->everConnected = true;
    m_Office->recovery.connected(office::monotonicMs());
    // Never show a sample from the previous connection.
    office::videoStatsChannel().clear();
    m_OfficeToolbar = office::createToolbar(m_Window, m_StreamConfig.width, m_StreamConfig.height,
        m_Office->mouseMode, [this](office::Action action, int first, int second) {
            officeAction(action, first, second);
        }, office::SessionBridge::isSessionProcess());
    // The statistics panel stays open across reconnects of this session.
    if (m_OfficeToolbar && m_Office->statisticsPanel) m_OfficeToolbar->setStatisticsVisible(true);
    // Sunshine may change the active display during launch/resume. Read DPI
    // only after the stream has started, not from the previous desktop layout.
    m_Office->queueDisplayScale();
    officePollUi();
}

void Session::officeStopUi() {
    m_OfficeRestoreCapture = false;
    m_OfficeToolbar.reset();
    office::videoStatsChannel().clear();
}

void Session::officePollUi() {
    if (!m_InputHandler) return;
    if (auto* bridge = office::SessionBridge::instance()) {
        if (bridge->stopRequested()) {
            if (!m_Office) interrupt();
            else if (!m_Office->userStopped) officeCancelRecovery();
        }
        if (bridge->takeFocus() && m_Window) {
            SDL_RestoreWindow(m_Window);
            SDL_RaiseWindow(m_Window);
        }
    }
    if (!m_Office) return;
    const bool mayCapture = !m_OfficeInputPaused && !m_Office->userStopped &&
        !m_Office->reconfigure && SDL_GetKeyboardFocus() == m_Window;
    if (mayCapture && m_OfficeRestoreCapture) {
        // AppKit may deliver the parent focus event after the sheet completion.
        m_OfficeRestoreCapture = false;
        m_InputHandler->setCaptureActive(true);
    }
    const auto effective = office::effectiveMouseMode(m_Office->mouseMode,
        m_Office->cursorSupported, m_Office->cursorStatus);
    if (mayCapture && m_OfficeAppliedInput != static_cast<int>(effective)) {
        m_InputHandler->setOfficeMouseMode(effective != office::MouseMode::Relative,
            effective == office::MouseMode::Local);
        m_OfficeAppliedInput = static_cast<int>(effective);
    }
    if (!m_OfficeToolbar) return;
    office::VideoStatsSample stats;
    if (office::videoStatsChannel().take(stats)) {
        m_OfficeToolbar->setStatistics(office::videoStatsSummary(stats).c_str(),
            office::videoStatsDetails(stats).c_str());
    }
    const auto scale = m_Office->displayScaleSnapshot();
    m_OfficeToolbar->setDisplayScales(scale.value.supported, scale.value.current, scale.pending);
    QString status;
    switch (m_Office->cursorStatus.load()) {
    case -1: status = QStringLiteral("旧版主机：使用远端光标"); break;
    case -2:
        // The host may have applied the request before its response was lost.
        // Preserve the visible local pointer instead of risking no cursor.
        status = QStringLiteral("远端光标同步失败；暂用本地光标");
        break;
    case 1: break;
    default: status = QStringLiteral("正在同步光标设置…"); break;
    }
    if (!status.isEmpty() && !scale.message.isEmpty()) status += QStringLiteral(" · ");
    status += scale.message;
    m_OfficeToolbar->setStatus(status.toUtf8().constData());
}

void Session::officeAction(office::Action action, int first, int second) {
    if (!m_Office || !m_InputHandler) return;
    switch (action) {
    case office::Action::InputPause:
        if (first && !m_OfficeInputPaused) {
            m_OfficeRestoreCapture = m_InputHandler->isCaptureActive();
            m_OfficeInputPaused = true;
            m_InputHandler->releaseOfficeInput();
        } else if (!first && m_OfficeInputPaused) {
            // Discard queued events from the local sheet before resuming.
            SDL_FlushEvents(SDL_KEYDOWN, SDL_KEYMAPCHANGED);
            SDL_FlushEvents(SDL_MOUSEMOTION, SDL_MOUSEWHEEL);
            SDL_FlushEvents(SDL_FINGERDOWN, SDL_FINGERMOTION);
            m_OfficeInputPaused = false;
            officePollUi();
        }
        break;
    case office::Action::DisplayScale:
        m_Office->queueDisplayScale(first);
        officePollUi();
        break;
    case office::Action::Devices:
        if (auto* bridge = office::SessionBridge::instance()) bridge->showManager();
        break;
    case office::Action::Mouse: {
        if (first < 0 || first > 2) return;
        const auto mode = static_cast<office::MouseMode>(first);
        m_Office->saveMouse(mode);
        m_Preferences->absoluteMouseMode = mode != office::MouseMode::Relative;
        m_Office->cursorStatus = m_Office->cursorSupported ? 0 : -1;
        m_Office->queueCursor(m_Office->peerAddress, m_Office->peerPort,
            m_Office->peerCertificate, m_Office->trueUid, mode != office::MouseMode::Local);
        officePollUi();
        break;
    }
    case office::Action::Resolution:
        if (!office::validResolution(first, second)) return;
        if (first == m_StreamConfig.width && second == m_StreamConfig.height) return;
        m_Office->saveResolution(first, second);
        m_Preferences->width = first;
        m_Preferences->height = second;
        m_Office->reconfigure = true;
        interrupt();
        break;
    case office::Action::Fullscreen:
        m_InputHandler->raiseAllKeys();
        toggleFullscreen();
        break;
    case office::Action::Statistics:
        // The toolbar shows the panel itself; the video overlay stays untouched
        // (upstream Ctrl+Alt+Shift+S still toggles it).
        m_Office->statisticsPanel = first != 0;
        break;
    case office::Action::Disconnect:
        officeCancelRecovery();
        break;
    }
}
