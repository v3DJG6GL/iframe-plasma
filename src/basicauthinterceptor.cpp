/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#include "basicauthinterceptor.h"

#include <QByteArray>
#include <QDebug>
#include <QLoggingCategory>
#include <QQuickWebEngineProfile>
#include <QUrl>

Q_LOGGING_CATEGORY(lcIframeAuth, "iframeplasma.auth")

BasicAuthInterceptor::BasicAuthInterceptor(QObject *parent)
    : QWebEngineUrlRequestInterceptor(parent)
{
}

void BasicAuthInterceptor::setCredential(const QString &host, const QString &user, const QString &password)
{
    const QString key = host.toLower();
    if (user.isEmpty() && password.isEmpty()) {
        m_headers.remove(key);
        qCInfo(lcIframeAuth) << "interceptor: cleared credentials for host=" << key;
        return;
    }
    const QByteArray creds = (user + QLatin1Char(':') + password).toUtf8();
    m_headers.insert(key, QByteArrayLiteral("Basic ") + creds.toBase64());
    qCInfo(lcIframeAuth) << "interceptor: registered host=" << key
                         << "user=" << user << "pwLen=" << password.size();
}

void BasicAuthInterceptor::setRawHeader(const QString &host, const QString &headerValue)
{
    const QString key = host.toLower();
    // Strip whitespace and stray surrounding quotes that users sometimes paste
    QString cleaned = headerValue.trimmed();
    if ((cleaned.startsWith(QLatin1Char('"')) && cleaned.endsWith(QLatin1Char('"')))
        || (cleaned.startsWith(QLatin1Char('\'')) && cleaned.endsWith(QLatin1Char('\'')))) {
        cleaned = cleaned.mid(1, cleaned.size() - 2);
    }

    if (cleaned.isEmpty()) {
        m_headers.remove(key);
        qCInfo(lcIframeAuth) << "interceptor: cleared raw header for host=" << key;
        return;
    }
    m_headers.insert(key, cleaned.toUtf8());
    qCInfo(lcIframeAuth) << "interceptor: registered RAW header for host=" << key
                         << "valueLen=" << cleaned.size()
                         << "scheme=" << cleaned.section(QLatin1Char(' '), 0, 0);
}

void BasicAuthInterceptor::clearCredential(const QString &host)
{
    const QString key = host.toLower();
    m_headers.remove(key);
    m_hostOwner.remove(key);
}

void BasicAuthInterceptor::clearAll()
{
    m_headers.clear();
    m_hostOwner.clear();
}

void BasicAuthInterceptor::applyProfile(const QString &profileId,
                                       const QString &authType,
                                       const QString &username,
                                       const QString &secret,
                                       const QStringList &hosts)
{
    if (profileId.isEmpty() || hosts.isEmpty() || secret.isEmpty()) {
        qCInfo(lcIframeAuth) << "applyProfile: skipping (empty profileId/hosts/secret)"
                             << "id=" << profileId << "hostsCount=" << hosts.size()
                             << "secretLen=" << secret.size();
        return;
    }
    // Build the Authorization header value once.
    QByteArray header;
    if (authType == QLatin1String("basic")) {
        const QByteArray creds = (username + QLatin1Char(':') + secret).toUtf8();
        header = QByteArrayLiteral("Basic ") + creds.toBase64();
    } else if (authType == QLatin1String("bearer")) {
        header = QByteArrayLiteral("Bearer ") + secret.toUtf8();
    } else if (authType == QLatin1String("raw")) {
        // Strip whitespace and surrounding quotes that users sometimes paste.
        QString cleaned = secret.trimmed();
        if ((cleaned.startsWith(QLatin1Char('"')) && cleaned.endsWith(QLatin1Char('"')))
            || (cleaned.startsWith(QLatin1Char('\'')) && cleaned.endsWith(QLatin1Char('\'')))) {
            cleaned = cleaned.mid(1, cleaned.size() - 2);
        }
        header = cleaned.toUtf8();
    } else {
        qCWarning(lcIframeAuth) << "applyProfile: unknown authType=" << authType;
        return;
    }

    for (const QString &h : hosts) {
        const QString key = h.toLower();
        // Conflict detection: same host owned by a different profile — last-write-wins, warn.
        const auto ownerIt = m_hostOwner.constFind(key);
        if (ownerIt != m_hostOwner.cend() && ownerIt.value() != profileId) {
            qCWarning(lcIframeAuth) << "applyProfile: host" << key
                << "was owned by profile" << ownerIt.value()
                << "now overridden by profile" << profileId;
        }
        m_headers.insert(key, header);
        m_hostOwner.insert(key, profileId);
    }
    qCInfo(lcIframeAuth) << "applyProfile: id=" << profileId
                         << "type=" << authType
                         << "hosts=" << hosts
                         << "headerLen=" << header.size();
}

void BasicAuthInterceptor::clearProfile(const QString &profileId)
{
    if (profileId.isEmpty()) {
        return;
    }
    QStringList wiped;
    for (auto it = m_hostOwner.begin(); it != m_hostOwner.end(); /* manual */) {
        if (it.value() == profileId) {
            m_headers.remove(it.key());
            wiped.append(it.key());
            it = m_hostOwner.erase(it);
        } else {
            ++it;
        }
    }
    qCInfo(lcIframeAuth) << "clearProfile: id=" << profileId << "wiped hosts=" << wiped;
}

QStringList BasicAuthInterceptor::hosts() const
{
    return m_headers.keys();
}

void BasicAuthInterceptor::interceptRequest(QWebEngineUrlRequestInfo &info)
{
    // Runs on Chromium's IO thread. Keep allocation cheap.
    const QString host = info.requestUrl().host().toLower();
    const auto it = m_headers.constFind(host);
    if (it != m_headers.cend()) {
        info.setHttpHeader(QByteArrayLiteral("Authorization"), it.value());
        qCInfo(lcIframeAuth).noquote() << "interceptor: injected Authorization for"
            << info.requestUrl().toString().left(120);
    } else if (!m_headers.isEmpty()) {
        // Only log near-misses if we have any creds at all
        qCInfo(lcIframeAuth).noquote() << "interceptor: NO MATCH host=" << host
            << "url=" << info.requestUrl().toString().left(120);
    }
}

bool BasicAuthInterceptor::attachTo(QObject *profile)
{
    if (!profile) {
        qCWarning(lcIframeAuth) << "attachTo: profile is null";
        return false;
    }
    auto *p = qobject_cast<QQuickWebEngineProfile *>(profile);
    if (!p) {
        qCWarning(lcIframeAuth) << "attachTo: qobject_cast failed; actual class ="
                                << profile->metaObject()->className();
        return false;
    }
    p->setUrlRequestInterceptor(this);
    qCInfo(lcIframeAuth) << "attachTo: SUCCESS profile=" << p
                         << "storageName=" << p->storageName();
    return true;
}

bool BasicAuthInterceptor::detachFrom(QObject *profile)
{
    if (!profile) return false;
    auto *p = qobject_cast<QQuickWebEngineProfile *>(profile);
    if (!p) {
        qCWarning(lcIframeAuth) << "detachFrom: qobject_cast failed; class ="
                                << profile->metaObject()->className();
        return false;
    }
    p->setUrlRequestInterceptor(nullptr);
    qCInfo(lcIframeAuth) << "detachFrom: SUCCESS profile=" << p;
    return true;
}
