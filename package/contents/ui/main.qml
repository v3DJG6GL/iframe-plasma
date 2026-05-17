/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import QtWebEngine
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property bool inPanel: [
        PlasmaCore.Types.TopEdge,
        PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge,
        PlasmaCore.Types.LeftEdge
    ].includes(Plasmoid.location)

    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    switchWidth:  inPanel ? Number.POSITIVE_INFINITY : Kirigami.Units.gridUnit * 18
    switchHeight: inPanel ? Number.POSITIVE_INFINITY : Kirigami.Units.gridUnit * 12

    Plasmoid.icon: "applications-internet"

    // Tell the panel layout: don't reserve hover-indicator padding around the
    // applet — we want the raw slot for the compact rep so the WebEngineView
    // can reach the full panel thickness without dark strips above/below.
    // Confirmed pattern from plasma-workspace `appmenu` and `activitybar`.
    Plasmoid.constraintHints: Plasmoid.CanFillArea
    // Don't paint a panel tile behind the WebEngineView (Chromium renders its
    // own pixels). `ConfigurableBackground` keeps right-click → "Show
    // background" available for users who want one.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    // Parsed tab list, refreshed whenever config changes
    property var tabs: parseTabs(Plasmoid.configuration.urlsJson)
    property int currentTabIndex: Math.max(0, Math.min(Plasmoid.configuration.currentTabIndex, tabs.length - 1))

    // Named auth profiles. Re-parsed on config change.
    property var authProfiles: parseAuthProfiles(Plasmoid.configuration.authProfilesJson)

    function parseAuthProfiles(jsonStr) {
        try {
            const arr = JSON.parse(jsonStr || "[]");
            return Array.isArray(arr) ? arr : [];
        } catch (e) {
            console.warn("iframe-plasma: bad authProfilesJson:", e.message);
            return [];
        }
    }

    function profileById(id) {
        if (!id) return null;
        for (const p of root.authProfiles) {
            if (p.id === id) return p;
        }
        return null;
    }

    // Per-tab load status, fed by each WebTab's loadStatus property change.
    // Indexed by tab index. Values: "idle" | "loading" | "ok" | "err" | "auth".
    // Replace-whole-array on every set — QML doesn't notify on element mutation.
    property var tabStatuses: []
    function setTabStatus(idx, status) {
        const next = tabStatuses.slice();
        while (next.length <= idx) next.push("idle");
        next[idx] = status;
        tabStatuses = next;
    }

    toolTipMainText: {
        if (tabs.length === 0) return i18n("iframe Plasma");
        const cur = tabs[currentTabIndex];
        return cur && cur.label ? cur.label : i18n("iframe Plasma");
    }
    toolTipSubText: {
        if (tabs.length === 0) return i18n("No URLs configured");
        if (tabs.length === 1) return "";
        return i18np("1 tab", "%1 tabs (%2 active)", tabs.length, currentTabIndex + 1);
    }

    function parseTabs(jsonStr) {
        try {
            const arr = JSON.parse(jsonStr || "[]");
            if (Array.isArray(arr)) return arr.filter(t => t && t.url);
        } catch (e) {
            console.warn("iframe-plasma: bad urlsJson:", e.message);
        }
        return [];
    }

    function resolveTheme() {
        const mode = Plasmoid.configuration.themeMode;
        if (mode === "light" || mode === "dark") return mode;
        // auto: pick from KDE color scheme background lightness
        const bg = Kirigami.Theme.backgroundColor;
        const lightness = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b;
        return lightness < 0.5 ? "dark" : "light";
    }

    function resolveUrl(tab) {
        if (!tab || !tab.url) return "about:blank";
        return String(tab.url).replace(/\$\{theme\}/g, resolveTheme());
    }

    // Live session time-range from the popup's active WebTab — updates when
    // the user picks a different preset in the toolbar's time-range
    // dropdown. Used by resolveThumbUrl when thumbTimeRange === "auto" so
    // the panel-slot thumbnail follows the popup. Empty string when no
    // active tab or no session override.
    readonly property string activeTabSessionRange:
        (activeTab && activeTab.currentTimeRange) || ""

    // Like resolveUrl but additionally rewrites `from=`/`to=` query params
    // when the tab has a `thumbTimeRange` preset (e.g. "24h"). Used by the
    // panel-slot thumbnail only — the popup keeps using resolveUrl() so its
    // time range is whatever the URL itself specifies.
    //
    // `thumbTimeRange` semantics:
    //   - "" or "auto"     → follow the popup (use activeTabSessionRange
    //                         if this tab is the active one)
    //   - "5m"/"24h"/"7d"  → hard-override the URL's from/to for the
    //                         thumbnail; popup unaffected
    function resolveThumbUrl(tab) {
        if (!tab || !tab.url) return "about:blank";
        let url = String(tab.url);
        let range = tab.thumbTimeRange || "auto";
        // "auto" + previewTab matches the popup's active tab → use the
        // popup's live session range. Otherwise leave URL's own range alone.
        if (range === "auto") {
            const idx = root.currentTabIndex;
            if (root.tabs[idx] === tab && root.activeTabSessionRange.length > 0) {
                range = root.activeTabSessionRange;
            } else {
                range = ""; // keep URL's own from/to
            }
        }
        if (range.length > 0) {
            // Strip existing from/to (handles ?from= , &from= , ?to= , &to=).
            url = url.replace(/[?&]from=[^&]*/g, function(m) { return m.charAt(0) === '?' ? '?' : ''; });
            url = url.replace(/[?&]to=[^&]*/g,   function(m) { return m.charAt(0) === '?' ? '?' : ''; });
            url = url.replace(/\?&/, '?').replace(/[?&]$/, '');
            const sep = url.indexOf('?') === -1 ? '?' : '&';
            url = url + sep + 'from=now-' + range + '&to=now';
        }
        return url.replace(/\$\{theme\}/g, resolveTheme());
    }

    Connections {
        target: Plasmoid.configuration
        function onUrlsJsonChanged() {
            root.tabs = root.parseTabs(Plasmoid.configuration.urlsJson);
            if (root.currentTabIndex >= root.tabs.length) {
                root.setCurrentTab(Math.max(0, root.tabs.length - 1));
            }
            root.primeAuthProfiles();
        }
        function onAuthProfilesJsonChanged() {
            root.authProfiles = root.parseAuthProfiles(Plasmoid.configuration.authProfilesJson);
            root.primeAuthProfiles();
            root.reloadAll();
        }
        function onUseBasicAuthInjectionChanged() {
            root.syncInterceptor();
            if (Plasmoid.configuration.useBasicAuthInjection) root.primeAuthProfiles();
            root.reloadAll();
        }
    }

    Component.onCompleted: {
        // Run the one-shot legacy-auth migration BEFORE priming the
        // interceptor — converts per-URL basicAuthUser/rawAuthHeader to
        // named auth profiles, writes secrets to KWallet under
        // `profile:<uuid>`, and clears the legacy fields from urlsJson.
        Qt.callLater(function() {
            root.migrateLegacyAuth();
            const anyAuth = root.tabs.some(t => (t.authProfileId && t.authProfileId.length > 0));
            if (anyAuth) root.primeAuthProfiles();
            root.syncInterceptor();
        });
    }

    // Shared WebEngineProfile — persists cookies/cache across all tabs and survives
    // plasmashell restarts. Same-origin tabs coalesce into one renderer process.
    // Lazily-loaded C++ plugin: KWallet bridge + BasicAuth interceptor.
    // If the build/install hasn't happened yet, this stays null and basic-auth
    // degrades gracefully (Qt's default dialog still prompts the user).
    Loader {
        id: authSupportLoader
        source: "AuthSupport.qml"
        asynchronous: false
        onStatusChanged: if (status === Loader.Error) {
            console.warn("iframe-plasma: C++ auth plugin not available — basic-auth integration disabled. Build with cmake to enable.");
        }
    }
    readonly property var authSupport: authSupportLoader.item

    readonly property string profileStorageRoot: {
        // StandardPaths.writableLocation returns a QUrl ("file:///…") — strip the
        // scheme so QtWebEngine gets a real filesystem path, not a literal "file:" dir.
        const base = String(StandardPaths.writableLocation(StandardPaths.AppDataLocation))
                        .replace(/^file:\/\//, "");
        return base + "/iframe-plasma/" + (Plasmoid.id || 0);
    }

    WebEngineProfile {
        id: sharedProfile
        storageName: Plasmoid.metaData.pluginId + "-" + (Plasmoid.id || 0)
        offTheRecord: Plasmoid.configuration.privateBrowsing
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
        persistentStoragePath: root.profileStorageRoot
        httpUserAgent: Plasmoid.configuration.userAgentOverride.length > 0
            ? Plasmoid.configuration.userAgentOverride : ""
    }

    // Attach/detach the interceptor whenever the toggle or plugin availability changes.
    // Signal fired from root-level events; WebTab listens and reloads its view.
    // Cleaner than reaching into fullRepresentation's StackLayout from outside.
    signal reloadAllRequested()
    function reloadAll() { reloadAllRequested() }

    function syncInterceptor() {
        const enabled = Plasmoid.configuration.useBasicAuthInjection;
        console.info("iframe-plasma[sync] authSupport=" + (root.authSupport ? "available" : "null")
            + " useBasicAuthInjection=" + enabled);
        if (!root.authSupport) return;
        if (enabled) {
            const ok = root.authSupport.attachInterceptor(sharedProfile);
            console.info("iframe-plasma[sync] attachInterceptor returned " + ok);
        } else {
            const ok = root.authSupport.detachInterceptor(sharedProfile);
            console.info("iframe-plasma[sync] detachInterceptor returned " + ok);
        }
    }
    Connections {
        target: authSupportLoader
        function onLoaded() {
            // C++ plugin just became available — wire up the interceptor AND
            // populate the credential map. The earlier flow only attached the
            // interceptor; priming was only called if Component.onCompleted
            // had already run with tabs populated — a race the user can't see.
            root.syncInterceptor();
            root.migrateLegacyAuth();
            const anyAuth = root.tabs.some(t => (t.authProfileId && t.authProfileId.length > 0));
            if (anyAuth) {
                root.primeAuthProfiles();
                // Reload so the freshly-registered Authorization header is sent
                // on the next request — otherwise the initial load already
                // happened unauthenticated and went to Authelia.
                root.reloadAll();
            }
        }
    }

    // Prime the interceptor: walk profiles in use, group their target hosts
    // (from tabs that reference each profile), pull each profile's secret
    // from KWallet, and register everything via applyProfile.
    //
    // No-op if the C++ plugin isn't loaded.
    function primeAuthProfiles() {
        if (!root.authSupport) return;
        // Group hosts per profile-in-use.
        const profilesInUse = {};   // id -> { profile, hosts: [] }
        for (const t of root.tabs) {
            if (!t.authProfileId || !t.url) continue;
            let host;
            try { host = new URL(t.url).host; } catch (e) { continue; }
            const p = root.profileById(t.authProfileId);
            if (!p) continue;
            if (!profilesInUse[p.id]) profilesInUse[p.id] = { profile: p, hosts: [] };
            if (!profilesInUse[p.id].hosts.includes(host)) profilesInUse[p.id].hosts.push(host);
        }
        // Clear ALL registrations (covers profiles whose URLs got reassigned away).
        root.authSupport.clearCredentials();
        // Re-apply each in-use profile.
        for (const id in profilesInUse) {
            const { profile, hosts } = profilesInUse[id];
            const secrets = root.authSupport.getMap(root.authSupport.profileKey(id)) || {};
            const secret = secrets.password || secrets.bearerToken || secrets.rawHeader || "";
            if (secret.length === 0) {
                console.info("iframe-plasma[auth] profile " + id + " has no stored secret — skipping");
                continue;
            }
            root.authSupport.applyProfile(id, profile.authType || "basic",
                profile.username || "", secret, hosts);
        }
    }

    // Handler invoked from WebTab on every authenticationDialogRequested.
    // Contract: leave request.accepted=false to let Qt show its default prompt;
    // set accepted=true + dialogAccept(user,pw) to supply stored creds silently.
    function handleBasicAuth(request, tabConfig) {
        try {
            const profile = root.profileById(tabConfig.authProfileId);
            if (!profile) {
                console.info("iframe-plasma[auth] no profile -> letting Qt prompt");
                return;
            }
            // Qt's Basic-auth dialog only makes sense for the `basic` type.
            // Bearer / Raw profiles are pre-injected via the interceptor —
            // if a 401 still happens (e.g. wrong token), Qt would prompt the
            // user for user+password which can't fix it. Let Qt prompt
            // anyway in that case; user can cancel.
            if (profile.authType !== "basic") {
                console.info("iframe-plasma[auth] non-basic profile type=" + profile.authType
                    + " -> letting Qt prompt");
                return;
            }

            const reqHost = new URL(String(request.url)).host;
            const tabHost = new URL(tabConfig.url).host;
            if (reqHost.toLowerCase() !== tabHost.toLowerCase()) {
                console.info("iframe-plasma[auth] host mismatch -> letting Qt prompt");
                return;
            }
            const user = profile.username || "";
            if (user.length === 0) {
                console.info("iframe-plasma[auth] profile has no username -> letting Qt prompt");
                return;
            }
            const secrets = root.authSupport ? root.authSupport.getMap(root.authSupport.profileKey(profile.id)) : {};
            const pw = (secrets && secrets.password) || "";
            if (pw.length > 0) {
                request.accepted = true;
                request.dialogAccept(user, pw);
                console.info("iframe-plasma[auth] dialogAccept (profile=" + profile.id + ", user=" + user + ")");
            } else {
                console.info("iframe-plasma[auth] profile has no stored password -> letting Qt prompt");
            }
        } catch (e) {
            console.warn("iframe-plasma[auth] handler error:", e.message);
        }
    }

    // --- Legacy auth migration (one-shot at startup) -----------------------
    //
    // Pre-0.4.0 stored credentials per-URL in `basicAuthUser`/
    // `basicAuthPasswordPlaintext`/`rawAuthHeader` fields. 0.4.0 introduces
    // named profiles. This walks `urlsJson`, detects legacy fields, dedupes
    // by (host, username, rawHeader) signature so multiple tabs sharing the
    // same credential collapse into one profile, writes the secret to
    // KWallet under `profile:<uuid>`, and rewrites `urlsJson` to reference
    // profiles via `authProfileId`. Idempotent: skips tabs that already have
    // a non-empty authProfileId.
    function migrateLegacyAuth() {
        // Plugin must be live: writing secrets to KWallet and stripping legacy
        // fields without persisting them would silently drop credentials that
        // existed only in the old `basic:<host>` keys. The onLoaded handler
        // re-invokes this once authSupport is ready.
        if (!root.authSupport) return;

        let tabsRaw;
        try {
            tabsRaw = JSON.parse(Plasmoid.configuration.urlsJson || "[]");
            if (!Array.isArray(tabsRaw)) return;
        } catch (e) { return; }

        let profiles = root.parseAuthProfiles(Plasmoid.configuration.authProfilesJson);
        const byKey = {};
        // Pre-populate byKey from existing profiles so we re-use them on re-runs.
        for (const p of profiles) {
            // Use a synthesized signature based on profile type+username.
            // (Hosts vary per-tab — we just need to dedupe legacy fields.)
            const sig = (p.authType === "raw") ? ("raw:" + p.id) :
                                                  ("basic:" + (p.username || ""));
            byKey[sig] = p;
        }

        let mutated = false;
        for (const t of tabsRaw) {
            if (!t || t.authProfileId) continue;
            const hasLegacy = (t.basicAuthUser && t.basicAuthUser.length > 0) ||
                              (t.basicAuthPasswordPlaintext && t.basicAuthPasswordPlaintext.length > 0) ||
                              (t.rawAuthHeader && t.rawAuthHeader.length > 0);
            if (!hasLegacy) continue;

            let host = "";
            try { host = new URL(t.url).host; } catch (e) { /* keep "" */ }

            // Dedupe signature: raw header is unique per value; basic shares
            // by host+user (so 5 same-host same-user tabs → 1 profile).
            const sig = t.rawAuthHeader
                ? ("raw:" + t.rawAuthHeader.substring(0, 32))
                : ("basic:" + host + ":" + (t.basicAuthUser || ""));

            let p = byKey[sig];
            if (!p) {
                p = {
                    id: root.newUuid(),
                    name: host + (t.basicAuthUser ? " (" + t.basicAuthUser + ")"
                                                  : t.rawAuthHeader ? " (raw header)" : ""),
                    authType: t.rawAuthHeader ? "raw" : "basic",
                    username: t.basicAuthUser || "",
                    autheliaHost: Plasmoid.configuration.autheliaHost || ""
                };
                // Move the secret into KWallet under the new key.
                const oldKWalletPw = root.authSupport.get("basic:" + host) || "";
                const secret = t.rawAuthHeader || oldKWalletPw || t.basicAuthPasswordPlaintext || "";
                if (secret.length > 0) {
                    const map = {};
                    if (t.rawAuthHeader) map.rawHeader = secret;
                    else map.password = secret;
                    root.authSupport.setMap(root.authSupport.profileKey(p.id), map);
                }
                profiles.push(p);
                byKey[sig] = p;
                console.info("iframe-plasma[migrate] created profile id=" + p.id
                    + " name=" + p.name + " type=" + p.authType);
            }
            t.authProfileId = p.id;
            delete t.basicAuthUser;
            delete t.basicAuthPasswordPlaintext;
            delete t.rawAuthHeader;
            mutated = true;
        }

        if (mutated) {
            Plasmoid.configuration.authProfilesJson = JSON.stringify(profiles);
            Plasmoid.configuration.urlsJson = JSON.stringify(tabsRaw);
            console.info("iframe-plasma[migrate] persisted: " + profiles.length + " profile(s), " + tabsRaw.length + " tab(s)");
        }
    }

    // Simple v4 UUID (sufficient for profile identity — not security-critical).
    function newUuid() {
        function hex() { return Math.floor(Math.random() * 16).toString(16); }
        let s = "";
        for (let i = 0; i < 32; i++) {
            if (i === 8 || i === 12 || i === 16 || i === 20) s += "-";
            if (i === 12) { s += "4"; continue; }
            if (i === 16) { s += (8 + Math.floor(Math.random() * 4)).toString(16); continue; }
            s += hex();
        }
        return s;
    }

    // Auto-cycle through tabs ONLY while the popup is closed — the panel-slot
    // thumbnail (in "auto" preview mode) rotates through tabs in the background,
    // but the moment the user opens the widget the cycle pauses so they can
    // browse without the active tab being yanked out from under them.
    Timer {
        id: cycleTimer
        interval: Math.max(5, Plasmoid.configuration.autoCycleIntervalSec) * 1000
        running: Plasmoid.configuration.autoCycleEnabled
                 && root.tabs.length > 1
                 && !root.expanded
        repeat: true
        onTriggered: root.setCurrentTab((root.currentTabIndex + 1) % root.tabs.length)
    }

    // Cookie clearing per-host needs `profile.cookieStore` which QML doesn't
    // expose for QQuickWebEngineProfile. Phase 4 adds a small C++ helper on the
    // shared plugin to do this properly. For now the toolbar action falls back
    // to clearing the HTTP cache (which alone does not invalidate the Authelia
    // session cookie — by design, so a refresh after auth changes still works).
    function clearCacheAndReload() {
        sharedProfile.clearHttpCache();
        console.info("iframe-plasma: cleared HTTP cache");
        root.activeTab?.reload();
    }

    // The current tab index lives in two places: a runtime `root` property
    // (used everywhere as the binding source) and a kcfg-persisted value
    // (so the next session restores the same active tab).  Always update
    // both together — bare `root.currentTabIndex = N` would not survive
    // a restart, and bare kcfg write would skip the binding chain.
    function setCurrentTab(idx) {
        root.currentTabIndex = idx;
        Plasmoid.configuration.currentTabIndex = idx;
    }

    // Active WebTab reference. Set from inside fullRepresentation's
    // Component.onCompleted (the Repeater's id is scoped to that Component
    // and not reachable from this document scope otherwise).
    // Bound expression — re-evaluates on currentTabIndex or repeater.count change.
    property var activeTab: null

    // --- Keyboard shortcuts (scoped to popup-open so panel use isn't grabby) ---
    Shortcut {
        sequences: [StandardKey.Refresh]
        enabled: root.expanded
        onActivated: root.activeTab?.reload()
    }
    Shortcut {
        sequence: "Ctrl+Shift+R"
        enabled: root.expanded
        onActivated: root.activeTab?.hardReload()
    }
    Shortcut {
        sequence: "Ctrl+W"
        enabled: root.expanded
        onActivated: root.expanded = false
    }
    Shortcut {
        sequences: ["Ctrl+Tab", StandardKey.NextChild]
        enabled: root.expanded && root.tabs.length > 1
        onActivated: root.setCurrentTab((root.currentTabIndex + 1) % root.tabs.length)
    }
    Shortcut {
        sequences: ["Ctrl+Shift+Tab", StandardKey.PreviousChild]
        enabled: root.expanded && root.tabs.length > 1
        onActivated: root.setCurrentTab(
            (root.currentTabIndex - 1 + root.tabs.length) % root.tabs.length)
    }
    // Ctrl+1..9 → jump to tab N (Konsole/Dolphin convention).
    // Instantiator hosts non-Item delegates fine — one Shortcut per index,
    // each gated on its own slot being populated.
    Instantiator {
        model: 9
        active: root.expanded
        delegate: Shortcut {
            required property int index
            sequence: "Ctrl+" + (index + 1)
            enabled: root.tabs.length > index
            onActivated: root.setCurrentTab(index)
        }
    }

    // Compact representation — when the widget is on a Plasma panel.
    // Renders a live mini-WebEngineView showing one configured tab's URL at
    // panel-slot size. For Grafana URLs (d-solo + kiosk) the chart auto-scales
    // responsively to whatever viewport the slot gives it.
    //
    // Optional per-tab `thumbSelector` further crops the slot to just one CSS
    // element (e.g. `.u-wrap`) — the matched element is sized to 100vw × 100vh
    // and everything else is hidden, so uPlot natively redraws the chart at
    // slot size with no header / legend / footer eating the space. This
    // applies ONLY to the panel-slot view; the popup always shows the full URL.
    //
    // Shares sharedProfile with the popup so cookies/auth are reused.
    // When compactPreviewEnabled is off (or no tabs are configured) falls back
    // to the widget icon.
    compactRepresentation: Item {
        id: compact

        // Thumbnail tab source:
        //   - mode="auto"  (default) → follow the popup's currentTabIndex.
        //     QML's binding system handles auto-follow automatically:
        //     currentTabIndex change → previewTabIdx re-evaluates →
        //     previewTab → miniView.url → WebEngineView reloads.
        //   - mode="fixed" → use the saved compactPreviewTabIndex.
        readonly property string previewMode: Plasmoid.configuration.compactPreviewMode || "auto"
        readonly property int previewTabIdx: {
            if (root.tabs.length === 0) return 0;
            const cap = root.tabs.length - 1;
            if (previewMode === "auto") {
                return Math.max(0, Math.min(root.currentTabIndex, cap));
            }
            return Math.max(0, Math.min(
                Plasmoid.configuration.compactPreviewTabIndex, cap));
        }
        readonly property var previewTab: root.tabs.length > 0 ? root.tabs[previewTabIdx] : null
        readonly property bool previewLive: Plasmoid.configuration.compactPreviewEnabled
                                            && previewTab

        // Thumbnail mode → CSS selector. Presets target Grafana TimeSeries
        // (uPlot) panels; .u-wrap > canvas is the painted bitmap and is
        // guaranteed non-transparent (the .u-over / .u-under bug we hit
        // earlier). `custom` re-exposes the user's free-text selector.
        readonly property string thumbMode: (previewTab && previewTab.thumbMode) || "chartOnly"
        readonly property string thumbSelector: {
            const m = thumbMode;
            const custom = (previewTab && previewTab.thumbSelector) || "";
            switch (m) {
            case "chartOnly":     return ".u-wrap > canvas";
            case "chartWithAxes": return ".u-wrap";
            case "fullPanel":     return "";
            case "custom":        return custom;
            default:              return "";
            }
        }

        // Force a full reload when the mode changes, so applyThumbCrop is
        // triggered fresh via onLoadingChanged (the page is otherwise stable
        // and won't re-fire LoadSucceededStatus). Also covers the case where
        // the previous selector's MutationObserver was already torn down.
        onThumbSelectorChanged: {
            console.info("iframe-plasma[compact] thumbMode=" + thumbMode
                + " → selector=" + JSON.stringify(thumbSelector)
                + "; reloading miniView");
            if (miniLoader.item) miniLoader.item.reload();
        }

        // Panel-slot sizing. The canonical Plasma 6 rule (mirroring
        // libksysguard/CompactSensorFace.qml and applets/mediacontroller's
        // CompactRepresentation.qml):
        //
        //  - Long axis:  Layout.preferredWidth/Height = user-configured pixels;
        //                Layout.maximumWidth/Height pinned to the same value so
        //                the panel cannot shrink us under contention.
        //  - Cross axis: Layout.preferredWidth/Height = -1  (NEVER a pixel
        //                value — Plasma honours it even with `fillHeight: true`,
        //                shrinking the slot below the panel thickness and
        //                creating the dark strips we saw).
        //  - No implicitWidth / implicitHeight on the compact rep itself —
        //    they were a previous source of the same bug.
        //
        // Horizontal panel: width = configured, height = panel thickness.
        // Vertical panel:   height = configured, width = panel thickness.
        // Desktop (Planar): both axes = configured.
        readonly property bool horizontalPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        readonly property bool verticalPanel:   Plasmoid.formFactor === PlasmaCore.Types.Vertical

        // User-configured long-axis size (Configure → Display → Preview size).
        readonly property int longAxisPx: Plasmoid.configuration.compactPreviewLongAxisPx

        Layout.minimumWidth:  Kirigami.Units.iconSizes.smallMedium
        Layout.minimumHeight: Kirigami.Units.iconSizes.smallMedium

        Layout.preferredWidth:  verticalPanel   ? -1 : longAxisPx
        Layout.preferredHeight: horizontalPanel ? -1 : longAxisPx

        Layout.maximumWidth:  horizontalPanel ? longAxisPx : Number.POSITIVE_INFINITY
        Layout.maximumHeight: verticalPanel   ? longAxisPx : Number.POSITIVE_INFINITY

        Layout.fillHeight: horizontalPanel
        Layout.fillWidth:  verticalPanel

        // Internal-large-size architecture. Cross-validated via playwright:
        // uPlot refuses to lay out a chart at viewports under ~200×150
        // (.u-over.height = 0). Render at 1200×300 internally so Grafana
        // produces a proper chart, then crop the painted axis margins via
        // canvas inline transform (cropAxes) and downscale to the slot via
        // QML Scale.
        readonly property real slotAspect:    width / Math.max(1, height)
        readonly property int  internalHeight: Math.max(300, height * 3)
        readonly property int  internalWidth:  Math.max(300, Math.round(internalHeight * slotAspect))
        readonly property real renderScale:    height / internalHeight

        clip: true

        // --- Live preview ---------------------------------------------------
        // Gate the WebEngineView behind a Loader so we don't pay Chromium
        // init cost (subprocess, GPU context, profile attach) when the user
        // has disabled the live preview or has no tabs configured.  The
        // fallback icon (below) takes over when `previewLive === false`.
        Loader {
            id: miniLoader
            width:  compact.internalWidth
            height: compact.internalHeight
            anchors.top:  parent.top
            anchors.left: parent.left
            z: 0   // below the hover-shield MouseArea so hover doesn't reach Chromium
            active:  compact.previewLive
            visible: compact.previewLive
            sourceComponent: miniViewComp
        }

        Component {
            id: miniViewComp

            WebEngineView {
                id: miniView
                anchors.fill: parent
                profile: sharedProfile
                url: compact.previewTab ? root.resolveThumbUrl(compact.previewTab) : "about:blank"

                settings.javascriptEnabled: true
            settings.showScrollBars: false
            settings.localStorageEnabled: true
            backgroundColor: "transparent"
            zoomFactor: 1.0
            enabled: false   // pass clicks through to the MouseArea above
            smooth: true

            transform: Scale {
                origin.x: 0; origin.y: 0
                xScale: compact.renderScale
                yScale: compact.renderScale
            }

            onLoadingChanged: function(info) {
                console.info("iframe-plasma[mini] loadingChanged status=" + info.status
                    + " url=" + info.url + " thumbSelector=" + JSON.stringify(compact.thumbSelector));
                if (info.status === WebEngineView.LoadSucceededStatus
                    && compact.thumbSelector.length > 0)
                {
                    applyThumbCrop(compact.thumbSelector);
                }
            }

            // Forward console.info / console.warn from in-page JS (our shim's
            // observer callback, apply() returns, etc.) to QML console so it
            // shows up in journalctl. Filter to only [ifp-thumb] tagged lines.
            onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID) {
                if (message && message.indexOf('[ifp-thumb]') !== -1) {
                    console.info("iframe-plasma" + message);
                }
            }

            // Inject CSS that hides everything except the path to `selector`,
            // and sizes the matched element to fill the slot. After applying
            // we fire window.resize so uPlot / ResizeObserver-aware libraries
            // tear down their stale canvas pixel buffers and re-render at the
            // new viewport — without this, Grafana's chart canvas keeps its
            // original hi-DPI (e.g. 1548×1628) buffer and the browser
            // stretches it into our small CSS box, producing severe aliasing.
            //
            // Also re-fires resize a few times because uPlot's reflow can race
            // with Grafana's React tree updates. Three dispatches at 0/100/500
            // ms cover the typical reflow window without busy-looping.
            //
            // Polls every 100ms for up to 30s until the selector matches,
            // since Grafana renders panels progressively after the load event.
            //
            // The IIFE body is selector-agnostic, so it's built once at
            // component init; only the trailing `("<sel>")` call-args string
            // is appended per invocation.
            readonly property string _applyThumbCropJsBody:
                  "(function(sel){"
                // OVERLAY-ONLY ARCHITECTURE
                //
                // Don't touch the source canvas's CSS at all. Don't mark
                // ancestors. Don't position:fixed anything except the display
                // canvas. uPlot keeps its natural rendering size so
                // canvas.getBoundingClientRect() reflects the same CSS box
                // uPlot used for its pxRatio computation — meaning
                // bufW/cr.width = bufH/cr.height = devicePixelRatio uniformly,
                // and our drawImage math is correct.
                //
                // Just two things needed:
                //   1. Inject CSS to hide title bar + "Powered by Grafana"
                //      badge (so they don't paint behind the display canvas
                //      when our overlay is semi-transparent or has gaps).
                //   2. Create a fresh display canvas at the top of body,
                //      position:fixed:inset:0:z-index=max, and copy the
                //      chart-area pixels from the source via drawImage.
                + "  function ensureStyle() {"
                + "    if (document.getElementById('ifp-thumb-style')) return;"
                + "    const s = document.createElement('style');"
                + "    s.id = 'ifp-thumb-style';"
                + "    s.textContent = ["
                + "      'html[data-ifp-thumb=\"1\"],html[data-ifp-thumb=\"1\"] body{margin:0!important;padding:0!important;overflow:hidden!important;background:#181b1f!important;}',"
                + "      'html[data-ifp-thumb=\"1\"] [data-testid=\"data-testid header-container\"]{display:none!important;}',"
                + "      'html[data-ifp-thumb=\"1\"] img[alt=\"Grafana\"],html[data-ifp-thumb=\"1\"] div:has(>img[alt=\"Grafana\"]),html[data-ifp-thumb=\"1\"] div:has(>span+img[alt=\"Grafana\"]),html[data-ifp-thumb=\"1\"] div[class*=\"logoContainer\"]{display:none!important;}',"
                + "      '#ifp-thumb-display{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;z-index:2147483647!important;background:#181b1f!important;display:block!important;margin:0!important;padding:0!important;border:none!important;transform:none!important;}'"
                + "    ].join('');"
                + "    (document.head||document.documentElement).appendChild(s);"
                + "  }"
                + "  function nudgeReflow(target) {"
                // uPlot only re-rasterizes its canvas pixel buffer when its
                // wrapper's ResizeObserver fires — `window.resize` alone just
                // invalidates pointer math, so the canvas keeps its original
                // hi-DPI buffer and the browser stretches it (the aliasing
                // noise we hit before). Force a real box-size mutation: +1 px,
                // next frame, back to 100%. That round-trip is what Grafana's
                // own panel-resize handler relies on.
                + "    const wrap = (target && target.querySelector) ? (target.querySelector('.u-wrap') || target) : target;"
                + "    if (!wrap) { window.dispatchEvent(new Event('resize')); return; }"
                + "    const w0 = wrap.style.width;"
                + "    const h0 = wrap.style.height;"
                + "    wrap.style.width  = (wrap.clientWidth  + 1) + 'px';"
                + "    wrap.style.height = (wrap.clientHeight + 1) + 'px';"
                + "    requestAnimationFrame(function(){"
                + "      wrap.style.width  = w0 || '100%';"
                + "      wrap.style.height = h0 || '100%';"
                // Belt-and-braces: window.resize for non-uPlot panels (Stat, Gauge).
                + "      window.dispatchEvent(new Event('resize'));"
                + "    });"
                + "  }"
                // Crop the painted axis margins off a uPlot canvas target.
                // uPlot paints axis tick labels and tick lines onto the
                // canvas pixel buffer itself (NOT separate DOM elements), so
                // `display:none` rules can't remove them. The chart-data area
                // is, however, exactly bounded by uPlot's `.u-over` div
                // (sibling of canvas, transparent, positioned at the chart-
                // area rect within `.u-wrap`). Read that rect, then shift +
                // scale the canvas via inline transform so the chart area
                // fills the viewport and the axis margins slide off-screen.
                // Skipped if `.u-over` doesn't exist (non-uPlot panel) or has
                // zero dimensions (not yet rendered).
                // Crop the painted axis margins by COPYING just the chart-
                // area pixels into a fresh canvas (display canvas) overlaid
                // on top. No CSS transform on the original canvas — QtWebEngine
                // 6.9's compositor seems to mis-render position:fixed + scale
                // transforms at extreme aspect ratios (works perfectly in
                // headless Chromium at the same viewport, fails in our
                // WebEngineView at 1200x300 with sy=1.41, OK at 600x750 with
                // sy=1.13). drawImage()'s pixel-level copy bypasses the
                // compositor problem entirely.
                //
                // The display canvas:
                //   - position:fixed; inset:0; width:100vw; height:100vh
                //   - internal pixel buffer = chart_area in device pixels
                //   - drawImage(src, sL,sT,sW,sH, 0,0,dW,dH) blits source's
                //     chart-area region to the entire display canvas
                //   - browser then stretches display canvas (pixel buffer
                //     → CSS box 100vw x 100vh) — uniform scale, no transform
                + "  function cropAxes(srcCanvas) {"
                + "    if (!srcCanvas || srcCanvas.tagName !== 'CANVAS') return;"
                + "    const wrap = srcCanvas.parentElement;"
                + "    const over = wrap && wrap.querySelector(':scope > .u-over');"
                + "    if (!wrap || !over) return;"
                // Source canvas is left at its NATURAL position/size by the
                // overlay-only architecture, so getBoundingClientRect()
                // returns the actual uPlot-computed CSS box (e.g. 1182×242
                // not viewport-forced 1200×300). bufW/cr.width == dpr
                // uniformly = correct math.
                + "    const cr = srcCanvas.getBoundingClientRect();"
                + "    if (cr.width === 0 || cr.height === 0) return;"
                + "    const orct = over.getBoundingClientRect();"
                + "    let cssL, cssT, cssW, cssH;"
                + "    if (orct.width > 0 && orct.height > 0) {"
                + "      cssL = orct.left - cr.left;"
                + "      cssT = orct.top  - cr.top;"
                + "      cssW = orct.width;"
                + "      cssH = orct.height;"
                + "    } else {"
                + "      const oL = parseFloat(over.style.left)   || 0;"
                + "      const oT = parseFloat(over.style.top)    || 0;"
                + "      const oW = parseFloat(over.style.width)  || 0;"
                + "      const oH = parseFloat(over.style.height) || 0;"
                + "      if (oW === 0 || oH === 0) return;"
                + "      const wr = wrap.getBoundingClientRect();"
                + "      cssL = oL - (cr.left - wr.left); cssT = oT - (cr.top - wr.top);"
                + "      cssW = oW; cssH = oH;"
                + "    }"
                + "    const bufW = srcCanvas.width;"
                + "    const bufH = srcCanvas.height;"
                + "    if (bufW === 0 || bufH === 0) return;"
                + "    const scaleX = bufW / cr.width;"
                + "    const scaleY = bufH / cr.height;"
                + "    const sL = cssL * scaleX, sT = cssT * scaleY;"
                + "    const sW = cssW * scaleX, sH = cssH * scaleY;"
                // Create / reuse display canvas
                + "    let disp = document.getElementById('ifp-thumb-display');"
                + "    if (!disp) {"
                + "      disp = document.createElement('canvas');"
                + "      disp.id = 'ifp-thumb-display';"
                + "      document.body.appendChild(disp);"
                + "    }"
                + "    const dpr = window.devicePixelRatio || 1;"
                + "    const dispCssW = window.innerWidth;"
                + "    const dispCssH = window.innerHeight;"
                + "    disp.width  = Math.max(1, Math.round(dispCssW * dpr));"
                + "    disp.height = Math.max(1, Math.round(dispCssH * dpr));"
                + "    const ctx = disp.getContext('2d');"
                + "    try { ctx.drawImage(srcCanvas, sL, sT, sW, sH, 0, 0, disp.width, disp.height); } catch (e) { console.warn('[ifp-thumb] drawImage failed:', e.message); return; }"
                + "    console.info('[ifp-thumb] CROP canvas-css=' + cr.width.toFixed(0) + 'x' + cr.height.toFixed(0) + ' src=' + bufW + 'x' + bufH + ' scale=' + scaleX.toFixed(3) + ',' + scaleY.toFixed(3) + ' srcRect=' + sL.toFixed(0) + ',' + sT.toFixed(0) + ',' + sW.toFixed(0) + ',' + sH.toFixed(0) + ' disp=' + disp.width + 'x' + disp.height);"
                + "  }"
                + "  function apply() {"
                + "    let el; try { el = document.querySelector(sel); } catch(e) { console.warn('[ifp-thumb] invalid selector \"'+sel+'\": '+e.message); return 'invalid'; }"
                + "    if (!el) return 'wait';"
                + "    ensureStyle();"
                + "    document.documentElement.setAttribute('data-ifp-thumb','1');"
                + "    cropAxes(el);"
                + "    return 'matched';"
                + "  }"
                + "  const first = apply();"
                + "  if (first === 'invalid') return first;"
                // Robust observer architecture (per edge-case research):
                //   - rAF-coalesced re-application: handles burst mutations
                //     and uPlot's async ResizeObserver callbacks naturally.
                //   - MutationObserver on document.body{childList,subtree}:
                //     catches deep canvas insertion AND class-list changes.
                //   - When a target is matched, also observe its parent
                //     `.u-wrap` for `attributes:{style,width,height}` so
                //     Y-axis-width drift between Grafana refreshes (which
                //     shifts `.u-over` inline style by a few px) triggers
                //     a transform recompute.
                //   - ResizeObserver on `.u-wrap` for viewport changes
                //     (panel-thickness drag).
                //   - NO timeout disconnect: same-size refreshes don't
                //     touch DOM (proven via 25s probe), so the observer
                //     idles cheaply when nothing changes.
                + "  if (window.__ifpThumbObserver) window.__ifpThumbObserver.disconnect();"
                + "  if (window.__ifpThumbWrapObserver) window.__ifpThumbWrapObserver.disconnect();"
                + "  if (window.__ifpThumbResize) { try{window.__ifpThumbResize.disconnect();}catch(e){} }"
                + "  let rafId = 0;"
                + "  let lastEl = null;"
                + "  function schedule() {"
                + "    if (rafId) return;"
                + "    rafId = requestAnimationFrame(function(){"
                + "      rafId = 0;"
                + "      const r = apply();"
                + "      const el = document.querySelector(sel);"
                + "      if (r === 'matched' && el && el !== lastEl) {"
                + "        lastEl = el;"
                // Add fine-grained observers on the chart's wrap and uplot ancestors.
                + "        const wrap = el.parentElement;"
                + "        if (wrap && window.__ifpThumbWrapObserver) window.__ifpThumbWrapObserver.disconnect();"
                + "        if (wrap) {"
                + "          const wo = new MutationObserver(schedule);"
                + "          wo.observe(wrap, { childList: true, subtree: true, attributes: true, attributeFilter: ['style','width','height'] });"
                + "          window.__ifpThumbWrapObserver = wo;"
                + "          try { const ro = new ResizeObserver(schedule); ro.observe(wrap); window.__ifpThumbResize = ro; } catch(e) {}"
                + "        }"
                + "        console.info('[ifp-thumb] MATCHED tag=' + el.tagName + (el.className ? '.' + el.className.split(' ').slice(0,2).join('.') : ''));"
                + "      }"
                + "    });"
                + "  }"
                + "  const obs = new MutationObserver(schedule);"
                + "  obs.observe(document.body, { childList: true, subtree: true });"
                + "  window.__ifpThumbObserver = obs;"
                // Periodic re-copy: Grafana's `refresh=30s` re-renders the
                // canvas pixel buffer via canvas 2D context calls — those do
                // NOT fire any DOM mutation, so neither the MutationObserver
                // nor the ResizeObserver catches new data. Poll every 3s to
                // copy the latest source pixels into the display canvas.
                // Cheap: a single drawImage + getBoundingClientRect call.
                + "  if (window.__ifpThumbInterval) clearInterval(window.__ifpThumbInterval);"
                + "  window.__ifpThumbInterval = setInterval(schedule, 3000);"
                + "  return first === 'matched' ? 'matched-and-observing' : 'observing';"
                + "})"

            function applyThumbCrop(selector) {
                console.info("iframe-plasma[thumb] applyThumbCrop ENTRY selector=" + JSON.stringify(selector)
                    + " loading=" + miniView.loading + " url=" + miniView.url);
                const code = _applyThumbCropJsBody + "(" + JSON.stringify(selector) + ")";
                runJavaScript(code, function(r) {
                    console.info("iframe-plasma[thumb] applyThumbCrop("
                        + JSON.stringify(selector) + ") = " + r);
                });
            }

            // When the slot itself resizes (user dragged panel size, changed
            // Preview-size config), re-fire window.resize so uPlot re-renders
            // at the new viewport. Debounced 200ms so dragging is smooth.
            onWidthChanged:  miniViewReflowTimer.restart()
            onHeightChanged: miniViewReflowTimer.restart()
            Timer {
                id: miniViewReflowTimer
                interval: 200
                onTriggered: {
                    if (compact.thumbSelector.length > 0) {
                        miniView.runJavaScript("window.dispatchEvent(new Event('resize'));");
                    }
                }
            }

            }
        }

        // --- Icon fallback --------------------------------------------------
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) - Kirigami.Units.smallSpacing
            height: width
            visible: !compact.previewLive
            source: Plasmoid.icon || "applications-internet"
            z: 0
        }

        // --- URL label overlay ---------------------------------------------
        // Semi-transparent dark pill in the top-left of the slot showing the
        // tab's label. Width hugs the text (with a small horizontal padding),
        // capped at the parent width so very long labels still fit. Height
        // scales with slot height (30%, floored at 12px) so it stays readable
        // on both thin (50px) and thick (250px) panels.
        //
        // z: 2 → above miniView (z=0) and the hover MouseArea (z=1); the
        // MouseArea still receives clicks on the rest of the slot.
        Rectangle {
            id: thumbLabel
            readonly property int horizontalPadding: 4
            anchors {
                top: parent.top
                left: parent.left
            }
            // Hug the text: implicitWidth of label + padding on both sides,
            // clamped to the parent's width so it never overflows.
            width: Math.min(parent.width,
                            thumbLabelText.implicitWidth + horizontalPadding * 2)
            height: Math.max(12, Math.round(parent.height * 0.30))
            color: Qt.rgba(0, 0, 0, 0.55)
            visible: Plasmoid.configuration.compactPreviewShowLabel
                  && compact.previewTab
                  && compact.previewTab.label
                  && compact.previewTab.label.length > 0
            z: 2

            QQC.Label {
                id: thumbLabelText
                anchors {
                    fill: parent
                    leftMargin: thumbLabel.horizontalPadding
                    rightMargin: thumbLabel.horizontalPadding
                }
                text: (compact.previewTab && compact.previewTab.label) || ""
                color: Theme.fg
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignLeft
                font.pixelSize: Math.max(8, Math.round(thumbLabel.height * 0.75))
                // Match the widget's own header font (Hack) used in the
                // tab bar and toolbar — keeps thumbnail labels consistent
                // with the popup's visual identity.
                font.family: Theme.fontHeader
            }
        }

        // Left-click anywhere on the slot toggles the full popup.
        // Right-click is INTENTIONALLY NOT accepted here so it propagates
        // to the PlasmoidItem and Plasma's containment shows the standard
        // widget context menu (Configure widget, Remove, etc.).
        //
        // Placed ABOVE the WebEngineView (z: 1) with hoverEnabled: true so
        // it consumes pointer enter/move/leave events before they reach
        // Chromium — without this, Grafana would see mouse-position events
        // even though the WebEngineView is `enabled: false`, draw its
        // crosshair/tooltip on every hover, and the chart would flicker.
        MouseArea {
            anchors.fill: parent
            z: 1
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: ColumnLayout {
        // Layout.preferred* only applies on first-ever open; once the user
        // drag-resizes the popup, Plasma persists `popupWidth/popupHeight`
        // in appletsrc and that value wins on subsequent opens.
        Layout.minimumWidth:  Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth:  800
        Layout.preferredHeight: 500
        spacing: 0

        CyberToolbar {
            id: toolbar
            Layout.fillWidth: true
            visible: root.tabs.length > 0
            host:            root.activeTab ? root.activeTab.currentHost           : ""
            tlsOk:           root.activeTab ? root.activeTab.tlsOk                 : false
            httpStatus:      root.activeTab ? root.activeTab.httpStatus            : 0
            latencyMs:       root.activeTab ? root.activeTab.latencyMs             : 0
            loading:         root.activeTab ? root.activeTab.loadStatus === "loading" : false
            timeRange:       root.activeTab ? root.activeTab.currentTimeRange       : ""
            refreshInterval: root.activeTab ? root.activeTab.currentRefreshInterval : ""
            onReloadClicked:        root.activeTab?.reload()
            onHardReloadClicked:    root.activeTab?.hardReload()
            onOpenExternalClicked:  root.activeTab?.openExternal()
            onClearCookiesClicked:  root.clearCacheAndReload()
            onSelectTimeRange:        range    => root.activeTab?.setTimeRange(range)
            onSelectRefreshInterval:  interval => root.activeTab?.setRefreshInterval(interval)
        }

        CyberTabBar {
            id: tabBar
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showTabBar && root.tabs.length > 1
            tabs: root.tabs
            currentIndex: root.currentTabIndex
            statuses: root.tabStatuses
            onTabSelected: idx => root.setCurrentTab(idx)
            onReloadRequested: idx => {
                const view = webStack.itemAt(idx);
                if (view) view.reload();
            }
        }

        StackLayout {
            id: webStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTabIndex

            function itemAt(idx) {
                const item = repeater.itemAt(idx);
                return item ? item.webView : null;
            }
            function reloadAll() {
                for (let i = 0; i < repeater.count; i++) {
                    const w = itemAt(i);
                    if (w) w.reload();
                }
            }

            Component.onCompleted: {
                // Expose the active-tab object (a WebTab instance) to root scope.
                // Qt.binding keeps it reactive to currentTabIndex / repeater.count.
                root.activeTab = Qt.binding(function() {
                    return repeater.count > 0
                        ? repeater.itemAt(Math.max(0, Math.min(root.currentTabIndex, repeater.count - 1)))
                        : null;
                });
            }

            Connections {
                target: root
                function onReloadAllRequested() { webStack.reloadAll() }
            }

            Repeater {
                id: repeater
                model: root.tabs
                delegate: WebTab {
                    required property var modelData
                    required property int index

                    tabConfig: modelData
                    profile: sharedProfile
                    // Authelia host is now per-profile (0.4.0+). Falls back to
                    // the deprecated global setting for unmigrated configs.
                    autheliaHost: {
                        const p = root.profileById(modelData.authProfileId);
                        return (p && p.autheliaHost) || Plasmoid.configuration.autheliaHost || "";
                    }
                    zoomPct: Plasmoid.configuration.zoomFactor
                    url: root.resolveUrl(modelData)
                    debugPort: Plasmoid.configuration.remoteDebuggingPort
                    onBasicAuthRequested: req => root.handleBasicAuth(req, modelData)
                    onAuthRequired: () => root.expanded = true
                    onLoadStatusChanged: root.setTabStatus(index, loadStatus)
                }
            }
        }

        // Empty-state placeholder when no URLs configured yet
        Kirigami.PlaceholderMessage {
            Layout.alignment: Qt.AlignCenter
            Layout.fillWidth: true
            visible: root.tabs.length === 0
            text: i18n("No URLs configured")
            explanation: i18n("Right-click the widget → Configure to add Grafana panels or any other URL.")
            icon.name: "list-add"
        }
    }
}
