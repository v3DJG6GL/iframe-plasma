/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pure query-string editing helpers and the Authelia host-match used by
 * WebTab.qml. Lifted here so tests/qml/tst_query_helpers.qml and
 * tests/qml/tst_authelia_detect.qml can drive every branch without
 * instantiating a WebEngineView.
 *
 *   editQuery(urlStr, updates) — manual ?key=value editor. QML's V4
 *     URLSearchParams has a bug where delete()/set() modifications
 *     silently fail to propagate back to url.toString(), so we use a
 *     hand-rolled splitter. `updates` is { key: string|null }: null
 *     removes, string sets (URL-encoded). First occurrence per key
 *     wins (legacy behaviour); subsequent dupes are dropped.
 *     Hash fragment and unrelated params preserved. Returns the
 *     rewritten string (or the input verbatim on error).
 *
 *   readQuery(urlStr, name) — extract the first `name=value` from the
 *     query (decoded), "" if absent. Flag-style params (no `=`) read
 *     as "".
 *
 *   matchTimeRangePreset(fromValue, toValue) — given the from/to query
 *     values, return the preset suffix ("24h" etc.), "custom" for
 *     non-preset, or "" when both absent. Pure factoring of WebTab's
 *     `currentTimeRange` property.
 *
 *   isAutheliaHost(currentUrl, autheliaHost) — true when currentUrl's
 *     host equals or is a subdomain of autheliaHost. Mirrors WebTab's
 *     onAutheliaHost.
 */
.pragma library
.import "sanitize.js" as Sanitize

function editQuery(urlStr, updates) {
    try {
        const hashIdx = urlStr.indexOf('#');
        const hash = hashIdx >= 0 ? urlStr.slice(hashIdx) : '';
        const beforeHash = hashIdx >= 0 ? urlStr.slice(0, hashIdx) : urlStr;
        const qIdx = beforeHash.indexOf('?');
        const path = qIdx >= 0 ? beforeHash.slice(0, qIdx) : beforeHash;
        const query = qIdx >= 0 ? beforeHash.slice(qIdx + 1) : '';
        const pairs = query.length > 0 ? query.split('&') : [];
        const handled = {};
        const out = [];
        // hasOwnProperty (not `k in updates`): `in` walks the prototype
        // chain, so a URL carrying e.g. `?toString=foo` would match
        // Object.prototype.toString and get rewritten to the encoded
        // function source, silently corrupting the navigated URL.
        const hasOwn = Object.prototype.hasOwnProperty;
        for (const p of pairs) {
            const eq = p.indexOf('=');
            const k = eq === -1 ? p : p.slice(0, eq);
            if (hasOwn.call(updates, k)) {
                if (!hasOwn.call(handled, k)) {
                    handled[k] = true;
                    const v = updates[k];
                    if (v !== null && v !== undefined) {
                        out.push(k + '=' + encodeURIComponent(v));
                    }
                }
            } else {
                out.push(p);
            }
        }
        for (const k of Object.keys(updates)) {
            if (!hasOwn.call(handled, k) && updates[k] !== null && updates[k] !== undefined) {
                out.push(k + '=' + encodeURIComponent(updates[k]));
            }
        }
        return path + (out.length ? '?' + out.join('&') : '') + hash;
    } catch (e) {
        console.warn("iframe-plasma: editQuery error:", e.message);
        return urlStr;
    }
}

function readQuery(urlStr, name) {
    try {
        const hashIdx = urlStr.indexOf('#');
        const beforeHash = hashIdx >= 0 ? urlStr.slice(0, hashIdx) : urlStr;
        const qIdx = beforeHash.indexOf('?');
        if (qIdx < 0) return "";
        const pairs = beforeHash.slice(qIdx + 1).split('&');
        for (const p of pairs) {
            const eq = p.indexOf('=');
            const k = eq === -1 ? p : p.slice(0, eq);
            if (k === name) {
                return eq === -1 ? "" : decodeURIComponent(p.slice(eq + 1));
            }
        }
        return "";
    } catch (e) { return ""; }
}

function matchTimeRangePreset(fromValue, toValue) {
    if (!fromValue && !toValue) return '';
    const m = (fromValue || '').match(/^now-(\d+[smhdwMy])$/);
    if (m && toValue === 'now') return m[1];
    return 'custom';
}

function isAutheliaHost(currentUrl, autheliaHost) {
    if (!autheliaHost || autheliaHost.length === 0) return false;
    try {
        // WHATWG URL.host is always ASCII-lowercased; sanitizeAutheliaHost
        // (ConfigAuth.qml) only trims + strips control bytes and does not
        // lowercase, so a stored value like "Auth.Example.COM" would
        // silently fail to match and the overlay never engages.
        //
        // Sanitize.strip here as defence-in-depth: ConfigAuth's load-time
        // sanitize covers per-profile autheliaHost rows but two paths still
        // feed the comparison raw — the deprecated-global fallback in
        // main.qml:2069 (`Plasmoid.configuration.autheliaHost || ""`) and
        // Migrations.legacyAuthMigration copying `autheliaHostFallback`
        // into a newly-synthesised profile verbatim. Either path can leak
        // a stray ZWSP/RLO/BOM that the literal `===` / `endsWith` would
        // silently miss, leaving the overlay disengaged so the operator
        // types credentials into the bare upstream login page.
        const host = new URL(currentUrl).host;
        const want = Sanitize.strip(String(autheliaHost).toLowerCase());
        if (!want) return false;
        return host === want
            || host.endsWith("." + want);
    } catch (e) {
        return false;
    }
}
