#include "toolbar.h"
namespace office {
std::unique_ptr<Toolbar> createToolbar(SDL_Window*, int, int, MouseMode,
                                      std::function<void(Action, int, int)>) {
    return {};
}
}
