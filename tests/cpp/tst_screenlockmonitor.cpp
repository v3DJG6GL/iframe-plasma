/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * ScreenLockMonitor's state-machine half: setLocked's re-emit guard and
 * the locked → lockedChanged() signal contract. The DBus subscription
 * itself is integration-tested by the live widget on every plasmashell
 * restart (a python-dbusmock-driven C++ unit test would be the proper
 * upstream pattern; it's deferred until python3-dbusmock is available
 * in the build environment).
 *
 * onActiveChanged is a private slot; invoke it via QMetaObject so we
 * don't have to broaden the public API just for tests.
 */
#include "screenlockmonitor.h"

#include <QDBusConnection>
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

    // Note: a queued-connection variant of the re-emit-guard test would
    // race against any real kscreenlocker ActiveChanged signal arriving
    // on the session bus during qWait(), since the default constructor
    // subscribes to the live service. The direct-call cases above
    // cover the same setLocked branches without that interference.
};

QTEST_GUILESS_MAIN(TestScreenLockMonitor)
#include "tst_screenlockmonitor.moc"
