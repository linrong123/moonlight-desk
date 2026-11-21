#include "parkedwindow.h"

// Windows/Linux keep the upstream behavior: the window closes on every end.
namespace office {
bool parkingSupported() { return false; }
std::unique_ptr<ParkedWindow> parkWindow(SDL_Window*, bool, int) { return {}; }
}
