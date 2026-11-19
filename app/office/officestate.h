#pragma once

#include "recoverypolicy.h"
#include "types.h"
#include "displayscale.h"
#include "backend/nvhttp.h"
#include "settings/streamingpreferences.h"
#include <QThreadPool>
#include <atomic>
#include <memory>
#include <mutex>

namespace office {
constexpr int ConnectionLostEvent = 0x6f660001;

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

    void load(StreamingPreferences* prefs);
    void saveResolution(int width, int height);
    void saveMouse(MouseMode mode);
    void prepareConnection(NvHTTP& http);
    void queueDisplayScale(int percent = 0);
    DisplayScaleSnapshot displayScaleSnapshot();
    void queueCursor(const NvAddress& address, uint16_t port,
                     const QSslCertificate& cert, bool trueUid, bool visible);
};

std::int64_t monotonicMs();
bool retryableTermination(int code);
bool retryableNetworkError(QNetworkReply::NetworkError code);
}
