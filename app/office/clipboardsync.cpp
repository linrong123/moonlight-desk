#include "clipboardsync.h"

namespace office {
std::string normalizeClipboardText(const std::string& text) {
    std::string result;
    result.reserve(text.size());
    for (std::size_t i = 0; i < text.size(); ++i) {
        if (text[i] == '\r') {
            result += '\n';
            if (i + 1 < text.size() && text[i + 1] == '\n') ++i;
        } else {
            result += text[i];
        }
    }
    return result;
}

ClipboardSync::Reply ClipboardSync::deny(int status) {
    if (status != 403 || m_Denied) return Reply::None;
    // The host refused (toggle off, not authorized or not streaming). Stop for
    // the rest of this connection; the caller logs once.
    m_Denied = true;
    return Reply::Denied;
}

void ClipboardSync::rememberRemote(const ClipboardReply& reply) {
    m_HasRemoteSequence = true;
    m_RemoteSequence = reply.sequence;
}

ClipboardSync::Push ClipboardSync::focusGained(long changeCount, bool hasText, std::string& text) {
    if (!active()) return Push::Skip;
    // NSPasteboard changeCount: unchanged since the last push or pull write
    // means nothing new was copied on the Mac.
    if (m_HasLocalChange && changeCount == m_LocalChange) return Push::Skip;
    adoptLocal(changeCount);
    if (!hasText || text.empty()) return Push::Skip;
    std::string normalized = normalizeClipboardText(text);
    if (normalized.size() > clipboardMaxBytes) return Push::TooLarge;
    text = std::move(normalized);
    return Push::Send;
}

ClipboardSync::Reply ClipboardSync::pushFinished(const ClipboardReply& reply, long changeCount) {
    if (reply.status == 403) return deny(reply.status);
    if (reply.status == 200) {
        if (reply.hasSequence) rememberRemote(reply);
        return Reply::None;
    }
    // Transport failure or a busy host clipboard: try again on the next focus
    // gain unless the Mac clipboard has moved on already. 400/413 are final.
    if ((reply.status == 0 || reply.status >= 500) && m_HasLocalChange && m_LocalChange == changeCount)
        m_HasLocalChange = false;
    return Reply::None;
}

ClipboardSync::Reply ClipboardSync::baselineFinished(const ClipboardReply& reply) {
    if (reply.status == 403) return deny(reply.status);
    if (reply.status == 200 && reply.hasSequence) rememberRemote(reply);
    return Reply::None;
}

bool ClipboardSync::pullFinished(const ClipboardReply& reply, Reply& outcome,
                                 long changeCountAtRequest, long changeCountNow,
                                 bool localHasText, const std::string& localText) {
    outcome = Reply::None;
    if (reply.status == 403) {
        outcome = deny(reply.status);
        return false;
    }
    if (!active() || reply.status != 200 || !reply.hasSequence) return false;
    // Something was copied on the Mac while the request was in flight: the
    // newer local content wins and is pushed on the next focus gain.
    if (changeCountNow != changeCountAtRequest) {
        rememberRemote(reply);
        return false;
    }
    if (m_HasRemoteSequence && reply.sequence == m_RemoteSequence) return false;
    rememberRemote(reply);
    if (!reply.hasText || reply.tooLarge || reply.text.empty()) return false;
    if (reply.text.size() > clipboardMaxBytes) return false;
    if (localHasText && normalizeClipboardText(localText) == reply.text) return false;
    return true;
}
}
