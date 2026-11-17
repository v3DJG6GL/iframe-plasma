/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pure URL-rewriting helpers behind the KCM's "From Grafana URL…" dialog
 * (ConfigUrls.qml). Pulled out so tests/qml/tst_grafana_url_rewrite.qml
 * can drive the full pipeline table-style without instantiating the
 * KCM Dialog tree.
 *
 *   transform(input, opts) — full pipeline; opts mirrors the dialog
 *                            toggle states (convertDSolo, timeRange,
 *                            kiosk, theme, refresh, refreshSeconds,
 *                            hideLogo, hidePanelMenu).
 *
 *   optsFor(isEdit, controls) — the opts transform() gets for the
 *                            dialog's Add or Edit mode.
 *
 *   parseRefreshSeconds(u, min, max) — a URL's refresh=<N>s|m|h as
 *                            clamped seconds, -1 when absent/unreadable/0.
 *
 *   parseTimeRange(u, presets) — the preset a URL's from/to window is,
 *                            "" when it is none of them.
 *
 *   paramIsOn(u, key, onValues) — whether a query param carries one of
 *                            the values that switch it on.
 *
 *   kioskIsOn(u) / kioskIsForeign(u) — the Edit dialog's Kiosk switch
 *                            state, and whether the URL's kiosk value is
 *                            one to keep verbatim (kiosk=tv).
 *
 *   splitFragment(u) → [base, "#frag"] — preserves an anchor through
 *                            subsequent stripParam/appendParam ops.
 *
 *   appendParam(u, k, v)  — adds k=v with `?` or `&` separator, fragment-safe.
 *   stripParam(u, key)    — removes every k=… occurrence, fragment-safe.
 */
.pragma library

function splitFragment(u) {
    const i = u.indexOf("#");
    return i === -1 ? [u, ""] : [u.substring(0, i), u.substring(i)];
}

function appendParam(u, key, value) {
    const parts = splitFragment(u);
    const base = parts[0];
    const frag = parts[1];
    const sep = base.indexOf("?") === -1 ? "?" : "&";
    return base + sep + key + "=" + value + frag;
}

function stripParam(u, key) {
    const parts = splitFragment(u);
    const base = parts[0];
    const frag = parts[1];
    const qIdx = base.indexOf("?");
    if (qIdx === -1) return base + frag;
    const path = base.substring(0, qIdx);
    const query = base.substring(qIdx + 1);
    // Split on `&` so consecutive duplicates (?panelId=1&panelId=2) all
    // strip in one pass. The previous regex pair could only catch one
    // head-position occurrence per call and silently left adjacent dupes.
    const kept = query.split("&").filter(function(kv) {
        if (!kv) return false;
        const eq = kv.indexOf("=");
        if (eq === -1) return true; // preserve valueless flags (e.g. kiosk)
        return kv.substring(0, eq) !== key;
    });
    return path + (kept.length ? "?" + kept.join("&") : "") + frag;
}

// Seconds as a Grafana refresh token in the largest unit that divides it
// exactly: 60 -> "1m", 7200 -> "2h", 86400 -> "1d", 90 -> "90s". The inverse
// of parseRefreshSeconds's unit table.
function refreshToken(seconds) {
    const n = Number(seconds);
    if (n > 0 && n % 86400 === 0) return (n / 86400) + "d";
    if (n > 0 && n % 3600 === 0) return (n / 3600) + "h";
    if (n > 0 && n % 60 === 0) return (n / 60) + "m";
    return String(seconds) + "s";
}

// Full URL transformation. `opts` shape:
//   { convertDSolo:bool, timeRange:string, kiosk:bool, theme:bool,
//     refresh:bool, refreshSeconds:number, hideLogo:bool,
//     hidePanelMenu:bool }
// Returns "" on CR/LF/NUL reject; transformed URL otherwise.
function transform(input, opts) {
    let u = (input || "").trim();
    if (!u) return "";

    // CR/LF/NUL reject — same threat-class as the auth interceptor's
    // C0-byte gate. A stray \n in a pasted URL corrupts the splitFragment
    // contract and risks bleeding params past a stray `#`.
    if (/[\r\n\0]/.test(u)) {
        return "";
    }

    opts = opts || {};

    // Split off the fragment once up front, work on `base` for the
    // entire pipeline, re-attach at the end. The existence regexes
    // below (`/[?&]theme=/`, `/[?&]hideLogo=/`, `/[?&]_ifp_hidePanelMenu=/`,
    // `/[?&]kiosk(=|&|#|$)/`) and the viewPanel match all scan the
    // whole string. For a Grafana hash-routed share link whose fragment
    // carries query-style chars (e.g. "https://g/x#/d/abc?theme=dark"),
    // a key embedded in `#…` falsely satisfies "already present?" and
    // silently suppresses the requested append, or a `?viewPanel=…` in
    // the fragment is misidentified as a real query param. Same
    // bug-class as the Run #4 viewPanel-terminator (21acd1e) and Run
    // #9 kiosk-terminator (2f771a5) fixes, generalised across the
    // remaining four existence guards via single-site fragment split.
    const _topParts = splitFragment(u);
    let base = _topParts[0];
    const frag = _topParts[1];

    // 1) /d/ → /d-solo/ (only when we have a viewPanel to convert).
    //    The match is anchored on the end of the value, so a viewPanel
    //    shape we don't understand leaves the URL alone instead of getting
    //    a panelId for the wrong panel next to a leftover viewPanel.
    const viewPanelMatch = base.match(/[?&]viewPanel=panel-(\d+)(?:-clone\d+)?(?=&|$)/);
    if (opts.convertDSolo && viewPanelMatch && base.indexOf("/d/") !== -1) {
        base = base.replace("/d/", "/d-solo/");
        base = stripParam(base, "viewPanel");
        // /d/ dashboard URLs sometimes already carry a panelId from a
        // prior drill-down; without this strip we'd emit two panelId
        // params and Grafana picks first-or-last in a version-dependent
        // way (user sees the wrong panel with no diagnostic).
        base = stripParam(base, "panelId");
        base = appendParam(base, "panelId", viewPanelMatch[1]);
    }

    // 2) Time range — strip any existing from/to, then add the preset.
    if (opts.timeRange) {
        base = stripParam(base, "from");
        base = stripParam(base, "to");
        base = appendParam(base, "from", "now-" + opts.timeRange);
        base = appendParam(base, "to", "now");
    }

    // 3) Kiosk — emit just `&kiosk` (no value); kiosk=1 has a Grafana
    //    11.2.x regression. Delimiter-anchor so kiosk.example.com host
    //    or kioskMode=1 param don't suppress insertion.
    if (opts.kiosk && !/[?&]kiosk(=|&|$)/.test(base)) {
        base = base + (base.indexOf("?") === -1 ? "?" : "&") + "kiosk";
    }

    // 4) Theme — runtime substitutes ${theme}.
    if (opts.theme && !/[?&]theme=/.test(base)) {
        base = appendParam(base, "theme", "${theme}");
    }

    // 5) Refresh — omit entirely when off (empty refresh= is buggy).
    //    Written in the largest whole unit (60 -> 1m, 86400 -> 1d): Grafana
    //    matches the value as a string against its interval list
    //    (5s..1m..1d), and older versions fall back to the FIRST entry
    //    (5s) for an unlisted "60s", polling far faster than chosen.
    if (opts.refresh) {
        base = stripParam(base, "refresh");
        base = appendParam(base, "refresh", refreshToken(opts.refreshSeconds));
    }

    // 6) hideLogo — strip the "Powered by Grafana" overlay on 12.4+.
    if (opts.hideLogo && !/[?&]hideLogo=/.test(base)) {
        base = appendParam(base, "hideLogo", "true");
    }

    // 7) hidePanelMenu — internal sentinel (Grafana ignores unknown
    //    params). WebTab.qml's user script suppresses the per-panel
    //    kebab when set.
    if (opts.hidePanelMenu && !/[?&]_ifp_hidePanelMenu=/.test(base)) {
        base = appendParam(base, "_ifp_hidePanelMenu", "1");
    }

    return base + frag;
}

// transform() options for the dialog's control state. Edit mode never
// converts /d/ to /d-solo/: the switch is hidden there, the conversion
// cannot be undone, and a /d/ row that still carries viewPanel is one the
// user chose to keep as a full dashboard.
function optsFor(isEdit, controls) {
    const opts = Object.assign({}, controls);
    opts.convertDSolo = !isEdit && !!opts.convertDSolo;
    return opts;
}

// Auto-refresh interval a URL carries, in seconds clamped to
// [minSec, maxSec]; -1 when it has none the dialog can show. Grafana's own
// picker writes minutes, hours and days (refresh=1m, refresh=2h,
// refresh=1d), not only the seconds form transform() emits, and a value
// this does not read is one the Edit dialog shows as "off" and then strips.
function parseRefreshSeconds(url, minSec, maxSec) {
    const base = splitFragment(String(url || ""))[0];
    const m = base.match(/[?&]refresh=([0-9]+)([smhd])(?:&|$)/);
    if (!m) return -1;
    const sec = parseInt(m[1], 10) * { s: 1, m: 60, h: 3600, d: 86400 }[m[2]];
    // refresh=0<unit> is no auto-refresh in Grafana (a count must be > 0);
    // clamping it to minSec would let an untouched Edit-dialog OK turn it
    // into a live minSec poll.
    if (sec <= 0) return -1;
    return Math.max(minSec, Math.min(maxSec, sec));
}

// Time-range preset (one of `presets`, e.g. "24h") a URL's window is, or ""
// when it is none — the Edit dialog then shows "(keep URL's range)" and
// transform() leaves from/to alone. A preset means from=now-<X>&to=now, so
// a `to` other than `now` (to=now-1d, an absolute time) is a window the
// presets cannot represent: taking the preset anyway let OK on an
// unrelated edit rewrite it to to=now.
function parseTimeRange(url, presets) {
    const base = splitFragment(String(url || ""))[0];
    const m = base.match(/[?&]from=now-([0-9]+[smhdwMy])(?:&|$)/);
    if (!m) return "";
    const tos = base.match(/[?&]to=[^&]*/g) || [];
    if (tos.some(function(t) { return t.substring(1) !== "to=now"; })) return "";
    return presets.indexOf(m[1]) !== -1 ? m[1] : "";
}

// Whether query param `key` carries one of `onValues` (fragment ignored).
// The Edit dialog's hideLogo / hidePanelMenu switches read the value, not
// the key's presence: a row with hideLogo=false opened with the switch on,
// and OK then rewrote it to hideLogo=true without any user action.
function paramIsOn(url, key, onValues) {
    const base = splitFragment(String(url || ""))[0];
    const q = base.indexOf("?");
    if (q === -1) return false;
    return base.substring(q + 1).split("&").some(function(kv) {
        const eq = kv.indexOf("=");
        return eq !== -1 && kv.substring(0, eq) === key
            && onValues.indexOf(kv.substring(eq + 1)) !== -1;
    });
}

// Value of the first `kiosk` query param (fragment ignored): null when
// absent, "" for the bare flag transform() emits.
function _kioskValue(url) {
    const base = splitFragment(String(url || ""))[0];
    const q = base.indexOf("?");
    if (q === -1) return null;
    const kvs = base.substring(q + 1).split("&");
    for (let i = 0; i < kvs.length; i++) {
        const eq = kvs[i].indexOf("=");
        if ((eq === -1 ? kvs[i] : kvs[i].substring(0, eq)) === "kiosk")
            return eq === -1 ? "" : kvs[i].substring(eq + 1);
    }
    return null;
}

// Edit dialog's Kiosk switch: the value, not the key's presence, like
// paramIsOn. Grafana reads kiosk=0 / kiosk=false as off, so a row with
// either opened with the switch on and OK rewrote it to a bare `kiosk`.
function kioskIsOn(url) {
    const v = _kioskValue(url);
    return v !== null && v !== "0" && v !== "false";
}

// A kiosk value the dialog neither emits nor reads as off (legacy
// kiosk=tv). Edit mode keeps it verbatim while the switch stays on —
// strip + re-append would silently turn it into full kiosk.
function kioskIsForeign(url) {
    const v = _kioskValue(url);
    return v !== null && ["", "1", "true", "0", "false"].indexOf(v) === -1;
}
