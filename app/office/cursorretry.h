#pragma once

namespace office {

// office/cursor decides whether the host stops drawing its own cursor. On a
// lossy long-haul link a single HTTPS request is regularly lost, which used to
// leave both cursors on screen for the whole session. Transport failures are
// retried a bounded number of times; any host reply (error status or a
// mismatched result) is final, so authentication failures never loop.
constexpr int kCursorAttemptTimeoutMs = 3000;
constexpr int kCursorMaxAttempts = 4;

// Delay in ms before the next attempt after `failed` failed attempts, or -1 to
// stop. A newer cursor request supersedes the running one immediately.
inline int cursorRetryDelay(int failed, bool retryable, bool superseded, int maxAttempts = kCursorMaxAttempts) {
    if (superseded || !retryable || failed < 1 || failed >= maxAttempts) return -1;
    return 500 << (failed - 1); // 500, 1000, 2000 ms
}

}
