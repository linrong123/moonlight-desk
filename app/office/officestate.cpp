#include "officestate.h"
#include <Limelight.h>
#include <QSettings>
#include <QCryptographicHash>
#include <chrono>

namespace office {
std::int64_t monotonicMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

bool retryableTermination(int code) {
    // Protected content and encoder errors require action, not an endless loop.
    return code != ML_ERROR_PROTECTED_CONTENT && code != ML_ERROR_FRAME_CONVERSION;
}

bool retryableNetworkError(QNetworkReply::NetworkError code) {
    return code == QNetworkReply::ConnectionRefusedError ||
           code == QNetworkReply::RemoteHostClosedError ||
           code == QNetworkReply::HostNotFoundError ||
           code == QNetworkReply::TimeoutError ||
           code == QNetworkReply::TemporaryNetworkFailureError ||
           code == QNetworkReply::OperationCanceledError;
}

State::State(const QString& hostId)
    : settingsGroup("office/hosts/" + QString::fromLatin1(
        QCryptographicHash::hash(hostId.toUtf8(), QCryptographicHash::Sha256).toHex())) {
    cursorQueue.setMaxThreadCount(1);
}

void State::load(StreamingPreferences* prefs) {
    QSettings settings;
    settings.beginGroup(settingsGroup);
    const int width = settings.value("width", prefs->width).toInt();
    const int height = settings.value("height", prefs->height).toInt();
    if (validResolution(width, height)) {
        prefs->width = width;
        prefs->height = height;
    }
    const int mode = settings.value("mouse", 0).toInt();
    mouseMode = static_cast<MouseMode>(mode >= 0 && mode <= 2 ? mode : 0);
    prefs->absoluteMouseMode = mouseMode != MouseMode::Relative;
    prefs->gameOptimizations = true;
}

void State::saveResolution(int width, int height) {
    QSettings settings;
    settings.beginGroup(settingsGroup);
    settings.setValue("width", width);
    settings.setValue("height", height);
}

void State::saveMouse(MouseMode mode) {
    mouseMode = mode;
    QSettings settings;
    settings.beginGroup(settingsGroup);
    settings.setValue("mouse", static_cast<int>(mode));
}

void State::prepareConnection(NvHTTP& http) {
    // Never downgrade authentication during recovery. getServerInfo() has an
    // upstream HTTP fallback; use the already-paired HTTPS endpoint directly.
    const auto xml = http.openConnectionToString(http.m_BaseUrlHttps,
        "serverinfo", {}, 3000, NvHTTP::NVLL_ERROR);
    NvHTTP::verifyResponseStatus(xml);
    if (NvHTTP::getXmlString(xml, "PairStatus") != "1") {
        throw GfeHttpResponseException(401, "Device pairing is required");
    }
    cursorSupported = NvHTTP::getXmlString(xml, "OfficeCursorSet") == "1";
    cursorStatus = cursorSupported ? 0 : -1;
    currentApp = NvHTTP::getCurrentGame(xml);
    peerAddress = http.address();
    peerPort = http.httpsPort();
    peerCertificate = http.serverCert();
}

void State::queueCursor(const NvAddress& address, uint16_t port,
                        const QSslCertificate& cert, bool trueUid, bool visible) {
    if (!cursorSupported) { cursorStatus = -1; return; }
    unsigned generation;
    {
        std::lock_guard<std::mutex> lock(cursorResultMutex);
        generation = ++cursorGeneration;
        cursorStatus = 0;
    }
    cursorQueue.clear(); // At most one in-flight and one latest pending request.
    cursorQueue.start(QRunnable::create([this, address, port, cert, trueUid, visible, generation] {
        int result;
        try {
            NvHTTP http(address, port, cert, trueUid);
            auto xml = http.openConnectionToString(http.m_BaseUrlHttps,
                "office/cursor", visible ? "visible=1" : "visible=0", 2000, NvHTTP::NVLL_ERROR);
            NvHTTP::verifyResponseStatus(xml);
            result = NvHTTP::getXmlString(xml, "cursorVisible") == (visible ? "1" : "0") ? 1 : -2;
        } catch (const std::exception&) {
            result = -2;
        }
        std::lock_guard<std::mutex> lock(cursorResultMutex);
        if (cursorGeneration == generation) cursorStatus = result;
    }));
}
}
