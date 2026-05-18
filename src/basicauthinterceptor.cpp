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

void BasicAuthInterceptor::clearAll()
{
    QWriteLocker locker(&m_headersLock);
    m_headers.clear();
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

    // Defense against header injection: a bearer/raw secret containing CR/LF
    // (or NUL) would smuggle additional HTTP headers into every outbound
    // request. Base64 (basic) cannot produce these bytes; bearer/raw take
    // the secret verbatim, so this check is the gate.
    //
    // RFC 7230 §3.2.6 restricts field-value to VCHAR / SP / HTAB / obs-text;
    // other C0 controls and DEL are not transmissible. Chromium normally
    // rejects them, but reject here too so a non-conformant downstream
    // proxy never sees e.g. a vertical-tab as a line terminator.
    for (char c : std::as_const(header)) {
        const unsigned char b = static_cast<unsigned char>(c);
        if ((b < 0x20 && b != '\t') || b == 0x7F) {
            qCWarning(lcIframeAuth) << "applyProfile: refusing header with control byte; id=" << profileId;
            return;
        }
    }

    {
        QWriteLocker locker(&m_headersLock);
        for (const QString &h : hosts) {
            m_headers.insert(h.toLower(), header);
        }
    }
    qCInfo(lcIframeAuth) << "applyProfile: id=" << profileId
                         << "type=" << authType
                         << "hostsCount=" << hosts.size()
                         << "headerLen=" << header.size();
}

void BasicAuthInterceptor::interceptRequest(QWebEngineUrlRequestInfo &info)
{
    // Runs on Chromium's IO thread. Keep allocation cheap and release the
    // read lock before touching `info` / logging so UI-thread mutations
    // don't stall.
    const QString host = info.requestUrl().host().toLower();
    QByteArray header;
    bool hadAny = false;
    {
        QReadLocker locker(&m_headersLock);
        const auto it = m_headers.constFind(host);
        if (it != m_headers.cend()) {
            header = it.value();
        }
        hadAny = !m_headers.isEmpty();
    }
    if (!header.isEmpty()) {
        info.setHttpHeader(QByteArrayLiteral("Authorization"), header);
        // qCDebug, not qCInfo: request URLs can carry tokens in the query
        // string (e.g. Grafana share links with auth params), so keep them
        // off the default journal stream.
        qCDebug(lcIframeAuth).noquote() << "interceptor: injected Authorization for"
            << info.requestUrl().toString().left(120);
    } else if (hadAny) {
        // Only log near-misses if we have any creds at all
        qCDebug(lcIframeAuth).noquote() << "interceptor: NO MATCH host=" << host
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
