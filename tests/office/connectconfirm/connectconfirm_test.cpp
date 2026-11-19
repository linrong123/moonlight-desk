#include "office/connectconfirm.h"
#include <QCoreApplication>
#include <QStringList>
#include <cstdio>
#include <cstdlib>
#include <utility>
#include <stdexcept>

using office::ApprovalOutcome;
using office::ApprovalState;

static int checks;
static void require(bool value) { ++checks; if (!value) { std::fprintf(stderr,"FAIL check %d\n",checks); std::abort(); } }

static QString reply(const QString& state, const QString& extra = {}) {
    return "<root status_code=\"200\">" + (state.isNull() ? QString() : "<state>" + state + "</state>") + extra + "</root>";
}
static void rejected(const QString& input) { require(!office::parseConnectConfirmResponse(input).valid()); }

// Scripted host: one reply per request; the clock only moves when the client sleeps.
struct FakeHost {
    QStringList replies;
    QStringList actions;
    std::int64_t clock = 1000;
    int waitingCalls = 0;
    int cancelAtMs = -1;      // User cancels once the clock reaches this point.
    int throwOnRequest = -1;  // Index of the request that fails in transport.
    bool cancelThrows = false;

    office::ApprovalHooks hooks() {
        office::ApprovalHooks h;
        h.request = [this](const QString& action) {
            actions << action;
            if (action == "cancel") {
                if (cancelThrows) throw std::runtime_error("cancel lost");
                return reply("none");
            }
            if (actions.size() - 1 == throwOnRequest) throw std::runtime_error("network");
            if (replies.isEmpty()) return reply("pending", "<timeoutSeconds>60</timeoutSeconds>");
            return replies.takeFirst();
        };
        h.cancelled = [this] { return cancelAtMs >= 0 && clock >= cancelAtMs; };
        h.waiting = [this] { ++waitingCalls; };
        h.now = [this] { return clock; };
        h.sleep = [this](int ms) { require(ms > 0 && ms <= office::approvalCancelCheckMs); clock += ms; };
        return h;
    }
};

static void parser() {
    auto r = office::parseConnectConfirmResponse(reply("pending", "<timeoutSeconds>60</timeoutSeconds>"));
    require(r.valid() && r.state == ApprovalState::Pending && r.timeoutSeconds == 60);
    const std::pair<const char*, ApprovalState> states[] = {
        {"not_required", ApprovalState::NotRequired}, {"approved", ApprovalState::Approved},
        {"denied", ApprovalState::Denied}, {"expired", ApprovalState::Expired}, {"none", ApprovalState::None}};
    for (const auto& s : states) {
        r = office::parseConnectConfirmResponse(reply(s.first));
        require(r.valid() && r.state == s.second && r.timeoutSeconds == -1);
    }
    // Sunshine style: declaration, status_message, pretty printing, unknown leaf fields.
    require(office::parseConnectConfirmResponse("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<root status_code=\"200\" status_message=\"OK\">\n  <state>approved</state>\n  <deviceName>x</deviceName>\n</root>\n").valid());
    // Non-200 keeps only the status and never a state.
    r = office::parseConnectConfirmResponse("<root status_code=\"400\" status_message=\"Invalid action\"/>");
    require(!r.valid() && r.status == 400 && r.state == ApprovalState::Invalid);
    r = office::parseConnectConfirmResponse("<root status_code=\"403\"><state>approved</state></root>");
    require(!r.valid() && r.status == 403);

    rejected("");
    rejected("not xml");
    rejected(reply(QString()));                                   // state missing
    rejected(reply("Approved"));                                  // case-sensitive enum
    rejected(reply(" approved"));
    rejected(reply("yes"));
    rejected(reply(""));
    rejected(reply("pending", "<state>approved</state>"));       // duplicate state
    rejected(reply("pending", "<timeoutSeconds>-1</timeoutSeconds>"));
    rejected(reply("pending", "<timeoutSeconds>6O</timeoutSeconds>"));
    rejected(reply("pending", "<timeoutSeconds>99999</timeoutSeconds>"));
    rejected(reply("pending", "<timeoutSeconds>1</timeoutSeconds><timeoutSeconds>2</timeoutSeconds>"));
    rejected("<root status_code=\"200\"><state><b>approved</b></state></root>");
    rejected("<root status_code=\"200\"><state a=\"1\">approved</state></root>");
    rejected("<root status_code=\"200\">approved<state>approved</state></root>");
    rejected("<root><state>approved</state></root>");             // status missing
    rejected("<root status_code=\"200\" status_code=\"200\"><state>approved</state></root>");
    rejected("<root status_code=\"2OO\"><state>approved</state></root>");
    rejected("<root status_code=\"+200\"><state>approved</state></root>");
    rejected("<root status_code=\"99\"><state>approved</state></root>");
    rejected("<other status_code=\"200\"><state>approved</state></other>");
    rejected(reply("approved") + reply("approved"));               // two roots
    rejected("<root status_code=\"200\"><state>approved</state>");  // unclosed
    rejected("<!DOCTYPE root [<!ENTITY s \"approved\">]><root status_code=\"200\"><state>&s;</state></root>");
    rejected("<x:root xmlns:x=\"urn:x\" status_code=\"200\"><state>approved</state></x:root>");
    rejected("<root xmlns=\"urn:x\" status_code=\"200\"><state>approved</state></root>");
    rejected(reply("approved", "<pad>" + QString(8200, 'a') + "</pad>"));
}

static ApprovalOutcome run(FakeHost& host) { return office::waitForHostApproval(host.hooks()); }

static void flow() {
    {   // not_required: proceed immediately, no waiting UI, no cancel.
        FakeHost host; host.replies << reply("not_required");
        require(run(host) == ApprovalOutcome::Proceed);
        require(host.actions == QStringList{"start"} && host.waitingCalls == 0);
    }
    {   // approved on start (recovery grace) proceeds without waiting UI.
        FakeHost host; host.replies << reply("approved");
        require(run(host) == ApprovalOutcome::Proceed && host.actions == QStringList{"start"} && host.waitingCalls == 0);
    }
    {   // pending -> approved after polling once per second.
        FakeHost host; host.replies << reply("pending") << reply("pending") << reply("approved");
        require(run(host) == ApprovalOutcome::Proceed);
        require((host.actions == QStringList{"start", "status", "status"}));
        require(host.waitingCalls == 1 && host.clock == 1000 + 2 * office::approvalPollIntervalMs);
    }
    {   // denied is terminal; nothing else is sent.
        FakeHost host; host.replies << reply("pending") << reply("denied");
        require(run(host) == ApprovalOutcome::Denied && (host.actions == QStringList{"start", "status"}));
        require(office::approvalOutcomeMessage(ApprovalOutcome::Denied) == QStringLiteral("被控端拒绝了连接"));
    }
    {   // expired reported by the host.
        FakeHost host; host.replies << reply("pending") << reply("expired");
        require(run(host) == ApprovalOutcome::Expired && (host.actions == QStringList{"start", "status"}));
        require(office::approvalOutcomeMessage(ApprovalOutcome::Expired) == QStringLiteral("被控端未在 60 秒内确认"));
    }
    {   // Host never answers: client gives up at 65 s and withdraws the request.
        FakeHost host;
        require(run(host) == ApprovalOutcome::TimedOut);
        require(host.clock - 1000 == office::approvalDeadlineMs);
        require(host.actions.first() == "start" && host.actions.last() == "cancel");
        require(host.actions.count(QStringLiteral("status")) == office::approvalDeadlineMs / office::approvalPollIntervalMs - 1);
        require(host.waitingCalls == 1);
        require(office::approvalOutcomeMessage(ApprovalOutcome::TimedOut) == QStringLiteral("被控端未在 60 秒内确认"));
    }
    {   // Invalid XML ends the wait and withdraws the request.
        FakeHost host; host.replies << reply("pending") << QStringLiteral("<root status_code=\"200\"><state>maybe</state></root>");
        require(run(host) == ApprovalOutcome::Failed && (host.actions == QStringList{"start", "status", "cancel"}));
        require(!office::approvalOutcomeMessage(ApprovalOutcome::Failed).isEmpty());
    }
    {   // Host error status (400) and a vanished request (`none`) fail too.
        FakeHost a; a.replies << QStringLiteral("<root status_code=\"400\"/>");
        require(run(a) == ApprovalOutcome::Failed);
        FakeHost b; b.replies << reply("pending") << reply("none");
        require(run(b) == ApprovalOutcome::Failed && b.actions.last() == "cancel");
    }
    {   // User cancel during polling: stop within one 100 ms slice and send cancel.
        FakeHost host; host.cancelAtMs = 1000 + 2500;
        require(run(host) == ApprovalOutcome::Cancelled);
        require(host.clock == 1000 + 2500);
        require((host.actions == QStringList{"start", "status", "status", "cancel"}));
        require(office::approvalOutcomeMessage(ApprovalOutcome::Cancelled).isEmpty());
    }
    {   // Host remembers a denied/expired result for 30 s: start returns it
        // directly. Final result shown at once; no waiting UI, no cancel.
        FakeHost host; host.replies << reply("denied");
        require(run(host) == ApprovalOutcome::Denied);
        require(host.actions == QStringList{"start"} && host.waitingCalls == 0);
        FakeHost late; late.replies << reply("expired");
        require(run(late) == ApprovalOutcome::Expired);
        require(late.actions == QStringList{"start"} && late.waitingCalls == 0);
    }
    {   // Cancel before anything was sent: no request at all.
        FakeHost host; host.cancelAtMs = 0;
        require(run(host) == ApprovalOutcome::Cancelled && host.actions.isEmpty());
    }
    {   // A lost cancel request does not hide the user's cancel.
        FakeHost host; host.cancelAtMs = 1000 + 300; host.cancelThrows = true;
        require(run(host) == ApprovalOutcome::Cancelled && host.actions.last() == "cancel");
    }
    {   // Transport failure while polling: withdraw, then rethrow to the session.
        FakeHost host; host.throwOnRequest = 2;
        bool thrown = false;
        try { run(host); } catch (const std::runtime_error&) { thrown = true; }
        require(thrown && (host.actions == QStringList{"start", "status", "status", "cancel"}));
    }
    {   // Transport failure on start: rethrown; best-effort cancel is harmless.
        FakeHost host; host.throwOnRequest = 0;
        bool thrown = false;
        try { run(host); } catch (const std::runtime_error&) { thrown = true; }
        require(thrown && host.waitingCalls == 0);
    }
}

static void launchRejection() {
    require(office::isHostApprovalRequired(403, QStringLiteral("Host approval required")));
    require(!office::isHostApprovalRequired(403, QStringLiteral("Forbidden")));
    require(!office::isHostApprovalRequired(401, QStringLiteral("Host approval required")));
    require(!office::isHostApprovalRequired(503, QStringLiteral("Host approval required")));
    require(!office::isHostApprovalRequired(403, QString()));

    // 403 is not a refusal: the host wants a fresh, confirmed connection.
    const auto required = office::approvalOutcomeMessage(ApprovalOutcome::ApprovalRequired);
    require(required == QStringLiteral("被控端需要本机确认，请重新连接"));
    require(!required.contains(QStringLiteral("拒绝")));

    // The dialog the host opened on its own is withdrawn with one cancel,
    // and a lost cancel never escapes to the session.
    QStringList sent;
    office::withdrawApprovalRequest([&sent](const QString& action) { sent << action; return QString(); });
    require(sent == QStringList{"cancel"});
    bool escaped = false;
    try {
        office::withdrawApprovalRequest([](const QString&) -> QString { throw std::runtime_error("lost"); });
    } catch (...) { escaped = true; }
    require(!escaped);
    office::withdrawApprovalRequest({});
}

static void bridgeStates() {
    // Approved after the waiting UI: the workbench goes back to "starting".
    require(office::approvalBridgeState(ApprovalOutcome::Proceed, true) == QStringLiteral("starting"));
    require(office::approvalBridgeState(ApprovalOutcome::Proceed, false).isEmpty());
    require(office::approvalBridgeState(ApprovalOutcome::Cancelled, true).isEmpty());
    require(office::approvalBridgeState(ApprovalOutcome::Failed, true).isEmpty());
    require(office::approvalBridgeState(ApprovalOutcome::Denied, false) == QStringLiteral("denied"));
    require(office::approvalBridgeState(ApprovalOutcome::Expired, true) == QStringLiteral("expired"));
    require(office::approvalBridgeState(ApprovalOutcome::TimedOut, true) == QStringLiteral("expired"));
    require(office::approvalBridgeState(ApprovalOutcome::ApprovalRequired, false) ==
            QStringLiteral("approval_required"));
}

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    parser();
    flow();
    launchRejection();
    bridgeStates();
    std::printf("PASS: %d connect-confirm checks (approved, not_required, denied, expired, timeout, invalid XML, cancel, 403, bridge states)\n", checks);
    return 0;
}
