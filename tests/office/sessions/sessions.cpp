#include "office/desksessions.h"
#include "office/sessionbridge.h"
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QProcess>
#include <QSignalSpy>
#include <QTest>
#include <QTimer>
#include <QLocalServer>
#include <QLocalSocket>
#include <QUuid>

class SessionsTest : public QObject {
    Q_OBJECT
private slots:
    void independentChildren() {
        office::DeskSessions manager;
        QVERIFY(manager.open("host-a", "A"));
        QVERIFY(manager.open("host-b", "B"));
        QCOMPARE(manager.count(), 2);
        QTRY_COMPARE_WITH_TIMEOUT(manager.status("host-a"), QString("已连接"), 5000);
        QTRY_COMPARE_WITH_TIMEOUT(manager.status("host-b"), QString("已连接"), 5000);
        // Repeated click raises the existing child, never starts a third stream.
        QVERIFY(manager.open("host-a", "A"));
        QCOMPARE(manager.count(), 2);
        manager.disconnectSession("host-a");
        QTRY_COMPARE_WITH_TIMEOUT(manager.count(), 1, 5000);
        QVERIFY(manager.isActive("host-b"));
        QCOMPARE(manager.status("host-b"), QString("已连接"));
        manager.stopAll();
        QTRY_COMPARE_WITH_TIMEOUT(manager.count(), 0, 5000);
    }
    void cancelBeforeHandshake() {
        office::DeskSessions manager;
        QVERIFY(manager.open("early", "A"));
        manager.disconnectSession("early");
        QTRY_COMPARE_WITH_TIMEOUT(manager.count(), 0, 5000);
    }
    void childClosesNormally() {
        office::DeskSessions manager;
        QSignalSpy errors(&manager, &office::DeskSessions::launchError);
        QVERIFY(manager.open("normal-close", "A"));
        QTRY_COMPARE_WITH_TIMEOUT(manager.count(), 0, 5000);
        QCOMPARE(errors.count(), 0);
        QCOMPARE(manager.status("normal-close"), QString("已断开"));
    }
    void bridgeCachesEarlyStateAndStopsOnPipeLoss() {
        QLocalServer server;
        const auto endpoint = "desk-test-" + QUuid::createUuid().toString(QUuid::WithoutBraces);
        QVERIFY(server.listen(endpoint));
        qputenv("MOONLIGHT_DESK_SESSION", endpoint.toUtf8());
        {
            office::SessionBridge bridge;
            bridge.report("connected");
            QTRY_VERIFY_WITH_TIMEOUT(server.hasPendingConnections(), 5000);
            auto* peer = server.nextPendingConnection();
            QByteArray received;
            QTRY_VERIFY_WITH_TIMEOUT((received += peer->readAll()).contains("connected\n"), 5000);
            peer->abort();
            QTRY_VERIFY_WITH_TIMEOUT(bridge.stopRequested(), 5000);
        }
        qunsetenv("MOONLIGHT_DESK_SESSION");
    }
    void childQuitWaitsForCleanup() {
        office::DeskSessions manager;
        QVERIFY(manager.open("cleanup", "A"));
        QTRY_COMPARE_WITH_TIMEOUT(manager.count(), 0, 5000);
        QCOMPARE(manager.status("cleanup"), QString("已断开"));
    }
    void failureDoesNotCloseOtherHost() {
        office::DeskSessions manager;
        QSignalSpy errors(&manager, &office::DeskSessions::launchError);
        QVERIFY(manager.open("host-b", "B"));
        QTRY_COMPARE_WITH_TIMEOUT(manager.status("host-b"), QString("已连接"), 5000);
        QVERIFY(manager.open("crash", "C"));
        QTRY_VERIFY_WITH_TIMEOUT(!manager.isActive("crash"), 5000);
        QCOMPARE(errors.count(), 1);
        QVERIFY(manager.isActive("host-b"));
        manager.stopAll();
        QTRY_COMPARE_WITH_TIMEOUT(manager.count(), 0, 5000);
    }
    void failedStartAndPreparation() {
        office::DeskSessions manager(nullptr, "/no/such/moonlight-desk-test-program");
        QSignalSpy errors(&manager, &office::DeskSessions::launchError);
        manager.setPrepareLaunch([](const QString&) { return false; });
        QVERIFY(!manager.open("host-a", "A"));
        QCOMPARE(manager.count(), 0);
        manager.setPrepareLaunch([](const QString&) { return true; });
        QVERIFY(manager.open("host-a", "A"));
        QTRY_COMPARE_WITH_TIMEOUT(manager.count(), 0, 5000);
        QCOMPARE(errors.count(), 2);
    }
    void bridgeWorksWhileMainLoopBlocked() {
        office::DeskSessions manager;
        QVERIFY(manager.open("blocked", "SDL simulation"));
        QTRY_COMPARE_WITH_TIMEOUT(manager.status("blocked"), QString("已连接"), 5000);
        manager.disconnectSession("blocked");
        // The fake SDL loop consumes bridge atomics without processing Qt events.
        QTRY_COMPARE_WITH_TIMEOUT(manager.count(), 0, 5000);
    }
    void quitWaitsForChildren() {
        QProcess helper;
        helper.start(QCoreApplication::applicationFilePath(), {"test-manager-quit"});
        QVERIFY(helper.waitForFinished(10000));
        QCOMPARE(helper.exitStatus(), QProcess::NormalExit);
        QCOMPARE(helper.exitCode(), 0);
    }
};

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    if (app.arguments().contains("stream")) {
        office::SessionBridge bridge;
        QObject::connect(&bridge, &office::SessionBridge::stop, &app, &QCoreApplication::quit);
        if (app.arguments().contains("cleanup")) {
            bridge.setCleanupRequired(true);
            QObject::connect(&bridge, &office::SessionBridge::stop, &app, [&] {
                QTimer::singleShot(50, &app, [&] { bridge.setCleanupRequired(false); app.quit(); });
            });
            QTimer::singleShot(100, &app, &QCoreApplication::quit);
        } else if (app.arguments().contains("normal-close")) {
            QTimer::singleShot(150, &app, &QCoreApplication::quit);
        } else if (app.arguments().contains("crash")) {
            QTimer::singleShot(50, &app, [] { QCoreApplication::exit(7); });
        } else if (app.arguments().contains("blocked")) {
            QTimer::singleShot(100, &app, [&] {
                bridge.report("connected");
                QElapsedTimer timer;
                timer.start();
                while (!bridge.stopRequested() && timer.elapsed() < 4000) QThread::msleep(5);
                app.exit(bridge.stopRequested() ? 0 : 9);
            });
        } else {
            QTimer::singleShot(100, &bridge, [&] { bridge.report("connected"); });
        }
        return app.exec();
    }
    if (app.arguments().contains("test-manager-quit")) {
        office::DeskSessions manager;
        manager.open("host-a", "A");
        manager.open("host-b", "B");
        QTimer::singleShot(200, &app, &QCoreApplication::quit);
        const auto result = app.exec();
        return manager.count() == 0 ? result : 10;
    }
    SessionsTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "sessions.moc"
