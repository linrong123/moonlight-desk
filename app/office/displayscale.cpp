#include "displayscale.h"

#include <QMap>
#include <QRegularExpression>
#include <QXmlStreamReader>
#include <algorithm>

namespace office {
namespace {
constexpr int allowedScales[] = {100,125,150,175,200,225,250,300,350,400,450,500};

int scaleValue(const QString& text)
{
    // Comparing canonical strings also rejects signs, whitespace, zero padding,
    // non-ASCII digits, and overflow without a permissive integer conversion.
    for (int value : allowedScales) {
        if (text == QString::number(value)) return value;
    }
    return 0;
}

bool validToken(const QString& token)
{
    static const QRegularExpression hex(QStringLiteral("\\A[0-9a-fA-F]{32}\\z"));
    return hex.match(token).hasMatch();
}
}

DisplayScaleResult parseDisplayScaleResponse(const QString& response)
{
    if (response.size() > 8192 || response.toUtf8().size() > 8192) return {};
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
                for (const auto& attribute : xml.attributes()) {
                    if (!attribute.namespaceUri().isEmpty() || !attribute.prefix().isEmpty()) return {};
                    if (attribute.name() == QLatin1String("status_code")) statusText = attribute.value().toString();
                }
                for (int known : {200,400,409,422,501,503}) {
                    if (statusText == QString::number(known)) status = known;
                }
                if (!status) return {};
            } else if (depth == 1) {
                field = xml.name().toString();
                if (fields.contains(field) || !xml.attributes().isEmpty()) return {};
                if (field != QLatin1String("scale") && field != QLatin1String("recommended") &&
                    field != QLatin1String("supportedScales") && field != QLatin1String("displayToken") &&
                    field != QLatin1String("message")) return {};
                text.clear();
            } else return {}; // Values must be plain text directly under root.
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
    if (fields.contains(QStringLiteral("displayToken")) && !validToken(fields.value(QStringLiteral("displayToken")))) return {};
    DisplayScaleResult result;
    result.status = status;
    if (status != 200) return result;
    if (fields.size() != 4 || !fields.contains(QStringLiteral("scale")) ||
        !fields.contains(QStringLiteral("recommended")) || !fields.contains(QStringLiteral("supportedScales")) ||
        !fields.contains(QStringLiteral("displayToken"))) return {};
    result.current = scaleValue(fields.value(QStringLiteral("scale")));
    result.recommended = scaleValue(fields.value(QStringLiteral("recommended")));
    if (!result.current || !result.recommended) return {};
    const auto values = fields.value(QStringLiteral("supportedScales")).split(QLatin1Char(','));
    int previous = 0;
    for (const auto& valueText : values) {
        const int value = scaleValue(valueText);
        if (!value || value <= previous) return {};
        result.supported.push_back(value);
        previous = value;
    }
    if (!std::binary_search(result.supported.begin(), result.supported.end(), result.current) ||
        !std::binary_search(result.supported.begin(), result.supported.end(), result.recommended)) return {};
    result.token = fields.value(QStringLiteral("displayToken"));
    return result;
}
}
