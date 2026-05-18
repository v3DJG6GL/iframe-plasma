/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtWebEngine

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
    // Cleared at every LoadStartedStatus, set true by onCertificateError.
    // Without this, tlsOk was a pure scheme-prefix check — a self-signed /
    // expired / hostname-mismatched server painted green during the load
    // window and stayed green if the toolbar wasn't re-evaluated after the
    // error fired. The lock chip is the operator's primary TLS-trust signal,
    // so derive it from (loadSucceeded || authelia-overlay) && https && no
    // recorded cert error for this navigation.
    property bool lastCertError: false
    readonly property bool tlsOk: (tab.loadStatus === "ok" || tab.loadStatus === "auth")
                                  && String(webview.url).startsWith("https://")
                                  && !tab.lastCertError

    readonly property alias webView: webview

    signal authRequired(string originalUrl)
    signal basicAuthRequested(var request)

    function reload() { webview.reload() }
    function hardReload() { webview.triggerWebAction(WebEngineView.ReloadAndBypassCache) }
    // Same scheme allowlist as onNewWindowRequested — if a redirect chain ever
    // lands the view on a non-http(s) URL (data:, file:, custom xdg handlers),
    // refuse to hand it off to the system URI dispatcher.
    function openExternal() {
        const u = String(webview.url);
        const scheme = u.split(":", 1)[0].toLowerCase();
        if (scheme === "http" || scheme === "https") {
            Qt.openUrlExternally(webview.url);
        } else {
            console.warn("iframe-plasma[nav] refusing openExternal; scheme=" + scheme);
        }
    }

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
                { refresh: useInterval ? interval : null }));
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
        // Defense-in-depth: parseTabs already rejects non-http(s) entries
        // before they reach here, but pin the scheme guard at the binding
        // so a future caller-path can't smuggle data:/file:/javascript:
        // into the shared profile.
        url: /^https?:\/\//i.test(String(tab.url)) ? tab.url : "about:blank"
        zoomFactor: Math.max(0.25, Math.min(5.0, tab.zoomPct / 100.0))

        settings.javascriptEnabled: true
        settings.localStorageEnabled: true
        settings.pluginsEnabled: false
        // Defense-in-depth: pin the hardened defaults explicitly so future
        // Qt-WebEngine default-flips can't silently re-enable these.
        settings.localContentCanAccessFileUrls: false
        settings.localContentCanAccessRemoteUrls: false
        settings.allowRunningInsecureContent: false
        settings.javascriptCanOpenWindows: false
        settings.javascriptCanAccessClipboard: false
        settings.javascriptCanPaste: false
        // pdfium is a recurring Chromium CVE target (e.g. CVE-2023-4863,
        // CVE-2024-4671); the widget never legitimately needs the in-page
        // PDF viewer, so disable that attack surface entirely.
        settings.pdfViewerEnabled: false
        // WebRTC isn't used here; without this pin Qt's default STUN
        // gathering enumerates every LAN interface and leaks the kiosk's
        // internal-network topology to any JS that opens an RTCPeerConnection.
        settings.webRTCPublicInterfacesOnly: true

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

            // Hide Grafana's per-panel 3-dot menu button (kebab) when the
            // URL carries our internal sentinel `_ifp_hidePanelMenu=1`.
            //
            // Grafana has no URL flag for this: kiosk mode only hides
            // dashboard chrome, /d-solo keeps the panel header (which is
            // what we want — we keep the title visible), and the feature
            // is asked-for in #12019 (open since 2018) with the Grafana
            // team explicitly recommending CSS as the only workaround.
            //
            // Selectors verified stable from Grafana 9.5 through main:
            //   [data-testid^="data-testid Panel menu "]    titled panels
            //     (testid value is `Panel menu <title>` — prefix match
            //     with trailing space to avoid matching "Panel menu item")
            //   [data-testid="panel-menu-button"]            untitled fallback
            //   button[aria-label^="Menu for panel "]        i18n safety net
            //   [data-testid^="data-testid Panel menu item "]
            //     the dropdown itself, portal-rendered to document.body
            //     (so a panel-scoped rule would miss it if the menu was
            //     already open when the style landed).
            //
            // Sources: PanelMenu.tsx + e2e-selectors/components.ts on
            // grafana/grafana at tags v12.0.0, v12.4.0, main.
            const hp = WebEngine.script();
            hp.name = "iframe-plasma-hide-panel-menu";
            hp.injectionPoint = WebEngineScript.DocumentCreation;
            hp.worldId = WebEngineScript.MainWorld;
            hp.runOnSubFrames = false;
            hp.sourceCode =
                "(function(){\n" +
                "  if (window.__ifpPanelMenuStyled) return;\n" +
                // Gate on the sentinel — same URL is reused for tabs that
                // want the menu visible, and we don't want CSS bleed.
                "  try { if ((window.location.search||'').indexOf('_ifp_hidePanelMenu=1') === -1) return; }\n" +
                "  catch(e) { return; }\n" +
                "  window.__ifpPanelMenuStyled = true;\n" +
                "  var css = '" +
                "[data-testid^=\"data-testid Panel menu \"]," +
                "[data-testid=\"panel-menu-button\"]," +
                "button[aria-label^=\"Menu for panel \"]," +
                "[data-testid^=\"data-testid Panel menu item \"]" +
                "{display:none!important;}';\n" +
                "  function inject(){\n" +
                "    if (document.getElementById('ifp-panel-menu-style')) return;\n" +
                "    var el = document.createElement('style');\n" +
                "    el.id = 'ifp-panel-menu-style';\n" +
                "    el.textContent = css;\n" +
                "    (document.head || document.documentElement).appendChild(el);\n" +
                "  }\n" +
                // At DocumentCreation the head may not exist yet; defer
                // to DOMContentLoaded if the document is still parsing.
                "  if (document.readyState === 'loading') {\n" +
                "    document.addEventListener('DOMContentLoaded', inject, { once: true });\n" +
                "  } else {\n" +
                "    inject();\n" +
                "  }\n" +
                "})();";
            webview.userScripts.insert(hp);
        }

        onLoadingChanged: function(info) {
            if (info.status === WebEngineView.LoadStartedStatus) {
                console.info("iframe-plasma[load] STARTED url=" + info.url);
                tab.loadStatus = "loading";
                tab.lastCertError = false;
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

        // Bounded one-shot reload after a renderer crash. Without a handler
        // the view just goes blank — both a DoS vector (hostile page crashes
        // its own renderer to disable the widget) and a forensics gap. Cap at
        // one retry per session to avoid a crash-loop hammering plasmashell.
        property bool _renderRetried: false
        onRenderProcessTerminated: function(status, exitCode) {
            console.warn("iframe-plasma[render] terminated status=" + status
                + " exitCode=" + exitCode + " retried=" + _renderRetried);
            if (status !== WebEngineView.NormalTerminationStatus && !_renderRetried) {
                _renderRetried = true;
                webview.reload();
            }
        }

        onAuthenticationDialogRequested: function(request) {
            console.info("iframe-plasma[auth] dialog requested type=" + request.type
                + " url=" + request.url + " realm=" + request.realm);
            tab.basicAuthRequested(request);
        }

        // Default action for an unhandled certificateError in Qt 6 is reject;
        // record the event so tlsOk falls to ⚠ instead of staying green from
        // the stale onLoadStartedStatus url prefix. Explicitly reject for
        // clarity (the C0 widening + scheme allowlist already block dataloss
        // paths, so we never want to ignoreCertificateError).
        onCertificateError: function(error) {
            console.warn("iframe-plasma[cert] error type=" + error.type
                + " url=" + error.url + " overridable=" + error.overridable
                + " desc=" + error.description);
            tab.lastCertError = true;
            error.rejectCertificate();
        }

        // Defense-in-depth: deny every page-driven permission upgrade. The
        // widget is a passive dashboard viewer with no UX path to surface a
        // permission prompt, so a panel that calls getUserMedia / geolocation
        // / notifications must never silently inherit a future Qt default-
        // grant. Cover both per-origin (onFeaturePermissionRequested) and
        // per-frame (onPermissionRequested, Qt 6.8+) shapes.
        onFeaturePermissionRequested: function(securityOrigin, feature) {
            console.warn("iframe-plasma[perm] denied feature=" + feature
                + " origin=" + securityOrigin);
            webview.grantFeaturePermission(securityOrigin, feature, false);
        }
        onPermissionRequested: function(perm) {
            console.warn("iframe-plasma[perm] denied permission=" + perm.permissionType
                + " origin=" + perm.origin);
            perm.deny();
        }
        // Fullscreen takeover by a hostile dashboard could mimic the lock
        // screen / fake an Authelia prompt; reject unconditionally.
        onFullScreenRequested: function(request) {
            console.warn("iframe-plasma[fs] rejected fullScreen request toggleOn=" + request.toggleOn);
            request.reject();
        }
        // Reject custom-protocol registration; widget never wants page-driven
        // mailto/web+xxx hijacking.
        onRegisterProtocolHandlerRequested: function(request) {
            console.warn("iframe-plasma[proto] rejected scheme=" + request.scheme
                + " url=" + request.url);
            request.reject();
        }
        // Reject page-initiated file dialogs — closes the exfiltration vector
        // from a compromised panel that auto-clicks an <input type=file>.
        onFileDialogRequested: function(request) {
            console.warn("iframe-plasma[file] rejected dialog mode=" + request.mode);
            request.dialogReject();
        }
        // Suppress the default Chromium context menu. Kiosk has no need for
        // Inspect / View source / Save link / Save image, and a bystander
        // right-click otherwise exposes inline secrets and reaches a
        // file-save dialog that bypasses onDownloadRequested under some
        // Qt 6.x builds.
        onContextMenuRequested: function(request) {
            console.info("iframe-plasma[ctx] suppressed menu pos=" + request.position
                + " mediaType=" + request.mediaType);
            request.accepted = true;
        }
        // Reject client-certificate auto-selection. With the shared SSO
        // profile any imported ~/.pki cert becomes a candidate; Qt's
        // default for a single-match CertificateRequest is silent select,
        // which would leak the kiosk identity to any origin that flips on
        // optional client-auth.
        onSelectClientCertificate: function(selection) {
            console.warn("iframe-plasma[cert] rejected client-cert request host="
                + selection.host + " count=" + selection.certificates.length);
            selection.selectNone();
        }
        // Cancel WebAuthn ceremonies — the system FIDO/passkey prompt
        // escapes the kiosk chrome and the widget never legitimately needs
        // WebAuthn (basic-auth via interceptor only).
        onWebAuthUxRequested: function(request) {
            console.warn("iframe-plasma[webauth] cancelled state=" + request.state);
            request.cancel();
        }
        // Suppress page-controlled tooltips. Default Qt behaviour renders the
        // tooltip outside the WebEngineView's clipped geometry (it's a top-
        // level platform widget), so a compromised dashboard can paint
        // attacker-controlled text — fake UI prompts, spoofed paths — over
        // arbitrary screen regions next to the kiosk. `accepted = true`
        // tells Qt the QML side took ownership and prevents the default
        // tooltip from appearing.
        onTooltipRequested: function(request) {
            request.accepted = true;
        }
        // Reject `<input type=color>` (and any JS-driven .click() on one).
        // The default action opens the platform's native colour picker as a
        // modal top-level window — same modal-over-kiosk hazard as a
        // surprise auth dialog, with no UX path to surface it to the
        // operator. The widget never legitimately needs a colour picker.
        onColorDialogRequested: function(request) {
            console.warn("iframe-plasma[color] rejected color dialog");
            request.dialogReject();
        }
        // Reject getDisplayMedia / screen-capture requests outright. The
        // generic permissionRequested/featurePermissionRequested denials
        // already cover most permission flavours, but desktopMediaRequested
        // is a separate signal (Qt 6.8+) that, if unhandled, can present
        // the screen-picker chooser even before the permission dialog
        // fires. A hostile page calling navigator.mediaDevices.getDisplay-
        // Media() over the SSO origin must not get any UI surface here.
        onDesktopMediaRequested: function(request) {
            console.warn("iframe-plasma[dispmedia] cancelled screen-capture request");
            request.cancel();
        }
        // Reject File System Access API (showOpenFilePicker / showSave-
        // FilePicker / showDirectoryPicker). FileDialogRequested handles
        // the legacy <input type=file>, but fileSystemAccessRequested is
        // a separate request type that wraps Chromium's modern FS-Access
        // API — same exfiltration / write surface, separate hook. The
        // widget never legitimately writes to disk.
        onFileSystemAccessRequested: function(request) {
            console.warn("iframe-plasma[fs-access] rejected origin=" + request.origin
                + " handleType=" + request.handleType);
            request.reject();
        }
        // Reject legacy storage-quota upgrades (window.webkitStorageInfo /
        // navigator.webkitPersistentStorage). Deprecated in modern Chromium
        // but the signal still fires from old pages. Default is to ignore,
        // but explicit reject pins it against future Qt default-flips.
        onQuotaRequested: function(request) {
            console.warn("iframe-plasma[quota] rejected origin=" + request.origin
                + " requestedSize=" + request.requestedSize);
            request.reject();
        }

        // Open user-clicked links externally; iframe sub-resources still load normally.
        // Restrict to web/mail/tel schemes — anything else (e.g. file:, smb:,
        // vnc:, ssh:, custom xdg handlers) could let a compromised page invoke
        // arbitrary system URI handlers click-less from inside the embedded view.
        onNewWindowRequested: function(request) {
            const scheme = String(request.requestedUrl).split(":", 1)[0].toLowerCase();
            const safe = scheme === "http" || scheme === "https"
                      || scheme === "mailto" || scheme === "tel";
            if (safe) {
                Qt.openUrlExternally(request.requestedUrl);
            } else {
                console.warn("iframe-plasma[nav] blocked external open; scheme=" + scheme);
            }
            request.action = WebEngineNewWindowRequest.IgnoreRequest;
        }
    }

    StatusOverlay {
        id: statusOverlay
        anchors.fill: parent
        onReloadClicked: webview.reload()
        onOpenExternalClicked: openExternal()
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
