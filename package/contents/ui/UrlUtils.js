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
// local files, so they're filtered out early.
function isSafeTabUrl(s) {
    if (typeof s !== "string") return false;
    return /^https?:\/\//i.test(s);
}

// JSON.parse with a defensive guard: returns the parsed array (with
// unsafe-URL rows filtered) or [] on any failure. Logs to console.warn so
// users debugging a broken config get a journal breadcrumb.
function parseTabs(jsonStr) {
    try {
        const arr = JSON.parse(jsonStr || "[]");
        if (Array.isArray(arr)) return arr.filter(t => t && isSafeTabUrl(t.url));
    } catch (e) {
        console.warn("iframe-plasma: bad urlsJson:", e.message);
    }
    return [];
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
function isGrafanaEmbed(u) {
    if (!u) return false;
    return /\/d(-solo)?\/[A-Za-z0-9_-]+\//.test(String(u));
}
