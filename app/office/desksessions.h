#pragma once

#include <QObject>
#include <QHash>
#include <QSharedPointer>
#include <functional>

namespace office {
// Each child owns one unmodified, process-global Moonlight streaming engine.
class DeskSessions : public QObject {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
public:
    explicit DeskSessions(QObject* parent = nullptr, QString program = {});
    int count() const { return m_Sessions.size(); }
    int revision() const { return m_Revision; }
    void setPrepareLaunch(std::function<bool(const QString&)> prepare) { m_Prepare = std::move(prepare); }
    Q_INVOKABLE bool isActive(const QString& uuid) const;
    Q_INVOKABLE QString status(const QString& uuid) const;
    Q_INVOKABLE bool open(const QString& uuid, const QString& name);
    Q_INVOKABLE void focus(const QString& uuid);
    Q_INVOKABLE void disconnectSession(const QString& uuid);
    Q_INVOKABLE void stopAll();
signals:
    void countChanged();
    void revisionChanged();
    void launchError(QString text);
    void showManager();
protected:
    bool eventFilter(QObject* object, QEvent* event) override;
private:
    struct Child;
    void changed();
    void finish(const QString& uuid, const QSharedPointer<Child>& child, bool failed);
    void command(const QSharedPointer<Child>& child, const QByteArray& command);
    QString m_Program;
    QHash<QString, QSharedPointer<Child>> m_Sessions;
    QHash<QString, QString> m_LastStatus;
    std::function<bool(const QString&)> m_Prepare;
    int m_Revision = 0;
    bool m_Quitting = false;
};
}
