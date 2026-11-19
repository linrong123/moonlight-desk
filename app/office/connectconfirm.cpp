#include "connectconfirm.h"

#include <QMap>
#include <QXmlStreamReader>

#include <algorithm>

namespace office {
namespace {
ApprovalState stateValue(const QString& text) {
    if (text == QLatin1String("not_required")) return ApprovalState::NotRequired;
    if (text == QLatin1String("pending")) return ApprovalState::Pending;
    if (text == QLatin1String("approved")) return ApprovalState::Approved;
    if (text == QLatin1String("denied")) return ApprovalState::Denied;
    if (text == QLatin1String("expired")) return ApprovalState::Expired;
    if (text == QLatin1String("none")) return ApprovalState::None;
    return ApprovalState::Invalid;
}

bool digitsOnly(const QString& text, int maxLength) {
    if (text.isEmpty() || text.size() > maxLength) return false;
    return std::all_of(text.begin(), text.end(), [](QChar c) {
        return c >= QLatin1Char('0') && c <= QLatin1Char('9');
    });
}
}

ConnectConfirmResponse parseConnectConfirmResponse(const QString& response)
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
                // Unknown leaf fields are ignored so the host can add diagnostics;
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

    ConnectConfirmResponse result;
    result.status = status;
    if (status != 200) return result;
    if (!fields.contains(QStringLiteral("state"))) return {};
    result.state = stateValue(fields.value(QStringLiteral("state")));
    if (result.state == ApprovalState::Invalid) return {};
    if (fields.contains(QStringLiteral("timeoutSeconds"))) {
        const QString timeout = fields.value(QStringLiteral("timeoutSeconds"));
        if (!digitsOnly(timeout, 4)) return {};
        result.timeoutSeconds = timeout.toInt();
    }
    return result;
}

ApprovalOutcome waitForHostApproval(const ApprovalHooks& hooks)
{
    const std::int64_t deadline = hooks.now() + approvalDeadlineMs;
    const auto withdraw = [&hooks] { withdrawApprovalRequest(hooks.request); };

    try {
        QString action = QStringLiteral("start");
        bool waitingShown = false;
        for (;;) {
            if (hooks.cancelled()) {
                if (waitingShown) withdraw();
                return ApprovalOutcome::Cancelled;
            }
            const auto reply = parseConnectConfirmResponse(hooks.request(action));
            if (!reply.valid()) { withdraw(); return ApprovalOutcome::Failed; }
            switch (reply.state) {
            case ApprovalState::Approved:
            case ApprovalState::NotRequired:
                return ApprovalOutcome::Proceed;
            case ApprovalState::Denied:
                return ApprovalOutcome::Denied;
            case ApprovalState::Expired:
                return ApprovalOutcome::Expired;
            case ApprovalState::Pending:
                break;
            default:
                // `none` (request vanished, e.g. host restarted) or invalid.
                withdraw();
                return ApprovalOutcome::Failed;
            }
            if (!waitingShown) {
                waitingShown = true;
                if (hooks.waiting) hooks.waiting();
            }
            action = QStringLiteral("status");

            const std::int64_t nextPoll = std::min(hooks.now() + approvalPollIntervalMs, deadline);
            for (std::int64_t now = hooks.now(); now < nextPoll; now = hooks.now()) {
                if (hooks.cancelled()) { withdraw(); return ApprovalOutcome::Cancelled; }
                hooks.sleep(int(std::min<std::int64_t>(approvalCancelCheckMs, nextPoll - now)));
            }
            if (hooks.cancelled()) { withdraw(); return ApprovalOutcome::Cancelled; }
            if (hooks.now() >= deadline) { withdraw(); return ApprovalOutcome::TimedOut; }
        }
    } catch (...) {
        withdraw();
        throw;
    }
}

void withdrawApprovalRequest(const std::function<QString(const QString& action)>& request)
{
    if (!request) return;
    try { request(QStringLiteral("cancel")); } catch (...) {}
}

bool isHostApprovalRequired(int statusCode, const QString& statusMessage)
{
    return statusCode == 403 && statusMessage == QLatin1String("Host approval required");
}

QString approvalOutcomeMessage(ApprovalOutcome outcome)
{
    switch (outcome) {
    case ApprovalOutcome::Denied:
        return QStringLiteral("被控端拒绝了连接");
    case ApprovalOutcome::Expired:
    case ApprovalOutcome::TimedOut:
        return QStringLiteral("被控端未在 60 秒内确认");
    case ApprovalOutcome::Failed:
        return QStringLiteral("无法确认被控端授权状态");
    case ApprovalOutcome::ApprovalRequired:
        return QStringLiteral("被控端需要本机确认，请重新连接");
    default:
        return {};
    }
}

QString approvalBridgeState(ApprovalOutcome outcome, bool waited)
{
    switch (outcome) {
    case ApprovalOutcome::Proceed:
        return waited ? QStringLiteral("starting") : QString();
    case ApprovalOutcome::Denied:
        return QStringLiteral("denied");
    case ApprovalOutcome::Expired:
    case ApprovalOutcome::TimedOut:
        return QStringLiteral("expired");
    case ApprovalOutcome::ApprovalRequired:
        return QStringLiteral("approval_required");
    default:
        return {};
    }
}
}
