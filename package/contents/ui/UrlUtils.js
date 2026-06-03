/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pure-function helpers extracted from main.qml so that
 *   tests/qml/tst_parse_safe.qml
 *   tests/qml/tst_resolve_theme.qml
 * can drive them table-style without instantiating the whole applet.
 *
 * Nothing in here touches Plasmoid.configuration, Kirigami.Theme, or any
 * other singleton — every input arrives by argument. main.qml's QML-side
 * wrappers (parseAuthProfiles / parseTabs / _isSafeTabUrl / resolveTheme /
 * resolveUrl / isGrafanaEmbed) are now one-line forwarders to these.
 */
.pragma library

// Tab URLs must be http(s). Pasted `data:`, `file:`, `javascript:`, `blob:`
// etc. would execute in the per-profile cookie/storage origin or read
// local files, so they're filtered out early. Embedded CR/LF/NUL is
// rejected for the same defence-in-depth reason GrafanaUrl.transform's
// C0 gate exists — a control byte in a URL routed through any
// non-WebEngine HTTP path would smuggle additional header lines.
function isSafeTabUrl(s) {
    if (typeof s !== "string") return false;
    if (/[\r\n\0]/.test(s)) return false;
    return /^https?:\/\//i.test(s);
}

// Single source of truth for "this on-disk row becomes a live tab". Drops
// rows with an unsafe/parse-hostile URL AND rows the user disabled. Both
// parseTabs (which produces root.tabs) and configIndexForTab (which maps a
// live-tab index back to its on-disk position) MUST agree on this predicate,
// else the filtered live index and the unfiltered urlsJson index diverge.
// `enabled !== false` keeps legacy rows that predate the field (missing →
// enabled).
function isLiveTab(t) {
    return !!t && isSafeTabUrl(t.url) && t.enabled !== false;
}

// JSON.parse with a defensive guard: returns the parsed array (with
// unsafe-URL and disabled rows filtered) or [] on any failure. Logs to
// console.warn so users debugging a broken config get a journal breadcrumb.
function parseTabs(jsonStr) {
    try {
        const arr = JSON.parse(jsonStr || "[]");
        // Drop disabled/unsafe rows here, at the single deserialize chokepoint,
        // so the live tab set (root.tabs) carries only enabled URLs — every
        // downstream consumer (tab bar, popup/thumbnail Repeaters, auto-
        // cycle, keyboard nav, count gates) is then correct with no per-
        // consumer skip. The config page (ConfigUrls) keeps its own full list,
        // so disabled URLs stay editable / re-enableable.
        if (Array.isArray(arr)) return arr.filter(isLiveTab);
    } catch (e) {
        console.warn("iframe-plasma: bad urlsJson:", e.message);
    }
    return [];
}

// Translate a live-tab index (index into the filtered array parseTabs
// returns) back to its index in the FULL on-disk `arr`. Returns -1 when out
// of range. Without this, any write that addresses urlsJson by a live index
// (e.g. savePickedSelector) lands on the wrong row whenever a disabled/unsafe
// URL precedes the target.
function configIndexForTab(arr, tabIndex) {
    if (!Array.isArray(arr) || tabIndex < 0) return -1;
    let seen = 0;
    for (let i = 0; i < arr.length; i++) {
        if (isLiveTab(arr[i])) {
            if (seen === tabIndex) return i;
            seen++;
        }
    }
    return -1;
}

// Same shape as parseTabs but no URL filter — profile rows aren't URLs.
function parseAuthProfiles(jsonStr) {
    try {
        const arr = JSON.parse(jsonStr || "[]");
        return Array.isArray(arr) ? arr : [];
    } catch (e) {
        console.warn("iframe-plasma: bad authProfilesJson:", e.message);
        return [];
    }
}

// Pure form of resolveTheme(): given the configured themeMode and the
// resolved KDE backgroundColor (as {r, g, b} in 0..1), return "light" or
// "dark". The "auto" branch uses Rec. 601 relative luminance with a 0.5
// midpoint.
function pickThemeForBackground(mode, bgColor) {
    if (mode === "light" || mode === "dark") return mode;
    if (!bgColor) return "dark";
    const r = (typeof bgColor.r === "number") ? bgColor.r : 0;
    const g = (typeof bgColor.g === "number") ? bgColor.g : 0;
    const b = (typeof bgColor.b === "number") ? bgColor.b : 0;
    const lightness = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return lightness < 0.5 ? "dark" : "light";
}

// Substitute every `${theme}` occurrence in url with theme. Tab-url
// re-evaluates this on every navigation so KDE colour-scheme flips
// propagate without restart.
function substituteTheme(url, theme) {
    return String(url).replace(/\$\{theme\}/g, theme);
}

// Same heuristic main.qml's toolbar uses to gate Time-range / Refresh
// dropdowns: only enable them for Grafana-shaped URLs. Matches /d/ and
// /d-solo/ followed by an alphanumeric uid segment.
//
// Drop the `#fragment` before scanning: a hash-routed share URL like
// `https://example.com/page#/d/abc/dashboard` would otherwise false-
// positive as Grafana and expose Grafana-only affordances (thumbnail
// presets, "Edit Grafana settings…" toolbutton) on a non-Grafana card.
// Same regex-terminator/fragment-bleed bug-class as Runs #15/#19.
function isGrafanaEmbed(u) {
    if (!u) return false;
    const s = String(u);
    const hashIdx = s.indexOf('#');
    const base = hashIdx === -1 ? s : s.slice(0, hashIdx);
    return /\/d(-solo)?\/[A-Za-z0-9_-]+\//.test(base);
}

// Concise display form of a tab URL for the config-card header subtitle:
// drop the scheme, the query string, and the #fragment, keeping host +
// path. Turns a noisy embed URL
//   https://grafana.example.com/d-solo/abc/dash?orgId=1&panelId=27&…
// into a scannable
//   grafana.example.com/d-solo/abc/dash
// The query/fragment carry the long, low-signal bits (orgId, theme,
// refresh, kiosk, var-*, the _ifp_ sentinels), so dropping them is exactly
// what keeps the subtitle from running off the card on a wide screen.
// Pure string slicing — no `new URL()`, so a half-typed "https://"
// placeholder collapses to "" and the caller hides the empty subtitle.
function displayUrl(u) {
    let s = String(u || "");
    const hash = s.indexOf('#');
    if (hash !== -1) s = s.slice(0, hash);
    const q = s.indexOf('?');
    if (q !== -1) s = s.slice(0, q);
    s = s.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "");   // strip scheme
    return s.replace(/\/+$/, "");                    // drop trailing slash(es)
}

// Classifier for urlsJson Apply events. Returns true when `newArr` differs
// from `oldArr` ONLY in metadata fields (label, thumb*, popup*); false when
// the change is structural — different length, a row's URL or
// authProfileId differs, or the rows have been reordered. Structural
// changes require a Repeater rebuild on the plasmoid side (new
// WebEngineProfile bindings, fresh URL navigations); metadata-only
// changes can be applied in place to the live tab objects without
// destroying any WebEngineView. See main.qml's onUrlsJsonChanged.
//
// Treats null/undefined/non-array inputs as structural (caller falls
// back to the rebuild path, which is safe).
//
// Identity by INDEX (positional). A move (swap rows 0 and 1) is
// structural — the WebTabs at those indices would need to switch
// profile/URL.
function isMetadataOnlyTabsChange(oldArr, newArr) {
    if (!Array.isArray(oldArr) || !Array.isArray(newArr)) return false;
    if (oldArr.length !== newArr.length) return false;
    for (let i = 0; i < oldArr.length; i++) {
        const o = oldArr[i] || {};
        const n = newArr[i] || {};
        // The URL string drives navigation. Even a query-string tweak
        // is a re-navigation, so it counts as structural for delegate
        // purposes (the WebTab would .load() the new URL anyway).
        if ((o.url || "") !== (n.url || "")) return false;
        // authProfileId selects the WebEngineProfile a delegate binds
        // to. Switching profiles mid-flight isn't supported in our
        // WebTab — the binding re-evaluates and Chromium re-attaches,
        // typically losing in-flight requests. Force the rebuild path.
        if ((o.authProfileId || "") !== (n.authProfileId || "")) return false;
    }
    return true;
}

// Auto-cycle stepper. Given the current tab index and the live `tabs`
// array, return the next index whose tab is not marked
// thumbMode="excluded" AND not present in the optional
// `runtimeExcluded` set (live keyword-match exclusions, session-only —
// see main.qml's _runtimeExcluded map). Returns -1 when no such tab
// exists (zero/one tab, every non-current tab excluded, etc.). Modulo
// handles wrap-around so currentIndex==tabs.length-1 still finds tab 0.
//
// `runtimeExcluded` accepts a JS Set, a plain object used as
// {idx: true}, or null/undefined for "no live exclusions". Detection
// is duck-typed (`.has` for Set, `[idx]` for plain objects) so callers
// don't need to allocate a Set when an existing map is at hand.
function nextCycleTabIndex(currentIndex, tabs, runtimeExcluded) {
    if (!Array.isArray(tabs) || tabs.length < 2) return -1;
    const n = tabs.length;
    // Normalise currentIndex (the live binding can briefly be stale
    // after a tab deletion).
    const start = ((currentIndex % n) + n) % n;
    const hasLiveCheck = runtimeExcluded != null;
    const setLike = hasLiveCheck && typeof runtimeExcluded.has === "function";
    for (let step = 1; step < n; step++) {
        const candidate = (start + step) % n;
        const t = tabs[candidate];
        if (!t || t.thumbMode === "excluded") continue;
        if (hasLiveCheck) {
            const live = setLike
                ? runtimeExcluded.has(candidate)
                : !!runtimeExcluded[candidate];
            if (live) continue;
        }
        return candidate;
    }
    return -1;
}
