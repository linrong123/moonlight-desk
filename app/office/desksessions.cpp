#include "desksessions.h"
#include <QCoreApplication>
#include <QEvent>
#include <QLocalServer>
#include <QLocalSocket>
#include <QProcess>
#include <QProcessEnvironment>
#include <QTimer>
#include <QTemporaryDir>
#include <QDir>
#include <QFile>
#include <memory>

namespace office {
struct DeskSessions::Child {
    std::unique_ptr<QTemporaryDir> directory;
    QProcess* process = nullptr;
    QLocalServer* server = nullptr;
    QLocalSocket* socket = nullptr;
    QString name;
    QString state = QStringLiteral("正在连接");
    QByteArray pending;
    bool stopping = false;
    bool focusPending = false;
    bool controlFailed = false;
};

DeskSessions::DeskSessions(QObject* parent, QString program)
    : QObject(parent), m_Program(program.isEmpty() ? QCoreApplication::applicationFilePath() : program) {
    QCoreApplication::instance()->installEventFilter(this);
}

bool DeskSessions::isActive(const QString& uuid) const { return m_Sessions.contains(uuid); }
QString DeskSessions::status(const QString& uuid) const {
    const auto child = m_Sessions.value(uuid);
    return child ? child->state : m_LastStatus.value(uuid);
}
void DeskSessions::changed() { ++m_Revision; emit revisionChanged(); }

bool DeskSessions::open(const QString& uuid, const QString& name) {
    if (m_Quitting || uuid.isEmpty()) return false;
    if (isActive(uuid)) { focus(uuid); return true; }
    if (m_Prepare && !m_Prepare(uuid)) {
        emit launchError(QStringLiteral("设备信息尚未准备好，请确认电脑在线并已完成配对后重试。"));
        return false;
    }
    auto child = QSharedPointer<Child>::create();
    child->name = name;
    child->server = new QLocalServer(this);
    child->server->setSocketOptions(QLocalServer::UserAccessOption);
    // Directory access also protects platforms ignoring socket-file modes.
    child->directory = std::make_unique<QTemporaryDir>(QDir::tempPath() + "/desk-session-XXXXXX");
    if (!child->directory->isValid() || !QFile::setPermissions(child->directory->path(),
            QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner)) {
        child->server->deleteLater();
        emit launchError(QStringLiteral("无法创建会话的私有临时目录。"));
        return false;
    }
    const auto endpoint = child->directory->path() + "/ipc";
    if (!child->server->listen(endpoint)) {
        child->server->deleteLater();
        emit launchError(QStringLiteral("无法创建独立桌面窗口，请稍后重试。"));
        return false;
    }
    child->process = new QProcess(this);
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert("MOONLIGHT_DESK_SESSION", endpoint);
    child->process->setProcessEnvironment(env);
    child->process->setProgram(m_Program);
    // No passwords, host addresses or command shell. Saved UUID selects the
    // paired host. Each process reads the same identity but never writes hosts.
    child->process->setArguments({"stream", "--display-mode", "windowed",
        "--no-quit-after", "--no-background-gamepad", "--mute-on-focus-loss", uuid, "Desktop"});
    child->process->setStandardOutputFile(QProcess::nullDevice());
    child->process->setStandardErrorFile(QProcess::nullDevice());
    connect(child->server, &QLocalServer::newConnection, this, [this, child] {
        while (child->server->hasPendingConnections()) {
            auto* socket = child->server->nextPendingConnection();
            if (child->socket) { socket->deleteLater(); continue; }
            child->socket = socket;
            connect(socket, &QLocalSocket::disconnected, this, [this, child] {
                if (!child->stopping) {
                    child->state = QStringLiteral("正在结束连接");
                    changed();
                }
                // The child normally cancels itself when this pipe closes.
                // A single SIGTERM is the upstream graceful fallback on macOS.
#ifdef Q_OS_UNIX
                QTimer::singleShot(5000, child->process, [this, child] {
                    if (child->process->state() != QProcess::NotRunning) {
                        child->controlFailed = true;
                        child->stopping = true;
                        child->state = QStringLiteral("控制通道中断，正在断开");
                        changed();
                        child->process->terminate();
                    }
                });
#endif
            });
            connect(socket, &QLocalSocket::readyRead, this, [this, child] {
                child->pending += child->socket->readAll();
                if (child->pending.size() > 4096) { child->socket->abort(); return; }
                while (child->pending.contains('\n')) {
                    const auto at = child->pending.indexOf('\n');
                    const auto state = child->pending.left(at);
                    child->pending.remove(0, at + 1);
                    if (state == "manager") { emit showManager(); continue; }
                    if (child->stopping) continue;
                    const QString denied = QStringLiteral("被控端拒绝了连接");
                    const QString expired = QStringLiteral("被控端未在 60 秒内确认");
                    if (state == "connected") child->state = QStringLiteral("已连接");
                    else if (state == "recovering") child->state = QStringLiteral("正在重连");
                    else if (state == "error") {
                        // Keep the specific approval result the session sent just before.
                        if (child->state == denied || child->state == expired) continue;
                        child->state = QStringLiteral("连接未成功，请查看连接窗口");
                    }
                    else if (state == "starting") child->state = QStringLiteral("正在连接");
                    else if (state == "approval") child->state = QStringLiteral("正在等待被控端确认…");
                    else if (state == "denied") child->state = denied;
                    else if (state == "expired") child->state = expired;
                    else continue;
                    changed();
                }
            });
            if (child->stopping) command(child, "stop\n");
            else if (child->focusPending) command(child, "focus\n");
        }
    });
    connect(child->process, &QProcess::errorOccurred, this, [this, uuid, child](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) finish(uuid, child, true);
    });
    connect(child->process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this, uuid, child](int code, QProcess::ExitStatus exit) {
            finish(uuid, child, code != 0 || exit == QProcess::CrashExit);
        });
    m_Sessions.insert(uuid, child);
    m_LastStatus.remove(uuid);
    emit countChanged();
    changed();
    child->process->start();
    QTimer::singleShot(30000, child->process, [this, child] {
        if (!child->socket && child->process->state() != QProcess::NotRunning) {
            child->controlFailed = true;
            child->stopping = true;
            child->state = QStringLiteral("连接窗口未响应，正在断开");
            changed();
#ifdef Q_OS_UNIX
            child->process->terminate();
#endif
        }
    });
    return true;
}

void DeskSessions::command(const QSharedPointer<Child>& child, const QByteArray& command) {
    if (child->socket && child->socket->state() == QLocalSocket::ConnectedState) {
        child->socket->write(command);
        child->socket->flush();
    }
}
void DeskSessions::focus(const QString& uuid) {
    const auto child = m_Sessions.value(uuid);
    if (!child || child->stopping) return;
    child->focusPending = true;
    command(child, "focus\n");
}
void DeskSessions::disconnectSession(const QString& uuid) {
    const auto child = m_Sessions.value(uuid);
    if (!child) return;
    child->stopping = true;
    child->state = QStringLiteral("正在断开");
    command(child, "stop\n");
    changed();
}
void DeskSessions::stopAll() {
    const auto uuids = m_Sessions.keys();
    for (const auto& uuid : uuids) disconnectSession(uuid);
}
void DeskSessions::finish(const QString& uuid, const QSharedPointer<Child>& child, bool failed) {
    if (m_Sessions.value(uuid) != child) return;
    failed = failed || child->controlFailed;
    m_LastStatus.insert(uuid, failed ? QStringLiteral("连接窗口意外退出") : QStringLiteral("已断开"));
    m_Sessions.remove(uuid);
    child->server->close();
    child->server->deleteLater();
    child->process->deleteLater();
    emit countChanged();
    changed();
    if (failed) emit launchError(QStringLiteral("%1 的连接窗口未能运行；其他连接不受影响。").arg(child->name));
    if (m_Quitting && m_Sessions.isEmpty()) QTimer::singleShot(0, qApp, &QCoreApplication::quit);
}
bool DeskSessions::eventFilter(QObject* object, QEvent* event) {
    if (object == qApp && event->type() == QEvent::Quit && !m_Sessions.isEmpty()) {
        m_Quitting = true;
        stopAll();
        // Never destroy a running QProcess (which would kill it before cleanup).
        return true;
    }
    return QObject::eventFilter(object, event);
}
}
