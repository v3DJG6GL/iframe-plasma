/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#pragma once

#include <QDBusConnection>
#include <QObject>
#include <qqmlregistration.h>

// Exposes the desktop screen-lock state to QML as a single `locked` property.
//
// QML has no property that reflects screen-lock (the `visible` chain stays
// true behind the locker), so the widget cannot otherwise pause work while the
// screen is locked. This bridges kscreenlocker's `org.freedesktop.ScreenSaver`
// D-Bus interface (`ActiveChanged` signal) into a QML-bindable bool. If the
// service is unavailable the property simply stays false — the widget keeps
// working, it just doesn't get the lock-time savings.
class ScreenLockMonitor : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool locked READ locked NOTIFY lockedChanged)

public:
    // Production: uses QDBusConnection::sessionBus().
    explicit ScreenLockMonitor(QObject *parent = nullptr);
    // Tests: inject a dbusmock-backed connection (e.g. a per-test private bus
    // name created with QDBusConnection::connectToBus). The bus reference is
    // held only for setup — Qt's connection registry keeps the slot alive
    // for the object's lifetime.
    explicit ScreenLockMonitor(const QDBusConnection &bus, QObject *parent = nullptr);

    bool locked() const { return m_locked; }

Q_SIGNALS:
    void lockedChanged();

private Q_SLOTS:
    void onActiveChanged(bool active);

private:
    void subscribe(const QDBusConnection &bus);
    void setLocked(bool locked);

    bool m_locked = false;
    // Set true on the first ActiveChanged signal arrival. The seed GetActive
    // reply consults this before calling setLocked() so a stale-but-valid
    // reply (the screen-state at the moment the daemon processed the call,
    // before the user locked) can't clobber a real ActiveChanged(true) that
    // landed first.
    bool m_signalReceived = false;
};
