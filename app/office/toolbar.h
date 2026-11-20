#pragma once
#include "types.h"
#include "SDL_compat.h"
#include <functional>
#include <memory>
#include <vector>

namespace office {
class Toolbar {
public:
    virtual ~Toolbar() = default;
    // Shown at the left of the toolbar; empty falls back to a generic name.
    virtual void setDeviceName(const char* name) = 0;
    // Mirrors the session's input pause (menu check mark) without an Action.
    virtual void setInputPaused(bool paused) = 0;
    // Mirrors the clipboard sync toggle without an Action. Unsupported hosts
    // grey the item out; denied means the host refused this connection.
    virtual void setClipboard(bool supported, bool enabled, bool denied) = 0;
    virtual void setStatus(const char* text) = 0;
    virtual void setDisplayScales(const std::vector<int>& supported, int current, bool pending) = 0;
    // Resident summary in the toolbar; details are the tooltip and panel text.
    virtual void setStatistics(const char* summary, const char* details) = 0;
    // Opens or closes the floating statistics panel without sending an Action.
    virtual void setStatisticsVisible(bool visible) = 0;
};
std::unique_ptr<Toolbar> createToolbar(SDL_Window* window, int width, int height,
    MouseMode mode, std::function<void(Action, int, int)> action, bool hasDeviceManager = false);
}
