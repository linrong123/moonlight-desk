#pragma once

// Scroll wheel speed for the office build. Header-only and free of Qt/SDL so it
// can be unit tested on its own.

#include <algorithm>
#include <cmath>
#include <limits>

namespace office {

// Percent of one WHEEL_DELTA (120) sent per wheel notch.
constexpr int kScrollSpeedSlow = 33;     // 40 per notch
constexpr int kScrollSpeedMedium = 67;   // 80 per notch
constexpr int kScrollSpeedStandard = 100; // 120 per notch

inline int scrollDeltaPerNotch(int percent) {
    percent = std::min(100, std::max(10, percent));
    return static_cast<int>(std::lround(120.0 * percent / 100.0));
}

// Converts wheel notches into high-resolution scroll deltas. Fractions that
// cannot be sent yet (e.g. trackpad scrolling) are carried to the next event.
class ScrollScaler {
public:
    explicit ScrollScaler(int percent = kScrollSpeedStandard)
        : m_PerNotch(scrollDeltaPerNotch(percent)), m_Remainder(0.0) {}

    short scale(float notches) {
        if (notches == 0.0f) {
            return 0;
        }
        if ((notches > 0.0f && m_Remainder < 0.0) || (notches < 0.0f && m_Remainder > 0.0)) {
            m_Remainder = 0.0;
        }
        double value = static_cast<double>(notches) * m_PerNotch + m_Remainder;
        double whole = std::trunc(value);
        constexpr double kMax = std::numeric_limits<short>::max();
        constexpr double kMin = std::numeric_limits<short>::min();
        double out = std::min(kMax, std::max(kMin, whole));
        m_Remainder = value - whole;
        return static_cast<short>(out);
    }

    void reset() { m_Remainder = 0.0; }

private:
    int m_PerNotch;
    double m_Remainder;
};

} // namespace office
