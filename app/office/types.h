#pragma once
namespace office {
enum class Action { Mouse, Resolution, Fullscreen, Statistics, Disconnect };
enum class MouseMode { Local = 0, Remote = 1, Relative = 2 };
// A failed or pending host request must not leave the user without a cursor.
inline MouseMode effectiveMouseMode(MouseMode requested, bool supported, int status) {
    if (!supported) return requested == MouseMode::Relative ? requested : MouseMode::Remote;
    return status == 1 ? requested : MouseMode::Local;
}
}
