#include "devicename.h"

#include <QSysInfo>
#include <QUrl>

#ifdef Q_OS_DARWIN
#include <CoreFoundation/CoreFoundation.h>
#include <SystemConfiguration/SystemConfiguration.h>
#endif

namespace office {
namespace {
constexpr int maxNameBytes = 64;

bool dropped(char32_t codePoint) {
    if (codePoint >= 0xD800 && codePoint <= 0xDFFF) return true; // Unpaired surrogates.
    switch (QChar::category(codePoint)) {
    case QChar::Other_Control:       // C0, DEL, C1
    case QChar::Other_Format:        // Bidi overrides and invisible formatting
    case QChar::Separator_Line:
    case QChar::Separator_Paragraph:
    case QChar::Other_NotAssigned:
        return true;
    default:
        return false;
    }
}
}

QByteArray sanitizePairingDeviceName(const QString& name) {
    QString cleaned;
    for (const char32_t codePoint : name.toUcs4()) {
        if (!dropped(codePoint)) cleaned += QString::fromUcs4(&codePoint, 1);
    }
    cleaned = cleaned.trimmed();
    QByteArray result;
    for (const char32_t codePoint : cleaned.toUcs4()) {
        const QByteArray encoded = QString::fromUcs4(&codePoint, 1).toUtf8();
        if (result.size() + encoded.size() > maxNameBytes) break;
        result += encoded;
    }
    // Truncation may leave trailing whitespace; the host should see a tidy name.
    result = QString::fromUtf8(result).trimmed().toUtf8();
    return result.isEmpty() ? QByteArrayLiteral("Moonlight Desk") : result;
}

QString localComputerName() {
#ifdef Q_OS_DARWIN
    if (CFStringRef computerName = SCDynamicStoreCopyComputerName(nullptr, nullptr)) {
        const CFIndex length = CFStringGetLength(computerName);
        QString name(int(length), Qt::Uninitialized);
        CFStringGetCharacters(computerName, CFRangeMake(0, length),
                              reinterpret_cast<UniChar*>(name.data()));
        CFRelease(computerName);
        if (!name.trimmed().isEmpty()) return name;
    }
#endif
    QString host = QSysInfo::machineHostName();
    if (host.endsWith(QStringLiteral(".local"), Qt::CaseInsensitive)) host.chop(6);
    return host;
}

QByteArray pairingDeviceNameQuery(const QString& name) {
    return QUrl::toPercentEncoding(QString::fromUtf8(sanitizePairingDeviceName(name)));
}
}
