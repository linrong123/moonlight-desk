#include "../../app/office/recoverypolicy.h"
#include <cassert>
#include <iostream>

int main() {
    using office::RecoveryPolicy;
    RecoveryPolicy fresh;
    assert(fresh.nextDelay(0, false) == -1); // failed local initialization
    fresh.connected(1000);
    assert(fresh.nextDelay(1200, true) == 1000); // unlock interruption
    assert(fresh.nextDelay(2200, true) == 2000);
    fresh.cancel();
    assert(fresh.nextDelay(4200, true) == -1);
    RecoveryPolicy timeout;
    assert(timeout.nextDelay(0, true) == 1000);
    assert(timeout.nextDelay(60000, true) == -1);
    RecoveryPolicy flapping;
    for (int i = 0; i < 10; ++i) {
        flapping.connected(i * 1000);
        assert(flapping.nextDelay(i * 1000 + 100, true) >= 0);
    }
    assert(flapping.nextDelay(11000, true) == -1); // rapid connect/drop can't reset budget
    RecoveryPolicy healthy;
    assert(healthy.nextDelay(0, true) == 1000);
    healthy.connected(1000);
    assert(healthy.nextDelay(32000, true) == 1000); // healthy session starts a new episode
    assert(office::validResolution(1920, 1080));
    assert(office::validResolution(3840, 2160));
    assert(!office::validResolution(0, 1080));
    assert(!office::validResolution(1920, -1));
    std::cout << "Recovery policy: cancellation, deadline, flapping, healthy reset and resolutions passed\n";
}
