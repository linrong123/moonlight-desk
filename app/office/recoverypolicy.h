#pragma once

#include <algorithm>
#include <cstdint>

namespace office {

// A bounded recovery episode. All calls run on the UI thread. Callers provide
// monotonic milliseconds so the policy can be tested without clocks or sockets.
class RecoveryPolicy {
public:
    void connected(std::int64_t now) { connectedAt = now; }
    void cancel() { cancelled = true; }
    bool isRecovering() const { return attempts != 0; }
    // Attempts used in the current episode; the reconnect overlay shows it.
    int attempt() const { return attempts; }

    int nextDelay(std::int64_t now, bool eligible) {
        if (cancelled || !eligible) return -1;
        if (connectedAt >= 0 && now - connectedAt >= 30000) {
            attempts = 0;
            startedAt = -1;
        }
        connectedAt = -1;
        if (startedAt < 0) startedAt = now;
        if (attempts >= 10 || now - startedAt >= 60000) return -1;
        const int delay = std::min(1000 << std::min(attempts, 3), 5000);
        if (now - startedAt + delay > 60000) return -1;
        ++attempts;
        return delay;
    }

private:
    int attempts = 0;
    bool cancelled = false;
    std::int64_t startedAt = -1;
    std::int64_t connectedAt = -1;
};

inline bool validResolution(int width, int height) {
    return (width == 1280 && height == 720) ||
           (width == 1920 && (height == 1080 || height == 1200)) ||
           (width == 2560 && (height == 1440 || height == 1600)) ||
           (width == 3840 && height == 2160);
}

inline bool retryableHostStatus(bool previouslyConnected, int status) {
    // Sunshine can be reachable before capture or its Desktop app is ready
    // after a console-session transition. Pairing and request errors are final.
    return previouslyConnected && status == 503;
}
}
