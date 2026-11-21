#include "../../app/office/scrollspeed.h"
#include <cassert>
#include <iostream>

int main() {
    using office::ScrollScaler;
    using office::scrollDeltaPerNotch;

    // The three presets map to 40 / 80 / 120 per wheel notch.
    assert(scrollDeltaPerNotch(office::kScrollSpeedSlow) == 40);
    assert(scrollDeltaPerNotch(office::kScrollSpeedMedium) == 80);
    assert(scrollDeltaPerNotch(office::kScrollSpeedStandard) == 120);
    // Out-of-range percentages are clamped to [10, 100].
    assert(scrollDeltaPerNotch(0) == 12);
    assert(scrollDeltaPerNotch(-50) == 12);
    assert(scrollDeltaPerNotch(1000) == 120);

    ScrollScaler slow(office::kScrollSpeedSlow);
    assert(slow.scale(1.0f) == 40);
    assert(slow.scale(-1.0f) == -40);
    ScrollScaler medium(office::kScrollSpeedMedium);
    assert(medium.scale(1.0f) == 80);
    assert(medium.scale(-1.0f) == -80);

    // 100% with whole notches matches the original (short)(notches * 120).
    ScrollScaler standard;
    assert(standard.scale(1.0f) == 120);
    assert(standard.scale(-1.0f) == -120);
    assert(standard.scale(2.0f) == 240);

    // Zero never sends and never touches the carried remainder.
    ScrollScaler zero(office::kScrollSpeedMedium);
    assert(zero.scale(0.0f) == 0);
    assert(zero.scale(0.015625f) == 1); // 1.25 -> 1, remainder 0.25
    assert(zero.scale(0.0f) == 0);
    assert(zero.scale(0.015625f) == 1); // 1.5 -> 1, remainder 0.5

    // Fractional notches (trackpads) accumulate instead of being lost.
    ScrollScaler fraction(office::kScrollSpeedMedium);
    int total = 0;
    for (int i = 0; i < 13; ++i) {
        total += fraction.scale(0.1f); // 8 per event at 80 per notch
    }
    assert(total == 104);
    ScrollScaler carry(office::kScrollSpeedMedium);
    int sum = 0;
    for (int i = 0; i < 4; ++i) {
        sum += carry.scale(0.015625f); // 1.25 each: 1, 1, 1, 2
    }
    assert(sum == 5);

    // Reversing direction drops the remainder of the previous direction.
    ScrollScaler reverse(office::kScrollSpeedMedium);
    for (int i = 0; i < 3; ++i) {
        reverse.scale(0.015625f); // remainder 0.75
    }
    assert(reverse.scale(-0.015625f) == -1); // -1.25, not -0.5
    ScrollScaler resetting(office::kScrollSpeedMedium);
    assert(resetting.scale(0.015625f) == 1);
    resetting.reset();
    assert(resetting.scale(0.015625f) == 1); // fresh 1.25, not 1.5

    // Out-of-range construction behaves like the clamped percentage.
    ScrollScaler tooLow(0);
    assert(tooLow.scale(1.0f) == 12);
    ScrollScaler tooHigh(500);
    assert(tooHigh.scale(1.0f) == 120);

    // Large values saturate at the short range instead of overflowing.
    ScrollScaler big;
    assert(big.scale(1000.0f) == 32767);
    assert(big.scale(-1000.0f) == -32768);
    assert(big.scale(1e30f) == 32767);

    std::cout << "Scroll speed: presets, 100% parity, remainder carry, reversal, clamp and saturation passed\n";
}
