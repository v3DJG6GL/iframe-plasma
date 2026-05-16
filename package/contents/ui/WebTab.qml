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

    // Recognize Grafana relative ranges of the form `from=now-Xu&to=now`.
    // Returns the unit suffix (`24h`, `7d`, …) or `"custom"` if non-standard,
    // or empty string if no time params at all.
    readonly property string currentTimeRange: {
        const u = String(webview.url);
        try {
            const url = new URL(u);
            const from = url.searchParams.get('from') || '';
            const to   = url.searchParams.get('to')   || '';
            if (!from && !to) return '';
            const m = from.match(/^now-(\d+[smhdwMy])$/);
            if (m && to === 'now') return m[1];
            return 'custom';
        } catch (e) { return ''; }
    }

    // Current `refresh=...` value or "" if absent.
    readonly property string currentRefreshInterval: {
        const u = String(webview.url);
        try {
            const url = new URL(u);
            return url.searchParams.get('refresh') || '';
        } catch (e) { return ''; }
    }

    // Apply a time range. `range` is either a preset string like "24h" or a
    // `{from, to}` object for fully-custom Grafana grammar.
    function setTimeRange(range) {
        try {
            const url = new URL(String(webview.url));
            if (typeof range === 'string' && range.length > 0) {
                url.searchParams.set('from', 'now-' + range);
                url.searchParams.set('to', 'now');
            } else if (range && typeof range === 'object') {
                url.searchParams.set('from', range.from || 'now-1h');
                url.searchParams.set('to', range.to || 'now');
            } else {
                return;   // null/empty → leave as-is
            }
            webview.url = url.toString();
        } catch (e) { console.warn("iframe-plasma: setTimeRange error:", e.message); }
    }

    // Set or clear `refresh=`. Empty/null/"off" removes the param entirely
    // (Grafana issue #41329: empty refresh= triggers a stuck-loading bug).
    function setRefreshInterval(interval) {
        try {
            const url = new URL(String(webview.url));
            if (typeof interval === 'string' && interval.length > 0 && interval !== 'off') {
                url.searchParams.set('refresh', interval);
            } else {
                url.searchParams.delete('refresh');
            }
            webview.url = url.toString();
        } catch (e) { console.warn("iframe-plasma: setRefreshInterval error:", e.message); }
    }

    function onAutheliaHost(currentUrl) {
        if (!tab.autheliaHost || tab.autheliaHost.length === 0) return false;
        return currentUrl.indexOf("://" + tab.autheliaHost) !== -1
            || currentUrl.indexOf("." + tab.autheliaHost) !== -1;
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
