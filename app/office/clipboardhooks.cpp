#include "officestate.h"
#include "clipboardresponse.h"
#include "localclipboard.h"
#include "toolbar.h"

#include "SDL_compat.h"

// Text clipboard sync, session side (office/CLIPBOARD.md). Every function here
// except the queued HTTP job runs on the SDL/UI thread. Clipboard content is
// never logged, only byte counts and status codes.
namespace office {
namespace {
// Registered once on the UI thread; workers push it to wake SDL_WaitEventTimeout
// so a pulled text lands on the Mac within a frame. The event loop has no
// default case for registered types, so the event itself is ignored.
std::atomic<Uint32> clipboardWakeEvent{0};

constexpr int clipboardTimeoutMs = 3000;
constexpr int finalPullTimeoutMs = 1500;
}

void State::showClipboard(Toolbar* toolbar) {
    if (toolbar) toolbar->setClipboard(clipboard.supported(), clipboard.enabled(), clipboard.denied());
}

void State::queueClipboard(ClipboardRequest kind, std::string text, long changeCount, int timeoutMs) {
    unsigned generation;
    {
        std::lock_guard<std::mutex> lock(clipboardMutex);
        generation = clipboardGeneration;
    }
    const auto address = peerAddress;
    const auto port = peerPort;
    const auto cert = peerCertificate;
    const auto uid = trueUid;
    const QByteArray body = QByteArray::fromStdString(text);
    clipboardQueue.start(QRunnable::create([this, address, port, cert, uid, kind, changeCount,
                                            timeoutMs, generation, body] {
        ClipboardReply reply;
        try {
            NvHTTP http(address, port, cert, uid);
            reply = parseClipboardResponse(http.requestOfficeClipboard(body, timeoutMs));
        } catch (const QtNetworkReplyException& e) {
            // Bare HTTP errors without XML: 401 from the host's authentication
            // layer (disabled client, unknown certificate), 413 for an
            // oversize body. Timeouts and connection failures stay 0.
            reply = {};
            reply.status = clipboardErrorStatus(e.getHttpStatusCode());
            if (!reply.status && e.getError() == QNetworkReply::AuthenticationRequiredError) reply.status = 401;
        } catch (const GfeHttpResponseException& e) {
            // Missing pairing or server certificate mismatch: an authentication
            // failure, never retried on this connection.
            reply = {};
            reply.status = e.getStatusCode() == 401 ? 401 : 0;
        } catch (const std::exception&) {
            reply = {};
        }
        {
            std::lock_guard<std::mutex> lock(clipboardMutex);
            if (clipboardGeneration != generation) return;
            clipboardResults.push_back({kind, changeCount, std::move(reply)});
        }
        if (const Uint32 type = clipboardWakeEvent.load()) {
            SDL_Event event = {};
            event.type = type;
            SDL_PushEvent(&event);
        }
    }));
}

void State::applyClipboardResults(Toolbar* toolbar) {
    std::deque<ClipboardResult> results;
    {
        std::lock_guard<std::mutex> lock(clipboardMutex);
        results.swap(clipboardResults);
    }
    for (auto& result : results) {
        auto outcome = ClipboardSync::Reply::None;
        const int status = result.reply.status;
        switch (result.kind) {
        case ClipboardRequest::Baseline:
            outcome = clipboard.baselineFinished(result.reply);
            if (status != 200 && !clipboardDenial(status))
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "Office clipboard: baseline read failed (%d)", status);
            break;
        case ClipboardRequest::Push:
            outcome = clipboard.pushFinished(result.reply, result.changeCount);
            if (status != 200 && !clipboardDenial(status))
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "Office clipboard: push failed (%d)", status);
            break;
        case ClipboardRequest::Pull: {
            const auto local = readLocalClipboard();
            if (clipboard.pullFinished(result.reply, outcome, result.changeCount, local.changeCount,
                                       local.hasText, local.text)) {
                const long written = writeLocalClipboard(result.reply.text);
                if (written >= 0) {
                    clipboard.localWritten(written);
                    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "Office clipboard: pulled %zu bytes",
                                result.reply.text.size());
                } else {
                    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "Office clipboard: Mac pasteboard write failed");
                }
            } else if (status == 200 && result.reply.tooLarge) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "Office clipboard: host text exceeds 1 MiB; not pulled");
            } else if (status != 200 && !clipboardDenial(status)) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "Office clipboard: pull failed (%d)", status);
            }
            break;
        }
        }
        if (outcome == ClipboardSync::Reply::Denied) {
            if (clipboard.deniedStatus() == 401)
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "Office clipboard: authentication rejected (401: client disabled or certificate not accepted); sync stopped for this connection");
            else
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "Office clipboard: host refused (403); sync stopped for this connection");
            showClipboard(toolbar);
        }
    }
}

void State::clipboardPush() {
    if (!clipboard.wantsLocal(localClipboardChangeCount())) return;
    auto local = readLocalClipboard();
    switch (clipboard.focusGained(local.changeCount, local.hasText, local.text)) {
    case ClipboardSync::Push::Send:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "Office clipboard: pushing %zu bytes", local.text.size());
        queueClipboard(ClipboardRequest::Push, std::move(local.text), local.changeCount, clipboardTimeoutMs);
        break;
    case ClipboardSync::Push::TooLarge:
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "Office clipboard: Mac text exceeds 1 MiB; not pushed");
        break;
    case ClipboardSync::Push::Skip:
        break;
    }
}

void State::clipboardPull(int timeoutMs) {
    if (!clipboard.active()) return;
    queueClipboard(ClipboardRequest::Pull, {}, localClipboardChangeCount(), timeoutMs);
}

void State::clipboardStart(Toolbar* toolbar, bool focused) {
    if (!clipboardWakeEvent.load()) {
        // The first registration returns SDL_USEREVENT itself, whose handler
        // asserts on unknown codes; take the next number instead.
        Uint32 type = SDL_RegisterEvents(1);
        if (type == SDL_USEREVENT) type = SDL_RegisterEvents(1);
        if (type != static_cast<Uint32>(-1) && type != SDL_USEREVENT) clipboardWakeEvent = type;
    }
    {
        std::lock_guard<std::mutex> lock(clipboardMutex);
        ++clipboardGeneration;
        clipboardResults.clear();
    }
    clipboardStarted = true;
    clipboard.setSupported(clipboardSupported);
    clipboard.setEnabled(clipboardEnabled);
    clipboard.resetConnection();
    showClipboard(toolbar);
    if (clipboard.active()) {
        // Remember the host's current sequence so content that was already on
        // Windows is not pulled over the Mac clipboard on the first focus loss.
        queueClipboard(ClipboardRequest::Baseline, {}, 0, clipboardTimeoutMs);
    }
    // A focused window counts as "focus gained": text copied on the Mac before
    // connecting is pushed once, like Remote Desktop.
    clipboardFocused = false;
    clipboardPoll(toolbar, focused);
}

void State::clipboardPoll(Toolbar* toolbar, bool focused) {
    if (!clipboardStarted) return;
    applyClipboardResults(toolbar);
    if (focused == clipboardFocused) return;
    clipboardFocused = focused;
    if (focused) clipboardPush();
    else clipboardPull(clipboardTimeoutMs);
}

void State::clipboardToggle(Toolbar* toolbar, bool enabled, bool focused) {
    if (enabled == clipboard.enabled()) return;
    saveClipboard(enabled);
    clipboard.setEnabled(enabled);
    {
        // Results of requests sent before the switch never apply after it.
        std::lock_guard<std::mutex> lock(clipboardMutex);
        ++clipboardGeneration;
        clipboardResults.clear();
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "Office clipboard: sync %s", enabled ? "on" : "off");
    if (enabled && clipboardStarted && clipboard.active()) {
        // Switching on never moves existing content; only later copies sync.
        clipboard.adoptLocal(localClipboardChangeCount());
        clipboard.forgetRemote();
        queueClipboard(ClipboardRequest::Baseline, {}, 0, clipboardTimeoutMs);
    }
    clipboardFocused = focused;
    showClipboard(toolbar);
}

void State::clipboardStop(bool finalPull) {
    if (clipboardStarted && finalPull && clipboard.active()) {
        // Copy-then-disconnect keeps the Windows text. The stream is still up
        // (LiStopConnection runs later), so the host accepts this read. Wait at
        // most finalPullTimeoutMs, even when an earlier request is in flight.
        applyClipboardResults(nullptr);
        clipboardPull(finalPullTimeoutMs);
        clipboardQueue.waitForDone(finalPullTimeoutMs);
        applyClipboardResults(nullptr);
    }
    clipboardStarted = false;
    {
        std::lock_guard<std::mutex> lock(clipboardMutex);
        ++clipboardGeneration;
        clipboardResults.clear();
    }
    clipboardQueue.clear();
}
}
