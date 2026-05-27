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
    const viewPanelMatch = base.match(/[?&]viewPanel=panel-(\d+)(?:-clone\d+)?/);
    if (opts.convertDSolo && viewPanelMatch && base.indexOf("/d/") !== -1) {
        base = base.replace("/d/", "/d-solo/");
        base = base.replace(/([?&])viewPanel=panel-\d+(-clone\d+)?(&|$)/, function(_, before, _clone, after) {
            return before === "?" && after === "" ? ""
                 : before === "?" ? "?"
                 : after === "" ? "" : "&";
        });
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
    if (opts.refresh) {
        base = stripParam(base, "refresh");
        base = appendParam(base, "refresh", String(opts.refreshSeconds) + "s");
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
