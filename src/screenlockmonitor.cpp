/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#include "screenlockmonitor.h"

#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>
#include <QLoggingCategory>

Q_LOGGING_CATEGORY(lcIframeLock, "iframeplasma.lock")

namespace
{
// kscreenlocker registers the freedesktop ScreenSaver interface here.
const QString kService = QStringLiteral("org.freedesktop.ScreenSaver");
const QString kInterface = QStringLiteral("org.freedesktop.ScreenSaver");
// Object path used for the explicit GetActive() seed call. The ActiveChanged
// signal is matched on ANY path (see the empty-path connect below), because
// the freedesktop interface is published on both `/ScreenSaver` and
// `/org/freedesktop/ScreenSaver` depending on the implementation.
const QString kPath = QStringLiteral("/org/freedesktop/ScreenSaver");
}

ScreenLockMonitor::ScreenLockMonitor(QObject *parent)
    : ScreenLockMonitor(QDBusConnection::sessionBus(), parent)
{
}

ScreenLockMonitor::ScreenLockMonitor(const QDBusConnection &bus, QObject *parent)
    : QObject(parent)
{
    subscribe(bus);
}

void ScreenLockMonitor::subscribe(const QDBusConnection &busIn)
{
    // QDBusConnection's connect() and asyncCall() are non-const but the
    // class is a cheap handle around a refcounted pimpl, so copy locally.
    QDBusConnection bus = busIn;
    // Subscribe to lock/unlock. An empty object path matches the signal
    // regardless of which path the service publishes it on.
    const bool connected = bus.connect(kService, QString(), kInterface,
                                       QStringLiteral("ActiveChanged"),
                                       this, SLOT(onActiveChanged(bool)));
    if (!connected) {
        qCWarning(lcIframeLock) << "could not subscribe to "
            "ScreenSaver.ActiveChanged; screen-lock pausing disabled";
        return;
    }

    // Seed the current state asynchronously — never block the QML engine on a
    // D-Bus round-trip. A hand-built QDBusMessage is used rather than
    // QDBusInterface because the latter's constructor performs a blocking
    // introspection round-trip before any async call can be issued.
    // Best-effort: if it fails, m_locked stays false and the first
    // ActiveChanged corrects it.
    const QDBusMessage seed = QDBusMessage::createMethodCall(
        kService, kPath, kInterface, QStringLiteral("GetActive"));
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(seed), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *w) {
                const QDBusPendingReply<bool> reply = *w;
                // Race: the user can lock between asyncCall dispatch and the
                // reply landing. If an ActiveChanged(true) arrived first the
                // seed's "false" (the state at the moment the daemon
                // processed our call) would silently overwrite the correct
                // true. Defer to the real signal when we've already heard
                // from it.
                if (reply.isValid() && !m_signalReceived) {
                    setLocked(reply.value());
                }
                w->deleteLater();
            });
}

void ScreenLockMonitor::onActiveChanged(bool active)
{
    m_signalReceived = true;
    setLocked(active);
}

void ScreenLockMonitor::setLocked(bool locked)
{
    if (m_locked == locked) {
        return;
    }
    m_locked = locked;
    Q_EMIT lockedChanged();
}
