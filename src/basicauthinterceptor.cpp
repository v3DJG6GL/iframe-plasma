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
    // For basic auth the username is concatenated with `:` before base64; a `:`
    // inside `username` would silently re-partition the decoded credential
    // (e.g. user="u", pass="a:b" → server sees user="u", pass="a:b"). Also
    // refuse C0 controls/DEL in username — base64 hides them from the
    // post-encode control-byte check below.
    if (authType == QLatin1String("basic")) {
        for (QChar ch : username) {
            const ushort u = ch.unicode();
            if (ch == QLatin1Char(':') || (u < 0x20 && u != 0x09) || u == 0x7F) {
                qCWarning(lcIframeAuth) << "applyProfile: refusing basic username with `:` or control char; id=" << profileId;
                return;
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
    // Canonicalize the lookup key to WHATWG `URL.host` semantics — that's
    // what the QML registration side (`new URL(t.url).host` in
    // primeAuthProfiles) emits: bare host for default ports (http→80,
    // https→443), `host:port` for non-default ports. Without this
    // canonicalization two failure modes appear:
    //  (a) Tab URL `https://h:9100/` registers key `h:9100`; QUrl::host()
    //      here returns `h` (port stripped) → lookup misses → auth never
    //      fires for non-default-port tabs.
    //  (b) Tab URL `https://h/` registers key `h`; a same-tab fetch to
    //      `https://h:9100/...` was previously matched as bare `h`
    //      → Authorization header leaked to an unrelated port on the
    //      same host (e.g. sidecar metrics endpoints).
    const QString rawHost = info.requestUrl().host().toLower();
    const int rawPort = info.requestUrl().port();
    const bool isDefaultPort = (rawPort == -1)
        || (scheme == QLatin1String("https") && rawPort == 443)
        || (scheme == QLatin1String("http")  && rawPort == 80);
    const QString host = isDefaultPort
        ? rawHost
        : rawHost + QLatin1Char(':') + QString::number(rawPort);
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
