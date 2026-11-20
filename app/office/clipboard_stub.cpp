#include "localclipboard.h"

// Clipboard sync is implemented for the macOS controller only.
namespace office {
long localClipboardChangeCount() { return 0; }
LocalClipboard readLocalClipboard() { return {}; }
long writeLocalClipboard(const std::string&) { return -1; }
}
