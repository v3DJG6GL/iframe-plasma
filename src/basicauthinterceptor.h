/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#pragma once

#include <QByteArray>
#include <QHash>
#include <QReadWriteLock>
#include <QString>
#include <QStringList>
#include <QWebEngineUrlRequestInterceptor>
#include <optional>
#include <qqmlregistration.h>

namespace iframeplasma::auth {

// Canonicalise a request host to the WHATWG `URL.host` form that the QML
// registration side emits (`new URL(t.url).host`): bare host for default
// scheme ports (http→80, https→443), `host:port` otherwise. IPv6 literals
// get their brackets re-added since `QUrl::host()` strips them. Used by
// both BasicAuthInterceptor::interceptRequest() and the unit tests.
QString canonicalizeHost(const QString &rawHost, const QString &scheme, int port);

// Build the Authorization header value for one profile. Returns nullopt on
// validation failure and (if errorReason is non-null) fills it with one of:
//   "empty-secret", "colon-in-basic-username", "control-in-username",
//   "control-in-header", "unknown-authtype".
// "none" is a passthrough profile and is the caller's responsibility to
// short-circuit before calling this function.
std::optional<QByteArray> buildAuthHeader(const QString &authType,
                                          const QString &username,
                                          const QString &secret,
                                          QString *errorReason = nullptr);

} // namespace iframeplasma::auth

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

    // Read-only snapshot of currently-registered (host → header) entries.
    // QWebEngineUrlRequestInfo is `final` and has no public constructor, so
    // unit tests cannot drive interceptRequest() directly; they verify
    // applyProfile/clearAll state through this accessor instead. Cheap
    // (one QHash COW) and locked under the read side of m_headersLock.
    QHash<QString, QByteArray> headersSnapshot() const;

private:
    // host (lowercased) -> precomputed "Basic <base64>" / "Bearer …" / raw header value.
    // interceptRequest() runs on Chromium's IO thread; applyProfile()/clearAll()
    // run on the UI thread — guard the hash with a read/write lock.
    QHash<QString, QByteArray> m_headers;
    mutable QReadWriteLock m_headersLock;
};
