/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * ScreenLockMonitor unit tests across two coverage planes:
 *
 *   1. setLocked's re-emit guard — invoked via QMetaObject::invokeMethod
 *      against ScreenLockMonitor's private onActiveChanged slot. No
 *      DBus involvement; verifies the state-machine contract in
 *      isolation.
 *
 *   2. The DBus subscription itself — spawns
 *      tests/fixtures/dbusmock/screensaver.py which stands up a private
 *      session bus + a mock org.freedesktop.ScreenSaver service, then
 *      drives ScreenLockMonitor against it and verifies that GetActive
 *      seeding + ActiveChanged signal propagation actually reach the
 *      `locked` property.
 *
 * The dbusmock subgroup auto-skips if python3-dbusmock isn't available
 * on the runner (the CMake gate doesn't unconditionally require it).
 */
#include "screenlockmonitor.h"

#include <QDBusConnection>
#include <QProcess>
#include <QSignalSpy>
#include <QTest>

class TestScreenLockMonitor : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initialState_isUnlocked()
    {
        ScreenLockMonitor m;
        QVERIFY(!m.locked());
    }

    void onActiveChanged_true_emitsAndUpdates()
    {
        ScreenLockMonitor m;
        QSignalSpy spy(&m, &ScreenLockMonitor::lockedChanged);
        QVERIFY(QMetaObject::invokeMethod(&m, "onActiveChanged",
                                           Q_ARG(bool, true)));
        QCOMPARE(m.locked(), true);
        QCOMPARE(spy.count(), 1);
    }

    void onActiveChanged_falseFromFalse_noEmit()
    {
        ScreenLockMonitor m;   // starts unlocked
        QSignalSpy spy(&m, &ScreenLockMonitor::lockedChanged);
        QVERIFY(QMetaObject::invokeMethod(&m, "onActiveChanged",
                                           Q_ARG(bool, false)));
        QCOMPARE(spy.count(), 0);
    }

    void onActiveChanged_redundantTrue_noSecondEmit()
    {
        ScreenLockMonitor m;
        QSignalSpy spy(&m, &ScreenLockMonitor::lockedChanged);
        QMetaObject::invokeMethod(&m, "onActiveChanged", Q_ARG(bool, true));
        QMetaObject::invokeMethod(&m, "onActiveChanged", Q_ARG(bool, true));
        QMetaObject::invokeMethod(&m, "onActiveChanged", Q_ARG(bool, true));
        QCOMPARE(spy.count(), 1);
        QCOMPARE(m.locked(), true);
    }

    void onActiveChanged_redundantFalse_noEmitAfterFirstTrue()
    {
        ScreenLockMonitor m;
        QSignalSpy spy(&m, &ScreenLockMonitor::lockedChanged);
        QMetaObject::invokeMethod(&m, "onActiveChanged", Q_ARG(bool, true));
        QMetaObject::invokeMethod(&m, "onActiveChanged", Q_ARG(bool, false));
        QMetaObject::invokeMethod(&m, "onActiveChanged", Q_ARG(bool, false));
        QMetaObject::invokeMethod(&m, "onActiveChanged", Q_ARG(bool, false));
        QCOMPARE(spy.count(), 2);   // one true→, one false-back-
        QCOMPARE(m.locked(), false);
    }

    void rapidToggle_emitsPerTransition()
    {
        ScreenLockMonitor m;
        QSignalSpy spy(&m, &ScreenLockMonitor::lockedChanged);
        const bool seq[] = {true, false, true, false, true, false};
        for (const bool v : seq) {
            QMetaObject::invokeMethod(&m, "onActiveChanged", Q_ARG(bool, v));
        }
        QCOMPARE(spy.count(), 6);
        QCOMPARE(m.locked(), false);
    }

    void rapidToggleWithDupes_emitsPerRealTransition()
    {
        ScreenLockMonitor m;
        QSignalSpy spy(&m, &ScreenLockMonitor::lockedChanged);
        // Two trues, then back-to-false, then redundant falses, then true.
        // Real transitions: f→t (1), t→f (2), f→t (3). That's 3 emits.
        const bool seq[] = {true, true, false, false, false, true};
        for (const bool v : seq) {
            QMetaObject::invokeMethod(&m, "onActiveChanged", Q_ARG(bool, v));
        }
        QCOMPARE(spy.count(), 3);
        QCOMPARE(m.locked(), true);
    }

    void constructor_withInjectedBus_doesNotThrow()
    {
        // The injected-bus constructor (Phase 1 refactor) lets tests pass
        // a controllable DBus connection. Even with the session bus and
        // no ScreenSaver service available, the constructor must complete
        // without error (subscribe() best-effort logs a warning at most).
        ScreenLockMonitor m{QDBusConnection::sessionBus()};
        QVERIFY(!m.locked());
    }

    void locked_property_initiallyFalse_thenTrueAfterFirstTrue()
    {
        ScreenLockMonitor m;
        QCOMPARE(m.locked(), false);
        QMetaObject::invokeMethod(&m, "onActiveChanged", Q_ARG(bool, true));
        QCOMPARE(m.locked(), true);
    }

    // ─────────────────────────────────────────────────────────────
    //  DBus-driven subgroup. Spawns tests/fixtures/dbusmock/screensaver.py,
    //  reads its bus address, connects ScreenLockMonitor to that private
    //  bus, drives the mock state via the fixture's stdin protocol.
    // ─────────────────────────────────────────────────────────────

    void dbus_seedsLockedTrueFromGetActive()
    {
        // The fixture's set_active(...) wires GetActive's return value.
        // Set it to true before constructing ScreenLockMonitor, then
        // verify the constructor's async-seed pulls it through.
        QProcess fixture;
        if (!startFixture(fixture)) {
            QSKIP("dbusmock fixture failed to start "
                  "(install python3-dbusmock)");
        }
        const QString busAddr = readBusAddress(fixture);
        QVERIFY(!busAddr.isEmpty());

        // Tell the mock to report locked=true BEFORE the monitor connects.
        sendCommand(fixture, "active true");
        QVERIFY(waitForOk(fixture));

        const QString busName = QStringLiteral("ifp-test-seed-true");
        QDBusConnection bus = QDBusConnection::connectToBus(busAddr, busName);
        QVERIFY(bus.isConnected());

        ScreenLockMonitor monitor(bus);
        QSignalSpy spy(&monitor, &ScreenLockMonitor::lockedChanged);

        // The constructor's GetActive is async; pump the event loop
        // until the signal fires or the timeout elapses.
        QTRY_VERIFY_WITH_TIMEOUT(monitor.locked() == true, 5000);
        QVERIFY(spy.count() >= 1);

        QDBusConnection::disconnectFromBus(busName);
        stopFixture(fixture);
    }

    void dbus_seedsLockedFalseFromGetActive()
    {
        // Default state of the mock is already false; just verify the
        // monitor stays unlocked and emits no signal (no transition).
        QProcess fixture;
        if (!startFixture(fixture)) {
            QSKIP("dbusmock fixture failed to start");
        }
        const QString busAddr = readBusAddress(fixture);
        QVERIFY(!busAddr.isEmpty());

        const QString busName = QStringLiteral("ifp-test-seed-false");
        QDBusConnection bus = QDBusConnection::connectToBus(busAddr, busName);
        QVERIFY(bus.isConnected());

        ScreenLockMonitor monitor(bus);
        QSignalSpy spy(&monitor, &ScreenLockMonitor::lockedChanged);

        // Give the async GetActive a chance to land.
        QTest::qWait(800);
        QCOMPARE(monitor.locked(), false);
        QCOMPARE(spy.count(), 0);

        QDBusConnection::disconnectFromBus(busName);
        stopFixture(fixture);
    }

    void dbus_picksUpActiveChangedSignal()
    {
        QProcess fixture;
        if (!startFixture(fixture)) {
            QSKIP("dbusmock fixture failed to start");
        }
        const QString busAddr = readBusAddress(fixture);
        QVERIFY(!busAddr.isEmpty());

        const QString busName = QStringLiteral("ifp-test-signal");
        QDBusConnection bus = QDBusConnection::connectToBus(busAddr, busName);
        QVERIFY(bus.isConnected());

        ScreenLockMonitor monitor(bus);
        QSignalSpy spy(&monitor, &ScreenLockMonitor::lockedChanged);

        // Wait for the initial async seed (false) to land so we don't
        // race with it. Then drive transitions and verify each.
        QTest::qWait(500);
        QCOMPARE(monitor.locked(), false);

        sendCommand(fixture, "active true");
        QVERIFY(waitForOk(fixture));
        QTRY_VERIFY_WITH_TIMEOUT(monitor.locked() == true, 3000);

        sendCommand(fixture, "active false");
        QVERIFY(waitForOk(fixture));
        QTRY_VERIFY_WITH_TIMEOUT(monitor.locked() == false, 3000);

        sendCommand(fixture, "active true");
        QVERIFY(waitForOk(fixture));
        QTRY_VERIFY_WITH_TIMEOUT(monitor.locked() == true, 3000);

        // Three real transitions → three lockedChanged emits.
        QCOMPARE(spy.count(), 3);

        QDBusConnection::disconnectFromBus(busName);
        stopFixture(fixture);
    }

    void dbus_redundantActiveChanged_doesNotReEmit()
    {
        QProcess fixture;
        if (!startFixture(fixture)) {
            QSKIP("dbusmock fixture failed to start");
        }
        const QString busAddr = readBusAddress(fixture);

        const QString busName = QStringLiteral("ifp-test-redundant");
        QDBusConnection bus = QDBusConnection::connectToBus(busAddr, busName);
        ScreenLockMonitor monitor(bus);
        QSignalSpy spy(&monitor, &ScreenLockMonitor::lockedChanged);

        QTest::qWait(500);
        sendCommand(fixture, "active true");
        QVERIFY(waitForOk(fixture));
        QTRY_VERIFY_WITH_TIMEOUT(monitor.locked() == true, 3000);
        const int afterFirst = spy.count();

        // Two more "active true" — these emit ActiveChanged(true) on
        // the bus but the monitor's setLocked guard should drop them.
        sendCommand(fixture, "active true");
        QVERIFY(waitForOk(fixture));
        sendCommand(fixture, "active true");
        QVERIFY(waitForOk(fixture));
        QTest::qWait(500);

        QCOMPARE(spy.count(), afterFirst);

        QDBusConnection::disconnectFromBus(busName);
        stopFixture(fixture);
    }

private:
    // ─── dbusmock fixture helpers ────────────────────────────────
    bool startFixture(QProcess &proc)
    {
        const QByteArray script = qgetenv("IFRAME_DBUSMOCK_SCREENSAVER");
        if (script.isEmpty()) return false;
        proc.setProgram(QStringLiteral("python3"));
        proc.setArguments({QString::fromLocal8Bit(script)});
        proc.start();
        return proc.waitForStarted(5000);
    }

    QString readBusAddress(QProcess &proc)
    {
        // Wait for the "BUS <address>" preamble.
        const qint64 deadline = QDateTime::currentMSecsSinceEpoch() + 10000;
        QByteArray buf;
        while (QDateTime::currentMSecsSinceEpoch() < deadline) {
            if (proc.waitForReadyRead(500)) buf.append(proc.readAllStandardOutput());
            const int nl = buf.indexOf('\n');
            if (nl >= 0) {
                const QByteArray line = buf.left(nl).trimmed();
                buf = buf.mid(nl + 1);
                if (line.startsWith("BUS ")) {
                    // Preserve any leftover bytes for the OK/ERR reader.
                    m_stdoutBuf = buf;
                    return QString::fromLocal8Bit(line.mid(4));
                }
            }
        }
        return QString();
    }

    void sendCommand(QProcess &proc, const char *cmd)
    {
        proc.write(cmd);
        proc.write("\n");
        proc.waitForBytesWritten(2000);
    }

    bool waitForOk(QProcess &proc)
    {
        // The fixture prints "OK" or "ERR ..." after each command.
        const qint64 deadline = QDateTime::currentMSecsSinceEpoch() + 5000;
        QByteArray &buf = m_stdoutBuf;
        while (QDateTime::currentMSecsSinceEpoch() < deadline) {
            if (proc.waitForReadyRead(500)) buf.append(proc.readAllStandardOutput());
            const int nl = buf.indexOf('\n');
            if (nl >= 0) {
                const QByteArray line = buf.left(nl).trimmed();
                buf = buf.mid(nl + 1);
                if (line == "OK") return true;
                if (line.startsWith("ERR")) return false;
            }
        }
        return false;
    }

    void stopFixture(QProcess &proc)
    {
        if (proc.state() == QProcess::Running) {
            proc.write("quit\n");
            if (!proc.waitForFinished(3000)) proc.kill();
        }
    }

    QByteArray m_stdoutBuf;
};

QTEST_GUILESS_MAIN(TestScreenLockMonitor)
#include "tst_screenlockmonitor.moc"
