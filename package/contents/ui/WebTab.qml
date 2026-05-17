/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtQuick.Layouts
import QtWebEngine
import org.kde.kirigami as Kirigami

Item {
    id: tab

    property var tabConfig: ({})
    property WebEngineProfile profile
    property string autheliaHost: ""
    property int zoomPct: 100
    property url url
    property int debugPort: 0

    // True once the user clicked "Log in here" — suppresses the overlay for
    // subsequent Authelia subpages (TOTP, WebAuthn) until we land off-host.
    property bool loginInProgress: false

    // Live load state — surfaced to the tab bar so the leading status dot can
    // reflect it. Values: "idle" | "loading" | "ok" | "err" | "auth".
    property string loadStatus: "idle"

    // "" → no override (chip follows URL); "off"; or an interval like "30s".
    property string userRefreshChoice: ""

    // Last-load metrics, captured from window.performance after each success.
    // httpStatus stays 0 until the JS callback returns; cross-origin nav can
    // wipe it back to 0 (responseStatus only available for same-origin docs).
    property int    httpStatus: 0
    property int    latencyMs:  0
    readonly property string currentHost: {
        try { return new URL(String(webview.url)).host } catch (e) { return "" }
    }
    readonly property bool tlsOk: String(webview.url).startsWith("https://")

    readonly property alias webView: webview

    signal authRequired(string originalUrl)
    signal basicAuthRequested(var request)

    function reload() { webview.reload() }
    function hardReload() { webview.triggerWebAction(WebEngineView.ReloadAndBypassCache) }
    function openExternal() { Qt.openUrlExternally(webview.url) }

    // --- Live time-range / refresh manipulation (toolbar overrides) ---------
    // Both functions mutate webview.url in place — Grafana picks up the new
    // params on reload. The configured tab URL (in urlsJson) is NOT changed,
    // so reopening the popup or restarting plasmashell restores the original.

    // Returns the unit suffix of `from=now-Xu&to=now` (e.g. "24h"), or
    // "custom" for non-standard from/to, or "" if no time params at all.
    readonly property string currentTimeRange: {
        const u = String(webview.url);
        const from = _readQuery(u, 'from');
        const to   = _readQuery(u, 'to');
        if (!from && !to) return '';
        const m = from.match(/^now-(\d+[smhdwMy])$/);
        if (m && to === 'now') return m[1];
        return 'custom';
    }

    // userRefreshChoice wins over the URL: Grafana's TimeSrv re-injects
    // `refresh=<dashboard-default>` via history.replaceState ~1 s after
    // each load, so reading the URL alone would let the chip flip back
    // to the wrong value moments after the user picks Off.
    readonly property string currentRefreshInterval: {
        if (tab.userRefreshChoice === "off")  return "";
        if (tab.userRefreshChoice.length > 0) return tab.userRefreshChoice;
        return _readQuery(String(webview.url), 'refresh');
    }

    // Assigning the same string to `webview.url` is a no-op; reload
    // instead so the dropdown selection always takes visible effect.
    function _navigate(newStr) {
        if (String(webview.url) === newStr) {
            webview.reload();
        } else {
            webview.url = newStr;
        }
    }

    // Manual query-string edit. QML's V4 JavaScript engine has a buggy
    // URLSearchParams: `delete()` / `set()` modifications silently fail
    // to propagate back to `url.toString()`. `updates` maps key → value
    // (null/undefined removes; string sets). Preserves unrelated params,
    // the hash fragment, and flag-style params (`&kiosk` with no value).
    function _editQuery(urlStr, updates) {
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
            for (const p of pairs) {
                const eq = p.indexOf('=');
                const k = eq === -1 ? p : p.slice(0, eq);
                if (k in updates) {
                    if (!handled[k]) {
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
                if (!handled[k] && updates[k] !== null && updates[k] !== undefined) {
                    out.push(k + '=' + encodeURIComponent(updates[k]));
                }
            }
            return path + (out.length ? '?' + out.join('&') : '') + hash;
        } catch (e) {
            console.warn("iframe-plasma: _editQuery error:", e.message);
            return urlStr;
        }
    }

    function _readQuery(urlStr, name) {
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

    // `range` is a preset like "24h", a `{from, to}` object, or "" to
    // revert from/to to whatever the configured `tab.url` had.
    function setTimeRange(range) {
        try {
            let updates;
            if (typeof range === 'string' && range.length > 0) {
                updates = { from: 'now-' + range, to: 'now' };
            } else if (range && typeof range === 'object') {
                updates = { from: range.from || 'now-1h', to: range.to || 'now' };
            } else {
                const origFrom = _readQuery(String(tab.url), 'from');
                const origTo   = _readQuery(String(tab.url), 'to');
                updates = {
                    from: origFrom ? origFrom : null,
                    to:   origTo   ? origTo   : null
                };
            }
            _navigate(_editQuery(String(webview.url), updates));
        } catch (e) { console.warn("iframe-plasma: setTimeRange error:", e.message); }
    }

    // `interval` is "" / "off" (disable), or a Grafana interval like "30s".
    // Disabling can't be done by URL alone — see the in-page user-script
    // in `Component.onCompleted` on the WebEngineView for the workaround.
    function setRefreshInterval(interval) {
        try {
            const useInterval = typeof interval === 'string'
                                && interval.length > 0
                                && interval !== 'off';
            tab.userRefreshChoice = useInterval ? interval : "off";

            // runJavaScript defaults to an isolated world in Qt 6 — must
            // target MainWorld so the page's history-patching code sees
            // the flag.
            webview.runJavaScript("window.__iframePlasmaRefreshOff = "
                + (useInterval ? "false" : "true") + ";",
                WebEngineScript.MainWorld);

            _navigate(_editQuery(String(webview.url),
                { refresh: useInterval ? interval : '' }));
        } catch (e) { console.warn("iframe-plasma: setRefreshInterval error:", e.message); }
    }

    function onAutheliaHost(currentUrl) {
        if (!tab.autheliaHost || tab.autheliaHost.length === 0) return false;
        try {
            const host = new URL(currentUrl).host;
            return host === tab.autheliaHost
                || host.endsWith("." + tab.autheliaHost);
        } catch (e) {
            return false;
        }
    }

    WebEngineView {
        id: webview
        anchors.fill: parent
        profile: tab.profile
        url: tab.url
        zoomFactor: Math.max(0.25, Math.min(5.0, tab.zoomPct / 100.0))

        settings.javascriptEnabled: true
        settings.localStorageEnabled: true
        settings.pluginsEnabled: false

        // Suppress Grafana's auto-refresh URL push.
        //
        // Grafana's TimeSrv re-injects `refresh=<dashboard-default>` via
        // `history.replaceState` ~1 s after each dashboard load. There is
        // no URL-only sentinel for "off" (grafana/grafana#4725, #9016,
        // #41329, #101412 — all declined over 8 years). Workaround: patch
        // `history.{push,replace}State` at DocumentCreation so any URL
        // Grafana writes has `refresh=` stripped, gated on the page-side
        // flag `__iframePlasmaRefreshOff` set by setRefreshInterval().
        //
        // WebEngineScript is a value type in Qt 6 and can't be inlined in
        // QML — must build it imperatively via the WebEngine.script() factory.
        Component.onCompleted: {
            const s = WebEngine.script();
            s.name = "iframe-plasma-refresh-control";
            s.injectionPoint = WebEngineScript.DocumentCreation;
            s.worldId = WebEngineScript.MainWorld;
            s.runOnSubFrames = false;
            s.sourceCode =
                "(function(){\n" +
                "  if (window.__iframePlasmaRefreshPatched) return;\n" +
                "  window.__iframePlasmaRefreshPatched = true;\n" +
                "  if (typeof window.__iframePlasmaRefreshOff === 'undefined')\n" +
                "    window.__iframePlasmaRefreshOff = false;\n" +
                "  const origRS = history.replaceState.bind(history);\n" +
                "  const origPS = history.pushState.bind(history);\n" +
                "  const strip = function(u){\n" +
                "    if (typeof u !== 'string' || !u.length) return u;\n" +
                "    if (!window.__iframePlasmaRefreshOff) return u;\n" +
                "    return u\n" +
                "      .replace(/([?&])refresh=[^&#]*/g, function(_, sep){ return sep === '?' ? '?' : ''; })\n" +
                "      .replace(/&&+/g, '&')\n" +
                "      .replace(/\\?&/, '?')\n" +
                "      .replace(/[?&]$/, '');\n" +
                "  };\n" +
                "  history.replaceState = function(s, t, u){ return origRS(s, t, strip(u)); };\n" +
                "  history.pushState    = function(s, t, u){ return origPS(s, t, strip(u)); };\n" +
                "})();";
            webview.userScripts.insert(s);
        }

        onLoadingChanged: function(info) {
            if (info.status === WebEngineView.LoadStartedStatus) {
                console.info("iframe-plasma[load] STARTED url=" + info.url);
                tab.loadStatus = "loading";
                if (!tab.loginInProgress) statusOverlay.showLoading();
            } else if (info.status === WebEngineView.LoadSucceededStatus) {
                const finalUrl = String(webview.url);
                const onAuthelia = tab.onAutheliaHost(finalUrl);
                console.info("iframe-plasma[load] SUCCEEDED finalUrl=" + finalUrl
                    + " onAuthelia=" + onAuthelia + " title=\"" + webview.title + "\"");

                if (onAuthelia) {
                    if (!tab.loginInProgress) {
                        tab.loadStatus = "auth";
                        statusOverlay.showAuthRequired();
                        tab.authRequired(String(tab.url));
                    } else {
                        tab.loadStatus = "ok";
                        statusOverlay.hide();
                    }
                } else {
                    tab.loginInProgress = false;
                    tab.loadStatus = "ok";
                    statusOverlay.hide();
                }
                tab._captureNavTiming();
            } else if (info.status === WebEngineView.LoadFailedStatus) {
                console.warn("iframe-plasma[load] FAILED url=" + info.url
                    + " code=" + info.errorCode + " msg=" + info.errorString);
                tab.loadStatus = "err";
                statusOverlay.showError(info.errorString || "Load failed");
            }
        }

        onAuthenticationDialogRequested: function(request) {
            console.info("iframe-plasma[auth] dialog requested type=" + request.type
                + " url=" + request.url + " realm=" + request.realm);
            tab.basicAuthRequested(request);
        }

        // Open user-clicked links externally; iframe sub-resources still load normally
        onNewWindowRequested: function(request) {
            Qt.openUrlExternally(request.requestedUrl);
            request.action = WebEngineNewWindowRequest.IgnoreRequest;
        }
    }

    StatusOverlay {
        id: statusOverlay
        anchors.fill: parent
        onReloadClicked: webview.reload()
        onOpenExternalClicked: Qt.openUrlExternally(tab.url)
        onLoginClicked: tab.loginInProgress = true
    }

    // Read responseStatus + duration from the PerformanceNavigationTiming entry.
    // Chromium-only API — Firefox/Safari return undefined here, no consequence
    // since we ship our own Chromium.
    function _captureNavTiming() {
        webview.runJavaScript(
            "(function(){try{var n=performance.getEntriesByType('navigation')[0];" +
            "return n?{status:n.responseStatus||0,duration:Math.round(n.duration||0)}:null;}catch(e){return null;}})()",
            function(result) {
                if (result) {
                    tab.httpStatus = result.status || 0;
                    tab.latencyMs = result.duration || 0;
                } else {
                    tab.httpStatus = 0;
                    tab.latencyMs = 0;
                }
            }
        );
    }

    Component.onCompleted: {
        if (tab.debugPort > 0) {
            // remote debugging is enabled via env var when plasmashell starts;
            // we just surface the URL here as a hint
            console.info("iframe-plasma: DevTools at http://localhost:" + tab.debugPort);
        }
    }
}
