#pragma once

#include <QString>

#include <cstdint>
#include <functional>

namespace office {
// Per-connection host approval, client side of CONNECTION.md §2.

enum class ApprovalState { Invalid, NotRequired, Pending, Approved, Denied, Expired, None };

struct ConnectConfirmResponse {
    int status = 0;
    ApprovalState state = ApprovalState::Invalid;
    int timeoutSeconds = -1;
    bool valid() const { return status == 200 && state != ApprovalState::Invalid; }
};

// Strict parser for `office/connect-request` replies. A 200 reply needs exactly
// one <state> with a known value; anything malformed returns defaults.
ConnectConfirmResponse parseConnectConfirmResponse(const QString& response);

enum class ApprovalOutcome { Proceed, Denied, Expired, TimedOut, Cancelled, Failed };

constexpr int approvalPollIntervalMs = 1000;
constexpr int approvalDeadlineMs = 65000;
constexpr int approvalCancelCheckMs = 100;

struct ApprovalHooks {
    // Sends `action=<action>` and returns the body; may throw on transport errors.
    std::function<QString(const QString& action)> request;
    std::function<bool()> cancelled;
    // Called once, when the host first reports `pending`.
    std::function<void()> waiting;
    std::function<std::int64_t()> now;  // Monotonic milliseconds.
    std::function<void(int ms)> sleep;
};

// Runs start -> status polling until a final state, user cancel or the 65 s
// client deadline. Cancel and deadline send a best-effort `cancel`. Transport
// exceptions also send `cancel` and are then rethrown to the caller.
ApprovalOutcome waitForHostApproval(const ApprovalHooks& hooks);

// launch/resume rejected because no approval permit was available.
bool isHostApprovalRequired(int statusCode, const QString& statusMessage);

// User-visible text for terminal outcomes; empty for Proceed and Cancelled.
QString approvalOutcomeMessage(ApprovalOutcome outcome);
}
