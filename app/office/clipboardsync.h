#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace office {
// Text clipboard sync decisions (office/CLIPBOARD.md). Platform independent:
// the session feeds it NSPasteboard change counts and parsed host replies and
// performs the HTTP requests and pasteboard writes it asks for. UI thread only.

constexpr std::size_t clipboardMaxBytes = 1024 * 1024; // UTF-8 bytes, both directions.

// Line endings travel as LF; CRLF and lone CR become LF.
std::string normalizeClipboardText(const std::string& text);

// Parsed office/clipboard reply. status 0 = transport failure or malformed XML.
struct ClipboardReply {
    int status = 0;
    bool hasSequence = false;
    std::uint64_t sequence = 0;
    bool hasText = false;
    bool tooLarge = false;
    std::string text; // UTF-8, LF line endings
};

class ClipboardSync {
public:
    enum class Push { Skip, Send, TooLarge };
    enum class Reply { None, Denied };

    void setSupported(bool supported) { m_Supported = supported; }
    void setEnabled(bool enabled) { m_Enabled = enabled; }
    // A new connection may be allowed again after a 403 on the previous one.
    void resetConnection() { m_Denied = false; }
    bool supported() const { return m_Supported; }
    bool enabled() const { return m_Enabled; }
    bool denied() const { return m_Denied; }
    bool active() const { return m_Supported && m_Enabled && !m_Denied; }

    // The current pasteboard content is treated as already synced (used when
    // the toggle is switched on: enabling never moves existing content).
    void adoptLocal(long changeCount) { m_LocalChange = changeCount; m_HasLocalChange = true; }

    // Cheap check before reading the pasteboard text: true when a focus gain
    // with this change count may push.
    bool wantsLocal(long changeCount) const {
        return active() && !(m_HasLocalChange && changeCount == m_LocalChange);
    }
    // Remote window gained focus. `text` is replaced by the normalized body
    // when the result is Send.
    Push focusGained(long changeCount, bool hasText, std::string& text);
    // POST result for a push taken at `changeCount`.
    Reply pushFinished(const ClipboardReply& reply, long changeCount);
    // Baseline GET: remember the host sequence without touching the Mac.
    Reply baselineFinished(const ClipboardReply& reply);
    // GET after focus loss / before an active disconnect. Returns true when
    // `reply.text` should be written to the Mac pasteboard; the caller then
    // reports the new change count through localWritten().
    bool pullFinished(const ClipboardReply& reply, Reply& outcome,
                      long changeCountAtRequest, long changeCountNow,
                      bool localHasText, const std::string& localText);
    void localWritten(long changeCount) { adoptLocal(changeCount); }

    bool hasRemoteSequence() const { return m_HasRemoteSequence; }
    std::uint64_t remoteSequence() const { return m_RemoteSequence; }

private:
    Reply deny(int status);
    void rememberRemote(const ClipboardReply& reply);

    bool m_Supported = false;
    bool m_Enabled = true;
    bool m_Denied = false;
    bool m_HasLocalChange = false;
    long m_LocalChange = 0;
    bool m_HasRemoteSequence = false;
    std::uint64_t m_RemoteSequence = 0;
};
}
