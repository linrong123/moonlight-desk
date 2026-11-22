#include "office/cursorretry.h"
#include <cassert>
#include <iostream>

int main() {
    using office::cursorRetryDelay;
    // Transport failures back off and stop after the attempt budget.
    assert(cursorRetryDelay(1, true, false) == 500);
    assert(cursorRetryDelay(2, true, false) == 1000);
    assert(cursorRetryDelay(3, true, false) == 2000);
    assert(cursorRetryDelay(4, true, false) == -1);
    // Host replies (including authentication errors) are final.
    assert(cursorRetryDelay(1, false, false) == -1);
    // A newer request (mode change, session cleanup) wins at once.
    assert(cursorRetryDelay(1, true, true) == -1);
    // Cleanup requests run once so teardown is not delayed.
    assert(cursorRetryDelay(1, true, false, 1) == -1);
    assert(cursorRetryDelay(0, true, false) == -1);
    // Worst case stays well inside one reconnect episode.
    int total = office::kCursorAttemptTimeoutMs * office::kCursorMaxAttempts;
    for (int failed = 1; cursorRetryDelay(failed, true, false) > 0; ++failed) total += cursorRetryDelay(failed, true, false);
    assert(total == 15500);
    // serverinfo at launch: 3 attempts, worst case 16.5 s.
    assert(cursorRetryDelay(2, true, false, office::kServerInfoMaxAttempts) == 1000);
    assert(cursorRetryDelay(3, true, false, office::kServerInfoMaxAttempts) == -1);
    total = office::kServerInfoAttemptTimeoutMs * office::kServerInfoMaxAttempts;
    for (int failed = 1; cursorRetryDelay(failed, true, false, office::kServerInfoMaxAttempts) > 0; ++failed)
        total += cursorRetryDelay(failed, true, false, office::kServerInfoMaxAttempts);
    assert(total == 16500);
    std::cout << "cursor retry tests passed\n";
}
