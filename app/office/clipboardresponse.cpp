#include "clipboardresponse.h"

#include <QByteArray>
#include <QMap>
#include <QXmlStreamReader>

#include <algorithm>

namespace office {
namespace {
// 1 MiB of text is about 1.4 MB of base64 plus a small envelope.
constexpr int maxResponseBytes = 2 * 1024 * 1024;

bool digitsOnly(const QString& text, int maxLength) {
    if (text.isEmpty() || text.size() > maxLength) return false;
    return std::all_of(text.begin(), text.end(), [](QChar c) {
        return c >= QLatin1Char('0') && c <= QLatin1Char('9');
    });
}

// Standard padded base64 only; empty is valid (QByteArray::fromBase64 silently skips junk).
bool strictBase64(const QByteArray& text) {
    if (text.size() % 4 != 0) return false;
    int padding = 0;
    for (int i = 0; i < text.size(); ++i) {
        const char c = text.at(i);
        if (c == '=') {
            if (i < text.size() - 2) return false;
            ++padding;
        } else if (padding || !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                                (c >= '0' && c <= '9') || c == '+' || c == '/')) {
            return false;
        }
    }
    return true;
}

bool flag(const QMap<QString, QString>& fields, const char* name, bool& value) {
    const QString key = QLatin1String(name);
    if (!fields.contains(key)) { value = false; return true; }
    const QString text = fields.value(key);
    if (text == QLatin1String("1")) { value = true; return true; }
    if (text == QLatin1String("0")) { value = false; return true; }
    return false;
}
}

ClipboardReply parseClipboardResponse(const QString& response)
{
    if (response.size() > maxResponseBytes) return {};
    QXmlStreamReader xml(response);
    QMap<QString, QString> fields;
    int status = 0;
    bool rootSeen = false;
    bool rootClosed = false;
    int depth = 0;
    QString field;
    QString text;

    while (!xml.atEnd()) {
        const auto event = xml.readNext();
        if (event == QXmlStreamReader::DTD || event == QXmlStreamReader::EntityReference) return {};
        if (event == QXmlStreamReader::StartElement) {
            if (!xml.namespaceUri().isEmpty() || !xml.prefix().isEmpty() || !xml.namespaceDeclarations().isEmpty()) return {};
            if (depth == 0) {
                if (rootSeen || rootClosed || xml.name() != QLatin1String("root")) return {};
                rootSeen = true;
                QString statusText;
                int statusCount = 0;
                for (const auto& attribute : xml.attributes()) {
                    if (!attribute.namespaceUri().isEmpty() || !attribute.prefix().isEmpty()) return {};
                    if (attribute.name() == QLatin1String("status_code")) {
                        statusText = attribute.value().toString();
                        ++statusCount;
                    }
                }
                if (statusCount != 1 || !digitsOnly(statusText, 3)) return {};
                status = statusText.toInt();
                if (status < 100 || status > 599) return {};
            } else if (depth == 1) {
                // Unknown leaf fields (status_message, diagnostics) are ignored;
                // every field must still be unique, attribute-free plain text.
                field = xml.name().toString();
                if (fields.contains(field) || !xml.attributes().isEmpty()) return {};
                text.clear();
            } else return {};
            ++depth;
        } else if (event == QXmlStreamReader::Characters) {
            if (depth == 2) text += xml.text();
            else if (!xml.isWhitespace()) return {};
        } else if (event == QXmlStreamReader::EndElement) {
            if (depth == 2) fields.insert(field, text);
            if (depth == 1) rootClosed = true;
            --depth;
        }
    }
    if (xml.hasError() || !rootSeen || !rootClosed || depth != 0) return {};

    ClipboardReply result;
    result.status = status;
    if (status != 200) return result;

    if (fields.contains(QStringLiteral("sequence"))) {
        const QString sequence = fields.value(QStringLiteral("sequence")).trimmed();
        bool ok = false;
        const qulonglong value = sequence.toULongLong(&ok, 10);
        if (!digitsOnly(sequence, 20) || !ok) return {};
        result.hasSequence = true;
        result.sequence = value;
    }
    if (!flag(fields, "hasText", result.hasText) || !flag(fields, "tooLarge", result.tooLarge)) return {};
    if (result.hasText) {
        if (!fields.contains(QStringLiteral("text"))) return {};
        const QByteArray encoded = fields.value(QStringLiteral("text")).trimmed().toLatin1();
        if (!strictBase64(encoded)) return {};
        const QByteArray bytes = QByteArray::fromBase64(encoded);
        if (static_cast<std::size_t>(bytes.size()) > clipboardMaxBytes) return {};
        // Reject invalid UTF-8 instead of writing replacement characters.
        if (QString::fromUtf8(bytes).toUtf8() != bytes) return {};
        result.text = normalizeClipboardText(bytes.toStdString());
    }
    return result;
}
}
