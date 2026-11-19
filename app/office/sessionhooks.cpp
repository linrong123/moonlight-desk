#include "streaming/session.h"

bool Session::officeEnabled() const { return bool(m_Office); }

int Session::officeRetryDelay() {
    if (!m_Office) return -1;
    if (m_Office->userStopped) m_Office->recovery.cancel();
    return m_Office->recovery.nextDelay(office::monotonicMs(),
        m_Office->reconfigure || m_Office->retryable.load());
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

void SdlInputHandler::setOfficeMouseMode(bool absolute, bool localCursor) {
    raiseAllKeys();
    setCaptureActive(false);
    m_AbsoluteMouseMode = absolute;
    m_MouseCursorCapturedVisibilityState = localCursor ? SDL_ENABLE : SDL_DISABLE;
    setCaptureActive(true);
}

void Session::officeStartUi() {
    if (!m_Office) return;
    m_Office->everConnected = true;
    m_Office->recovery.connected(office::monotonicMs());
    // Stock Sunshine cannot set cursor state; default to its remote cursor
    // rather than silently producing a double cursor or sending a toggle.
    const bool local = m_Office->mouseMode == office::MouseMode::Local && m_Office->cursorSupported;
    m_InputHandler->setOfficeMouseMode(m_Office->mouseMode != office::MouseMode::Relative, local);
    m_OfficeToolbar = office::createToolbar(m_Window, m_StreamConfig.width, m_StreamConfig.height,
        m_Office->mouseMode, [this](office::Action action, int first, int second) {
            officeAction(action, first, second);
        });
    officePollUi();
}

void Session::officeStopUi() { m_OfficeToolbar.reset(); }

void Session::officePollUi() {
    if (!m_OfficeToolbar || !m_Office) return;
    switch (m_Office->cursorStatus.load()) {
    case -1: m_OfficeToolbar->setStatus("旧版主机：使用远端光标；本地光标需办公版被控端"); break;
    case -2:
        // The host may have applied the request before its response was lost.
        // Preserve the visible local pointer instead of risking no cursor.
        m_OfficeToolbar->setStatus("远端光标同步失败；可重新选择重试");
        break;
    case 1: m_OfficeToolbar->setStatus("鼠标即时生效 · 分辨率应用时会短暂重连"); break;
    default: m_OfficeToolbar->setStatus("正在同步光标设置…"); break;
    }
}

void Session::officeAction(office::Action action, int first, int second) {
    if (!m_Office || !m_InputHandler) return;
    switch (action) {
    case office::Action::Mouse: {
        if (first < 0 || first > 2) return;
        const auto mode = static_cast<office::MouseMode>(first);
        m_Office->saveMouse(mode);
        m_Preferences->absoluteMouseMode = mode != office::MouseMode::Relative;
        const bool local = mode == office::MouseMode::Local && m_Office->cursorSupported;
        m_InputHandler->setOfficeMouseMode(m_Preferences->absoluteMouseMode, local);
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
        m_OverlayManager.setOverlayState(Overlay::OverlayDebug,
            !m_OverlayManager.isOverlayEnabled(Overlay::OverlayDebug));
        break;
    case office::Action::Disconnect:
        officeCancelRecovery();
        break;
    }
}
