/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#pragma once

#include <QHash>
#include <QReadWriteLock>
#include <QString>
#include <QStringList>
#include <QWebEngineUrlRequestInterceptor>
#include <qqmlregistration.h>

class BasicAuthInterceptor : public QWebEngineUrlRequestInterceptor
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit BasicAuthInterceptor(QObject *parent = nullptr);

    Q_INVOKABLE void clearAll();

    // Profile-aware façade: register one profile's credential against many
    // hosts in a single call. `authType` is "basic" | "bearer" | "raw":
    //   - "basic":  synthesizes "Basic " + base64(user:secret)
    //   - "bearer": synthesizes "Bearer " + secret
    //   - "raw":    uses `secret` as-is for the Authorization header
    Q_INVOKABLE void applyProfile(const QString &profileId,
                                  const QString &authType,
                                  const QString &username,
                                  const QString &secret,
                                  const QStringList &hosts);

    // QML cannot assign to WebEngineProfile.urlRequestInterceptor directly
    // (no Q_PROPERTY), so these do the qobject_cast + attach/detach for us.
    Q_INVOKABLE bool attachTo(QObject *profile);
    Q_INVOKABLE bool detachFrom(QObject *profile);

    void interceptRequest(QWebEngineUrlRequestInfo &info) override;

private:
    // host (lowercased) -> precomputed "Basic <base64>" / "Bearer …" / raw header value.
    // interceptRequest() runs on Chromium's IO thread; applyProfile()/clearAll()
    // run on the UI thread — guard the hash with a read/write lock.
    QHash<QString, QByteArray> m_headers;
    mutable QReadWriteLock m_headersLock;
};
