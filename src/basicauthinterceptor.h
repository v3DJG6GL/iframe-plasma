/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#pragma once

#include <QHash>
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

    Q_INVOKABLE void setCredential(const QString &host, const QString &user, const QString &password);
    // Set a fully-formed Authorization header value (e.g. "Basic <base64>" or
    // "Bearer <token>") without any encoding. Overrides setCredential for the
    // same host.
    Q_INVOKABLE void setRawHeader(const QString &host, const QString &headerValue);
    Q_INVOKABLE void clearCredential(const QString &host);
    Q_INVOKABLE void clearAll();
    Q_INVOKABLE QStringList hosts() const;

    // Profile-aware façade: register one profile's credential against many
    // hosts in a single call. `authType` is "basic" | "bearer" | "raw":
    //   - "basic":  synthesizes "Basic " + base64(user:secret)
    //   - "bearer": synthesizes "Bearer " + secret
    //   - "raw":    uses `secret` as-is for the Authorization header
    // m_hostOwner tracks which profileId each host belongs to so clearProfile
    // can selectively wipe just that profile's hosts.
    Q_INVOKABLE void applyProfile(const QString &profileId,
                                  const QString &authType,
                                  const QString &username,
                                  const QString &secret,
                                  const QStringList &hosts);
    Q_INVOKABLE void clearProfile(const QString &profileId);

    // QML cannot assign to WebEngineProfile.urlRequestInterceptor directly
    // (no Q_PROPERTY), so this method does the cast + attach for us.
    // Pass true to detach, false to attach.
    Q_INVOKABLE bool attachTo(QObject *profile);
    Q_INVOKABLE bool detachFrom(QObject *profile);

    void interceptRequest(QWebEngineUrlRequestInfo &info) override;

private:
    // host (lowercased) -> precomputed "Basic <base64>" / "Bearer …" / raw header value
    QHash<QString, QByteArray> m_headers;
    // host (lowercased) -> profileId, so clearProfile can wipe only that
    // profile's host registrations.
    QHash<QString, QString> m_hostOwner;
};
