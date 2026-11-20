#pragma once

#include "clipboardsync.h"

#include <QString>

namespace office {
// Strict parser for office/clipboard replies (GET and POST share the format).
// Malformed XML, a bad sequence, invalid base64 or invalid UTF-8 return
// status 0, which callers treat like a transport failure.
ClipboardReply parseClipboardResponse(const QString& response);
}
