/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#include "basicauthinterceptor.h"

#include <QByteArray>
#include <QDebug>
#include <QLatin1Char>
#include <QLatin1String>
#include <QLoggingCategory>
#include <QQuickWebEngineProfile>
#include <QUrl>

Q_LOGGING_CATEGORY(lcIframeAuth, "iframeplasma.auth")

namespace iframeplasma::auth {

QString canonicalizeHost(const QString &rawHost, const QString &scheme, int port)
{
    // QML side registers hosts using WHATWG `new URL().host` semantics:
    // bare host for default scheme ports (http→80, https→443), `host:port`
    // otherwise. QUrl::host() strips brackets from IPv6 literals (returns
    // `::1` for `https://[::1]/`), and the colon-in-host then becomes the
    // IPv6 sigil (port is already separated). Re-add brackets so the lookup
    // key matches the QML-side registration. Lowercase for case-fold match.
    const QString lower = rawHost.toLower();
    const bool isDefaultPort = (port == -1)
        || (scheme == QLatin1String("https") && port == 443)
        || (scheme == QLatin1String("http")  && port == 80);
    const QString bracketed = lower.contains(QLatin1Char(':'))
        ? QLatin1Char('[') + lower + QLatin1Char(']')
        : lower;
    return isDefaultPort
        ? bracketed
        : bracketed + QLatin1Char(':') + QString::number(port);
}

std::optional<QByteArray> buildAuthHeader(const QString &authType,
                                          const QString &username,
                                          const QString &secret,
                                          QString *errorReason)
{
    auto fail = [errorReason](const char *r) -> std::optional<QByteArray> {
        if (errorReason) {
            *errorReason = QString::fromLatin1(r);
        }
        return std::nullopt;
    };

    if (secret.isEmpty()) {
        return fail("empty-secret");
    }
    // For basic auth the username is concatenated with `:` before base64; a `:`
    // inside `username` would silently re-partition the decoded credential
    // (e.g. user="u", pass="a:b" → server sees user="u", pass="a:b"). Also
    // refuse C0 controls/DEL in username — base64 hides them from the
    // post-encode control-byte check below.
    if (authType == QLatin1String("basic")) {
        for (QChar ch : username) {
            const ushort u = ch.unicode();
            if (ch == QLatin1Char(':')) {
                return fail("colon-in-basic-username");
            }
            if ((u < 0x20 && u != 0x09) || u == 0x7F) {
                return fail("control-in-username");
            }
        }
    }
    // Build the Authorization header value once.
    QByteArray header;
    if (authType == QLatin1String("basic")) {
        const QByteArray creds = (username + QLatin1Char(':') + secret).toUtf8();
        header = QByteArrayLiteral("Basic ") + creds.toBase64();
    } else if (authType == QLatin1String("bearer")) {
        // Trim surrounding whitespace — RFC 7235 §2.1 token68 forbids whitespace
        // inside the credential, and an operator pasting a token from clipboard
        // commonly drags a trailing space along. Fail-closed proxies (oauth2-
        // proxy in strict mode, some auth-proxy implementations) reject the
        // request with 401 and the operator sees an unauthenticated dashboard
        // with no clear failure path — a paste-typo becomes an availability
        // issue. Parity with the `raw` branch's hygiene.
        header = QByteArrayLiteral("Bearer ") + secret.trimmed().toUtf8();
    } else if (authType == QLatin1String("raw")) {
        // Strip whitespace and surrounding quotes that users sometimes paste.
        QString cleaned = secret.trimmed();
        if ((cleaned.startsWith(QLatin1Char('"')) && cleaned.endsWith(QLatin1Char('"')))
            || (cleaned.startsWith(QLatin1Char('\'')) && cleaned.endsWith(QLatin1Char('\'')))) {
            cleaned = cleaned.mid(1, cleaned.size() - 2);
        }
        header = cleaned.toUtf8();
    } else {
        return fail("unknown-authtype");
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
            return fail("control-in-header");
        }
    }
    return header;
}

} // namespace iframeplasma::auth

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
    // `none` is a named passthrough profile — page handles its own login
    // (form-based, cookies, OAuth, 401 dialog). Skip silently before the
    // empty-secret gate so the journal isn't polluted with a misleading
    // "empty secret" warning every prime cycle.
    if (authType == QLatin1String("none")) {
        return;
    }
    if (profileId.isEmpty() || hosts.isEmpty() || secret.isEmpty()) {
        qCInfo(lcIframeAuth) << "applyProfile: skipping (empty profileId/hosts/secret)"
                             << "id=" << profileId << "hostsCount=" << hosts.size()
                             << "secretLen=" << secret.size();
        return;
    }
    QString errorReason;
    const auto built = iframeplasma::auth::buildAuthHeader(authType, username, secret, &errorReason);
    if (!built) {
        if (errorReason == QLatin1String("colon-in-basic-username")
            || errorReason == QLatin1String("control-in-username")) {
            qCWarning(lcIframeAuth) << "applyProfile: refusing basic username with `:` or control char; id=" << profileId;
        } else if (errorReason == QLatin1String("unknown-authtype")) {
            qCWarning(lcIframeAuth) << "applyProfile: unknown authType=" << authType;
        } else if (errorReason == QLatin1String("control-in-header")) {
            qCWarning(lcIframeAuth) << "applyProfile: refusing header with control byte; id=" << profileId;
        }
        return;
    }
    const QByteArray header = *built;

    {
        QWriteLocker locker(&m_headersLock);
        for (const QString &h : hosts) {
            // Trim + skip empty hosts. An empty string here would register
            // m_headers[""], and QUrl::host() returns an empty string for a
            // malformed-but-http-schemed URL whose authority is degenerate
            // (e.g. "http:///path"). The scheme gate in interceptRequest()
            // wouldn't catch that — it only filters on scheme, not on host
            // shape — so the empty-key entry would leak the Authorization
            // header to a request the operator never registered.
            const QString hLower = h.trimmed().toLower();
            if (hLower.isEmpty()) {
                qCWarning(lcIframeAuth) << "applyProfile: skipping empty/whitespace host entry; id=" << profileId;
                continue;
            }
            m_headers.insert(hLower, header);
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
    // Gate on http(s): operator-registered hosts are intended for HTTP
    // traffic; never inject the Authorization header onto ws://, wss://,
    // ftp://, or any future custom scheme that happens to share host().
    const QString scheme = info.requestUrl().scheme();
    if (scheme != QLatin1String("https") && scheme != QLatin1String("http")) {
        return;
    }
    const QString host = iframeplasma::auth::canonicalizeHost(
        info.requestUrl().host(), scheme, info.requestUrl().port());
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
