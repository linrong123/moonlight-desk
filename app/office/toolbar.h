#pragma once
#include "types.h"
#include "SDL_compat.h"
#include <functional>
#include <memory>

namespace office {
class Toolbar {
public:
    virtual ~Toolbar() = default;
    virtual void setStatus(const char* text) = 0;
};
std::unique_ptr<Toolbar> createToolbar(SDL_Window* window, int width, int height,
    MouseMode mode, std::function<void(Action, int, int)> action, bool hasDeviceManager = false);
}
