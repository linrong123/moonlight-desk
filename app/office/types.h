#pragma once
namespace office {
// Statistics carries first = 1 when the panel was opened and 0 when it was closed.
enum class Action { Mouse, Resolution, Fullscreen, Statistics, Disconnect, Devices, DisplayScale, InputPause };
enum class MouseMode { Local = 0, Remote = 1, Relative = 2 };
// A failed or pending host request must not leave the user without a cursor.
inline MouseMode effectiveMouseMode(MouseMode requested, bool supported, int status) {
    if (!supported) return requested == MouseMode::Relative ? requested : MouseMode::Remote;
    return status == 1 ? requested : MouseMode::Local;
}
}
