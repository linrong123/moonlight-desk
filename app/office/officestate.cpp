#include "officestate.h"
#include <Limelight.h>
#include <QSettings>
#include <QCryptographicHash>
#include <chrono>
#include <algorithm>

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
    displayScaleQueue.setMaxThreadCount(1);
}

State::~State() {
    // Pools must finish before the result mutexes and snapshots are destroyed,
    // including partial startup failures that never reach Session cleanup.
    cursorQueue.clear();
    displayScaleQueue.clear();
    cursorQueue.waitForDone();
    displayScaleQueue.waitForDone();
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
    displayScaleSupported = NvHTTP::getXmlString(xml, "OfficeDisplayScale") == "1";
    {
        std::lock_guard<std::mutex> lock(displayScaleMutex);
        ++displayScaleGeneration;
        displayScale = {};
        displayScale.pending = displayScaleSupported;
        if (!displayScaleSupported)
            displayScale.message = QStringLiteral("Windows缩放需更新被控端");
    }
    currentApp = NvHTTP::getCurrentGame(xml);
    peerAddress = http.address();
    peerPort = http.httpsPort();
    peerCertificate = http.serverCert();
}

State::DisplayScaleSnapshot State::displayScaleSnapshot() {
    std::lock_guard<std::mutex> lock(displayScaleMutex);
    return displayScale;
}

void State::queueDisplayScale(int percent) {
    if (!displayScaleSupported || userStopped) return;
    unsigned generation;
    QString token;
    {
        std::lock_guard<std::mutex> lock(displayScaleMutex);
        if (percent != 0) {
            const auto& value = displayScale.value;
            if (displayScale.pending || !value.valid() ||
                std::find(value.supported.begin(), value.supported.end(), percent) == value.supported.end()) return;
            if (percent == value.current) return;
            token = value.token;
        }
        generation = ++displayScaleGeneration;
        displayScale.pending = true;
        displayScale.message = percent ? QStringLiteral("正在设置Windows文字和图标大小…") :
            QStringLiteral("正在读取Windows缩放…");
    }
    const auto address = peerAddress;
    const auto port = peerPort;
    const auto cert = peerCertificate;
    const auto uid = trueUid;
    displayScaleQueue.clear();
    displayScaleQueue.start(QRunnable::create([this, address, port, cert, uid, percent, token, generation] {
        DisplayScaleResult result;
        QString message;
        try {
            NvHTTP http(address, port, cert, uid);
            auto request = [&](int target, const QString& displayToken = QString()) {
                try {
                    return parseDisplayScaleResponse(http.requestOfficeDisplayScale(target, displayToken));
                } catch (const std::exception&) { return DisplayScaleResult{}; }
            };
            result = request(percent, token);
            if (!result.valid() || (percent && result.current != percent)) {
                const int failedStatus = result.status;
                // A lost POST response does not prove the write failed. Query
                // once, never repeat the write, and show only the read-back value.
                if (percent) result = request(0);
                if (percent && result.valid() && result.current == percent)
                    message = QStringLiteral("Windows缩放已核实为%1%").arg(result.current);
                else if (failedStatus == 409)
                    message = QStringLiteral("显示器已变化，请重新选择Windows缩放");
                else if (failedStatus == 422)
                    message = QStringLiteral("Windows不支持该缩放比例");
                else if (failedStatus == 501)
                    message = QStringLiteral("此主机不支持Windows缩放");
                else
                    message = QStringLiteral("未能确认Windows缩放；请重连后重试");
            } else {
                message = QStringLiteral("Windows文字和图标：%1%").arg(result.current);
            }
        } catch (const std::exception&) {
            result = {};
            message = QStringLiteral("Windows缩放读取失败；请重连后重试");
        }
        std::lock_guard<std::mutex> lock(displayScaleMutex);
        if (displayScaleGeneration == generation) {
            displayScale.value = std::move(result);
            displayScale.pending = false;
            displayScale.message = std::move(message);
        }
    }));
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
