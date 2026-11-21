#include "../../app/office/parkedwindowlogic.h"

#include <cassert>
#include <iostream>

using office::ParkedEvent;

int main() {
    // Only recoverable ends keep the window, and only where supported.
    assert(office::shouldParkWindow(true, true, false, false));
    assert(office::shouldParkWindow(true, false, true, false));
    assert(!office::shouldParkWindow(true, false, false, false));
    assert(!office::shouldParkWindow(true, true, false, true));
    assert(!office::shouldParkWindow(true, false, true, true));
    assert(!office::shouldParkWindow(false, true, true, false));

    assert(office::recoveryOverlayText(false, 0, false) == "网络中断，正在重新连接…");
    assert(office::recoveryOverlayText(false, 1, false) == "网络中断，正在重新连接…（第 1 次）");
    assert(office::recoveryOverlayText(false, 12, false) == "网络中断，正在重新连接…（第 12 次）");
    assert(office::recoveryOverlayText(true, 3, false) == "正在切换分辨率…");
    assert(office::recoveryOverlayText(false, 2, true) == "正在等待被控端确认…");
    assert(office::recoveryOverlayText(true, 0, true) == "正在等待被控端确认…");

    assert(office::resizeAdoptedWindow(true, false, false));
    assert(!office::resizeAdoptedWindow(false, false, false));
    assert(!office::resizeAdoptedWindow(true, true, false));
    assert(!office::resizeAdoptedWindow(true, false, true));

    const std::uint32_t parked = 7;
    assert(office::classifyParkedEvent(office::kParkedQuitEvent, 0, 0, parked) == ParkedEvent::Cancel);
    assert(office::classifyParkedEvent(office::kParkedWindowEvent, office::kParkedWindowClose, parked, parked)
           == ParkedEvent::Cancel);
    assert(office::classifyParkedEvent(office::kParkedWindowEvent, office::kParkedWindowClose, 8, parked)
           == ParkedEvent::Discard);
    assert(office::classifyParkedEvent(office::kParkedWindowEvent, 5, parked, parked) == ParkedEvent::Discard);
    assert(office::classifyParkedEvent(0x300, 0, parked, parked) == ParkedEvent::Discard);
    assert(office::classifyParkedEvent(0x401, 0, parked, parked) == ParkedEvent::Discard);

    assert(office::parkedPumpTakes(office::kParkedQuitEvent));
    assert(office::parkedPumpTakes(office::kParkedWindowEvent));
    assert(office::parkedPumpTakes(0x300));
    assert(office::parkedPumpTakes(0x3FF));
    assert(office::parkedPumpTakes(0x403));
    assert(office::parkedPumpTakes(0x700));
    // Stale session user events (connection lost, render reset) stay queued.
    assert(!office::parkedPumpTakes(office::kParkedUserEvent));
    assert(!office::parkedPumpTakes(office::kParkedUserEvent + 1));
    assert(!office::parkedPumpTakes(0x2000));  // SDL_RENDER_TARGETS_RESET
    assert(!office::parkedPumpTakes(0x1000));  // drop events
    assert(!office::parkedPumpTakes(0x600));   // controller

    std::cout << "parked window logic: ok\n";
    return 0;
}
