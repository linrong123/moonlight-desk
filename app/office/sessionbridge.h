#pragma once
#include <QObject>
#include <QThread>
#include <atomic>

namespace office {
// IPC must keep working while the session's main thread is inside SDL, not Qt.
class SessionBridge : public QObject {
    Q_OBJECT
public:
    explicit SessionBridge(QObject* parent = nullptr);
    ~SessionBridge();
    static SessionBridge* instance();
    static bool isSessionProcess();
    Q_INVOKABLE void report(const QString& state);
    Q_INVOKABLE void setCleanupRequired(bool required) { m_CleanupRequired = required; }
    void showManager();
    bool stopRequested() const { return m_Stop.load(); }
    bool takeFocus() { return m_Focus.exchange(false); }
signals:
    void stop();
    void focus();
protected:
    bool eventFilter(QObject* object, QEvent* event) override;
private:
    QThread m_Thread;
    QObject* m_Worker = nullptr;
    std::atomic_bool m_Stop{false};
    std::atomic_bool m_Focus{false};
    bool m_CleanupRequired = false;
    static SessionBridge* s_Instance;
};
}
