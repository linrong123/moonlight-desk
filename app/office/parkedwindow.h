#pragma once

// Keeps the SDL stream window through automatic recovery (macOS only; see
// office/CONNECTION.md, in-window reconnect). While a window is parked no
// Session owns it: the parked object holds the window, the old session's SDL
// video reference, its toolbar and a native reconnect overlay. The next
// session adopts it instead of creating a window. Main thread only.

#include "SDL_compat.h"
#include <functional>
#include <memory>

namespace office {
class Toolbar;

class ParkedWindow {
public:
    struct Adopted {
        SDL_Window* window = nullptr;
        bool reconfigure = false;  // parked for a resolution change
        bool fullscreen = false;   // SDL or native (Spaces) fullscreen
        bool maximized = false;
    };

    // Destroying a window that was not adopted closes it: toolbar, overlay,
    // SDL_DestroyWindow, then SDL_QuitSubSystem(SDL_INIT_VIDEO).
    virtual ~ParkedWindow() = default;
    virtual SDL_Window* window() const = 0;
    // The old session's toolbar stays on the window; only 断开 still acts.
    virtual void setToolbar(std::unique_ptr<Toolbar> toolbar) = 0;
    // Called once, queued on the main thread, for 断开 / Esc / window close.
    virtual void setCancelHandler(std::function<void()> handler) = 0;
    virtual void setRecovery(bool reconfigure, int attempt) = 0;
    virtual void setApprovalWaiting(bool waiting) = 0;
    virtual void focus() = 0;
    // Hands the window and its SDL video reference to the caller and returns
    // the toolbar through toolbar. The object is empty afterwards.
    virtual Adopted adopt(std::unique_ptr<Toolbar>& toolbar) = 0;
};

bool parkingSupported();
// Null when the window cannot be kept; the caller then destroys it as usual.
std::unique_ptr<ParkedWindow> parkWindow(SDL_Window* window, bool reconfigure, int attempt);
}
