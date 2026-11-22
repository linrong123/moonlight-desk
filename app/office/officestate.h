#pragma once

#include "recoverypolicy.h"
#include "types.h"
#include "displayscale.h"
#include "clipboardsync.h"
#include "backend/nvhttp.h"
#include "settings/streamingpreferences.h"
#include <QThreadPool>
#include <atomic>
#include <deque>
#include <memory>
#include <mutex>

namespace office {
constexpr int ConnectionLostEvent = 0x6f660001;
class Toolbar;
class ParkedWindow;

struct State {
    explicit State(const QString& hostId);
    ~State();
    QString settingsGroup;
    RecoveryPolicy recovery;
    std::atomic_bool retryable{false};
    std::atomic_bool hostEnded{false};
    std::atomic_bool userStopped{false};
    std::atomic_bool cursorSupported{false};
    std::atomic_int cursorStatus{0}; // 0=idle, 1=success, -1=unsupported, -2=failure
    std::atomic_uint cursorGeneration{0};
    std::mutex cursorResultMutex;
    bool reconfigure = false;
    bool everConnected = false;
    int currentApp = 0;
    NvAddress peerAddress;
    uint16_t peerPort = 0;
    QSslCertificate peerCertificate;
    bool trueUid = true;
    MouseMode mouseMode = MouseMode::Local;
    // UI thread only: statistics panel stays open across reconnects.
    bool statisticsPanel = false;
    QThreadPool cursorQueue;
    std::atomic_bool displayScaleSupported{false};
    // CONNECTION.md §2: host asks its user before every launch/resume.
    std::atomic_bool connectConfirm{false};
    QThreadPool displayScaleQueue;
    struct DisplayScaleSnapshot {
        DisplayScaleResult value;
        bool pending = false;
        QString message;
    };
    std::mutex displayScaleMutex;
    unsigned displayScaleGeneration = 0;
    DisplayScaleSnapshot displayScale;
    // Text clipboard sync (office/CLIPBOARD.md). HTTP runs on clipboardQueue
    // (one thread, so a push and a later pull stay ordered); decisions and
    // pasteboard access stay on the UI thread.
    std::atomic_bool clipboardSupported{false};
    bool clipboardEnabled = true;   // per device, UI thread
    bool clipboardStarted = false;  // UI thread: officeStartUi ran for this connection
    bool clipboardFocused = false;  // UI thread: last seen remote window focus
    ClipboardSync clipboard;        // UI thread
    enum class ClipboardRequest { Baseline, Push, Pull };
    struct ClipboardResult {
        ClipboardRequest kind;
        long changeCount;
        ClipboardReply reply;
    };
    QThreadPool clipboardQueue;
    std::mutex clipboardMutex;
    unsigned clipboardGeneration = 0;
    std::deque<ClipboardResult> clipboardResults;
    // UI thread only: the stream window kept between two sessions during
    // automatic recovery (parkedwindow.h, macOS). Null otherwise.
    std::unique_ptr<ParkedWindow> parked;

    void load(StreamingPreferences* prefs);
    void saveResolution(int width, int height);
    void saveMouse(MouseMode mode);
    void saveClipboard(bool enabled);
    // False when the user stopped the connection while a retry was pending.
    bool prepareConnection(NvHTTP& http);
    void queueDisplayScale(int percent = 0);
    DisplayScaleSnapshot displayScaleSnapshot();
    // Transport failures are retried with backoff unless retry is false
    // (session cleanup must not be delayed).
    void queueCursor(const NvAddress& address, uint16_t port,
                     const QSslCertificate& cert, bool trueUid, bool visible, bool retry = true);

    // Clipboard hooks, UI thread only (clipboardhooks.cpp).
    void clipboardStart(Toolbar* toolbar, bool focused);
    void clipboardPoll(Toolbar* toolbar, bool focused);
    void clipboardToggle(Toolbar* toolbar, bool enabled, bool focused);
    // finalPull: active disconnect; reads the host clipboard once, bounded.
    void clipboardStop(bool finalPull);

private:
    void queueClipboard(ClipboardRequest kind, std::string text, long changeCount, int timeoutMs);
    void applyClipboardResults(Toolbar* toolbar);
    void clipboardPush();
    void clipboardPull(int timeoutMs);
    void showClipboard(Toolbar* toolbar);
};

std::int64_t monotonicMs();
bool retryableTermination(int code);
bool retryableNetworkError(QNetworkReply::NetworkError code);
}
