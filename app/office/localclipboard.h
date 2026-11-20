#pragma once

#include <string>

namespace office {
// The Mac general pasteboard (office/CLIPBOARD.md). Main thread only.
// Other platforms build a stub that never reports text and never writes.
struct LocalClipboard {
    long changeCount = 0;
    bool hasText = false;
    // nspasteboard.org ConcealedType/TransientType (password managers): the
    // text is not read and must not be synced.
    bool concealed = false;
    std::string text; // UTF-8
};

long localClipboardChangeCount();
LocalClipboard readLocalClipboard();
// Replaces the pasteboard with plain text. Returns the new change count, or
// -1 when nothing was written.
long writeLocalClipboard(const std::string& text);
}
