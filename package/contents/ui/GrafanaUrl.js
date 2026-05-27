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
    let base = parts[0];
    const frag = parts[1];
    // ?key=val&…   → ?…
    base = base.replace(new RegExp("[?]" + key + "=[^&]*(?:&|$)"), function(m) {
        return m.endsWith("&") ? "?" : "";
    });
    // &key=val
    base = base.replace(new RegExp("[&]" + key + "=[^&]*", "g"), "");
    return base + frag;
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

    // 1) /d/ → /d-solo/ (only when we have a viewPanel to convert).
    const viewPanelMatch = u.match(/[?&]viewPanel=panel-(\d+)(?:-clone\d+)?/);
    if (opts.convertDSolo && viewPanelMatch && u.indexOf("/d/") !== -1) {
        u = u.replace("/d/", "/d-solo/");
        u = u.replace(/([?&])viewPanel=panel-\d+(-clone\d+)?(&|$)/, function(_, before, _clone, after) {
            return before === "?" && after === "" ? ""
                 : before === "?" ? "?"
                 : after === "" ? "" : "&";
        });
        u = appendParam(u, "panelId", viewPanelMatch[1]);
    }

    // 2) Time range — strip any existing from/to, then add the preset.
    if (opts.timeRange) {
        u = stripParam(u, "from");
        u = stripParam(u, "to");
        u = appendParam(u, "from", "now-" + opts.timeRange);
        u = appendParam(u, "to", "now");
    }

    // 3) Kiosk — emit just `&kiosk` (no value); kiosk=1 has a Grafana
    //    11.2.x regression. Delimiter-anchor so kiosk.example.com host
    //    or kioskMode=1 param don't suppress insertion. Route through
    //    splitFragment so the flag doesn't bleed past a `#anchor`.
    if (opts.kiosk && !/[?&]kiosk(=|&|$)/.test(u)) {
        const parts = splitFragment(u);
        const base = parts[0];
        const frag = parts[1];
        u = base + (base.indexOf("?") === -1 ? "?" : "&") + "kiosk" + frag;
    }

    // 4) Theme — runtime substitutes ${theme}.
    if (opts.theme && !/[?&]theme=/.test(u)) {
        u = appendParam(u, "theme", "${theme}");
    }

    // 5) Refresh — omit entirely when off (empty refresh= is buggy).
    if (opts.refresh) {
        u = stripParam(u, "refresh");
        u = appendParam(u, "refresh", String(opts.refreshSeconds) + "s");
    }

    // 6) hideLogo — strip the "Powered by Grafana" overlay on 12.4+.
    if (opts.hideLogo && !/[?&]hideLogo=/.test(u)) {
        u = appendParam(u, "hideLogo", "true");
    }

    // 7) hidePanelMenu — internal sentinel (Grafana ignores unknown
    //    params). WebTab.qml's user script suppresses the per-panel
    //    kebab when set.
    if (opts.hidePanelMenu && !/[?&]_ifp_hidePanelMenu=/.test(u)) {
        u = appendParam(u, "_ifp_hidePanelMenu", "1");
    }

    return u;
}
