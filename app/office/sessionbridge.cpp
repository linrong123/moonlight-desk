#include "sessionbridge.h"
#include <QLocalSocket>
#include <QTimer>
#include <QCoreApplication>
#include <QEvent>
#include <QVariant>

namespace office {
SessionBridge* SessionBridge::s_Instance = nullptr;
SessionBridge* SessionBridge::instance() { return s_Instance; }
bool SessionBridge::isSessionProcess() { return !qEnvironmentVariableIsEmpty("MOONLIGHT_DESK_SESSION"); }

SessionBridge::SessionBridge(QObject* parent) : QObject(parent) {
    s_Instance = this;
    if (!isSessionProcess()) return;
    qApp->installEventFilter(this);
    auto* socket = new QLocalSocket;
    m_Worker = socket;
    socket->moveToThread(&m_Thread);
    connect(&m_Thread, &QThread::finished, socket, &QObject::deleteLater);
    connect(&m_Thread, &QThread::started, socket, [socket] {
        socket->connectToServer(qEnvironmentVariable("MOONLIGHT_DESK_SESSION"));
    });
    connect(socket, &QLocalSocket::connected, socket, [socket] {
        const auto state = socket->property("deskState").toByteArray();
        socket->write(state.isEmpty() ? QByteArray("starting\n") : state + '\n');
    });
    connect(socket, &QLocalSocket::disconnected, socket, [this] { m_Stop = true; });
    connect(socket, &QLocalSocket::errorOccurred, socket, [this](QLocalSocket::LocalSocketError) { m_Stop = true; });
    connect(socket, &QLocalSocket::readyRead, socket, [this, socket, pending = QByteArray()]() mutable {
        pending += socket->readAll();
        if (pending.size() > 4096) { socket->abort(); return; }
        while (pending.contains('\n')) {
            const auto at = pending.indexOf('\n');
            const auto command = pending.left(at);
            pending.remove(0, at + 1);
            if (command == "stop") m_Stop = true;
            else if (command == "focus") m_Focus = true;
        }
    });
    m_Thread.start();
    // During search, recovery and dialogs Qt is active. During streaming,
    // Session::officePollUi consumes the same atomics on the SDL main thread.
    auto* timer = new QTimer(this);
    connect(timer, &QTimer::timeout, this, [this, stopEmitted = false]() mutable {
        if (m_Stop && !stopEmitted) { stopEmitted = true; emit stop(); }
        if (takeFocus()) emit focus();
    });
    timer->start(50);
}
SessionBridge::~SessionBridge() {
    m_Thread.quit();
    m_Thread.wait();
    s_Instance = nullptr;
}
bool SessionBridge::eventFilter(QObject* object, QEvent* event) {
    if (object == qApp && event->type() == QEvent::Quit && m_CleanupRequired) {
        m_Stop = true;
        return true;
    }
    return QObject::eventFilter(object, event);
}
void SessionBridge::report(const QString& state) {
    if (!m_Worker) return;
    // Status enum only: never forward logging, pairing codes or frame data.
    if (state != "starting" && state != "connected" && state != "recovering" && state != "error") return;
    QMetaObject::invokeMethod(m_Worker, [socket = static_cast<QLocalSocket*>(m_Worker), state] {
        socket->setProperty("deskState", state.toUtf8());
        if (socket->state() == QLocalSocket::ConnectedState) socket->write(state.toUtf8() + '\n');
    }, Qt::QueuedConnection);
}
void SessionBridge::showManager() {
    if (!m_Worker) return;
    QMetaObject::invokeMethod(m_Worker, [socket = static_cast<QLocalSocket*>(m_Worker)] {
        if (socket->state() == QLocalSocket::ConnectedState) socket->write("manager\n");
    }, Qt::QueuedConnection);
}
}
