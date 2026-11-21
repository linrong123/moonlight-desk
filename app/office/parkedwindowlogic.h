#pragma once

// Decisions for keeping the stream window through automatic recovery
// (office/CONNECTION.md, in-window reconnect). Header-only and free of Qt/SDL
// so it can be unit tested on its own.

#include <cstdint>
#include <string>

namespace office {

// Only recoverable ends keep the window: a network loss the policy may retry,
// or a resolution change. Active disconnects and final errors close it.
inline bool shouldParkWindow(bool supported, bool retryable, bool reconfigure, bool userStopped) {
    return supported && (retryable || reconfigure) && !userStopped;
}

// Overlay text. Waiting for the host's approval wins over the reason for the
// reconnect; attempt is RecoveryPolicy::attempt() (0 before the first retry).
inline std::string recoveryOverlayText(bool reconfigure, int attempt, bool approvalWaiting) {
    if (approvalWaiting) return "正在等待被控端确认…";
    if (reconfigure) return "正在切换分辨率…";
    if (attempt <= 0) return "网络中断，正在重新连接…";
    return "网络中断，正在重新连接…（第 " + std::to_string(attempt) + " 次）";
}

// A kept window follows a new resolution only in plain windowed mode; a
// network retry keeps whatever size the user left.
inline bool resizeAdoptedWindow(bool reconfigure, bool fullscreen, bool maximized) {
    return reconfigure && !fullscreen && !maximized;
}

// SDL event types seen while no session loop runs. Values mirror SDL2
// (SDL_events.h); parkedwindow_mac.mm static_asserts that they match.
constexpr std::uint32_t kParkedQuitEvent = 0x100;          // SDL_QUIT
constexpr std::uint32_t kParkedWindowEvent = 0x200;        // SDL_WINDOWEVENT
constexpr std::uint8_t kParkedWindowClose = 14;            // SDL_WINDOWEVENT_CLOSE
constexpr std::uint32_t kParkedInputRanges[][2] = {
    {0x300, 0x3FF},  // keyboard
    {0x400, 0x4FF},  // mouse
    {0x700, 0x7FF},  // touch
};
constexpr std::uint32_t kParkedUserEvent = 0x8000;         // SDL_USEREVENT

enum class ParkedEvent { Cancel, Discard };

// For events taken from the queue while parked. Closing the kept window or
// quitting cancels recovery; local input and other window events of the old
// window are dropped. User events are never taken (see parkedwindow_mac.mm).
inline ParkedEvent classifyParkedEvent(std::uint32_t type, std::uint8_t windowEvent,
                                       std::uint32_t eventWindow, std::uint32_t parkedWindow) {
    if (type == kParkedQuitEvent) return ParkedEvent::Cancel;
    if (type == kParkedWindowEvent && windowEvent == kParkedWindowClose && eventWindow == parkedWindow)
        return ParkedEvent::Cancel;
    return ParkedEvent::Discard;
}

// True for the type ranges the parked pump takes from the SDL queue.
inline bool parkedPumpTakes(std::uint32_t type) {
    if (type == kParkedQuitEvent || type == kParkedWindowEvent) return true;
    for (const auto& range : kParkedInputRanges)
        if (type >= range[0] && type <= range[1]) return true;
    return false;
}
}
