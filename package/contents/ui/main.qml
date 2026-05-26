/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtCore
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC
import QtWebEngine
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "./CropEngine.js" as CropEngine

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

    // Parsed tab list, refreshed whenever config changes.
    //
    // CRITICAL: this MUST NOT be a binding on Plasmoid.configuration.urlsJson.
    // A binding re-evaluates whenever urlsJson changes and reassigns root.tabs
    // to a NEW array — that fires Repeater rebuild, destroying every WebTab
    // delegate AND the embedded WebEngineView. If an async runJavaScript
    // callback was in flight at that moment (e.g. from savePickedSelector's
    // applyImmediately), it fires on the destroyed webview and crashes
    // plasmashell with SIGSEGV in QJSEngine::create / didRunJavaScript.
    // The Connections handler below is the ONLY writer of root.tabs and
    // honours the _suppressTabsRebuildOnce guard.
    property var tabs: []
    property int currentTabIndex: Math.max(0, Math.min(Plasmoid.configuration.currentTabIndex, tabs.length - 1))
    // One-shot guard: when savePickedSelector writes urlsJson, set
    // this to true so onUrlsJsonChanged skips the tabs[] reassignment
    // (which would destroy/recreate every WebTab delegate and force a
    // from-scratch WebEngineView reload — the "blank greyish page"
    // the user saw after every picker save). The picker save instead
    // pushes selector updates directly to the live WebTab and the
    // compact thumbnail, keeping the WebEngineView's loaded state
    // intact. The flag self-clears on the first consume so it can't
    // accidentally swallow a later structural change.
    property bool _suppressTabsRebuildOnce: false

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

    // Tab URLs are loaded as the primary navigation in a WebEngineView whose
    // profile is per-authProfileId (auth=None tabs use the ephemeral profile).
    // Restrict to http(s) so a pasted `data:`, `file:`, `javascript:`, `blob:`
    // etc. cannot execute in any profile's cookie/storage origin or read
    // local files.
    function _isSafeTabUrl(s) {
        if (typeof s !== "string") return false;
        return /^https?:\/\//i.test(s);
    }

    function parseTabs(jsonStr) {
        try {
            const arr = JSON.parse(jsonStr || "[]");
            if (Array.isArray(arr)) return arr.filter(t => t && _isSafeTabUrl(t.url));
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

    // Same heuristic as ConfigUrls.qml's isGrafanaEmbed — duplicated
    // here (rather than singleton-extracted) because the regex is two
    // lines and pulling KCM-singleton scope into the popup isn't worth
    // the indirection. Used by the toolbar to gate the Time-range and
    // Refresh-interval chips, which rewrite Grafana-shaped URL params.
    function isGrafanaEmbed(u) {
        if (!u) return false;
        return /\/d(-solo)?\/[A-Za-z0-9_-]+\//.test(String(u));
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
        // Validate `range` before splicing into the query string. The popup
        // path (WebTab.currentTimeRange) regex-validates to /^now-(\d+[smhdwMy])$/
        // before exposing the suffix; thumbTimeRange came from raw config and
        // was concatenated unvalidated, so a typo'd or import-poisoned value
        // like "1h&kiosk=true&authToken=leak" would inject extra params into
        // the configured Grafana URL on every thumbnail load. Refuse anything
        // that doesn't match Grafana's interval shape; fall back to the URL's
        // own from/to (range = "").
        if (range.length > 0 && !/^\d+[smhdwMy]$/.test(range)) {
            console.warn("iframe-plasma[thumb] rejected invalid thumbTimeRange=" + range);
            range = "";
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
            // Skip the tabs[] reassignment (and the cascade of Repeater
            // delegate destroy/recreate that comes with it) when the
            // change came from savePickedSelector — that path pushed
            // the selector updates to live WebTabs directly. Without
            // this guard every picker save would blank the popup.
            if (root._suppressTabsRebuildOnce) {
                root._suppressTabsRebuildOnce = false;
                console.info("iframe-plasma[urls] selector-only update; tabs[] rebuild skipped");
                return;
            }
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
        // userAgentOverride used to live as a binding on WebEngineProfile,
        // but the 6.9 WebEngineProfilePrototype migration moved it off the
        // declarative surface (Prototype doesn't expose httpUserAgent).
        // Propagate the sanitised value to every live profile so a config-
        // dialog change still takes effect without a plasmashell restart.
        function onUserAgentOverrideChanged() {
            const ua = root._sanitisedUserAgent();
            for (const key in root._profiles) {
                root._profiles[key].httpUserAgent = ua;
            }
        }
    }

    Component.onCompleted: {
        // Seed root.tabs from the current urlsJson. The `property var
        // tabs: []` declaration above intentionally has NO binding —
        // see the comment there.
        root.tabs = root.parseTabs(Plasmoid.configuration.urlsJson);

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

    // Per-auth-profile WebEngineProfile — each named authProfileId gets its
    // own profile (its own cookies/cache/storage), so a tab with auth=None
    // never inherits another tab's session cookie or Authorization header.
    // Tabs sharing the same authProfileId share one profile (preserves SSO).
    // Tabs with authProfileId="" use the in-memory ephemeral profile.
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

    // --- Observability ------------------------------------------------------
    // Recurring work (web views, the auto-cycle, the thumbnail poll) must be
    // gated on whether it is actually being seen — and there are two separate
    // questions, not one:
    //   fullRepVisible    — is the popup being looked at?
    //   compactObservable — is the panel slot itself on screen?
    // Gating on the wrong one is a bug: pausing the thumbnail on !expanded
    // would freeze the rotating preview exactly when it should run. See
    // WebViewLifecycle.qml for how these drive each WebEngineView.
    readonly property bool screenLocked: root.authSupport
                                         && root.authSupport.screenLocked === true
    readonly property bool fullRepVisible: !root.inPanel || root.expanded
    // Set by the compact representation from its panel window's visibility;
    // defaults true so an absent window never wrongly pauses the thumbnail.
    property bool compactWindowVisible: true
    readonly property bool compactObservable: !root.screenLocked
                                              && root.compactWindowVisible

    readonly property string profileStorageRoot: {
        // StandardPaths.writableLocation returns a QUrl ("file:///…") — strip the
        // scheme so QtWebEngine gets a real filesystem path, not a literal "file:" dir.
        const base = String(StandardPaths.writableLocation(StandardPaths.AppDataLocation))
                        .replace(/^file:\/\//, "");
        return base + "/iframe-plasma/" + (Plasmoid.id || 0);
    }

    // authProfileId -> WebEngineProfile (cached, lifetime = root).
    // Key "" is the ephemeral off-the-record profile used by all auth=None tabs.
    property var _profiles: ({})
    // authProfileId -> BasicAuthInterceptor (per-profile m_headers so the
    // Authorization header registered for profile "admin" never injects on
    // requests routed through profile "viewer" or the ephemeral profile).
    // Ephemeral profile gets no interceptor at all.
    property var _interceptors: ({})

    // Component template — Qt 6.9+ deprecated direct `WebEngineProfile`
    // instantiation from QML; the replacement is `WebEngineProfilePrototype`,
    // a configurator that exposes only the write-once construction fields
    // (storageName / persistent storage / cookies / cache).  Runtime fields
    // (offTheRecord / spellCheck / UA / downloadRequested) are NOT on the
    // Prototype — they're applied to `prototype.instance()` in the factory
    // below.
    //
    // The write-once fields are populated via createObject() options (not
    // via declarative bindings), because a binding that depends on
    // `profileAuthId` re-evaluates once when its initial default is applied
    // and once when createObject's options set the real id — that second
    // write trips the Prototype's "should not be set again" warning even
    // though both writes happen before componentComplete.
    Component {
        id: profileComponent
        WebEngineProfilePrototype {
            property string profileAuthId: ""
        }
    }

    // Lazy factory.  Creates a `WebEngineProfilePrototype`, materialises its
    // underlying `QQuickWebEngineProfile` via `.instance()`, applies the
    // post-construction settings, optionally attaches a per-profile
    // interceptor, and returns the profile (NOT the prototype — that stays
    // parented to root for lifetime management).  Cached by authProfileId so
    // tabs sharing the same id share one profile.
    function profileForAuthId(authProfileId) {
        const key = authProfileId || "";
        if (root._profiles[key]) return root._profiles[key];
        const isEphemeral = (key.length === 0);
        // Empty storageName + empty persistentStoragePath drives the
        // underlying QQuickWebEngineProfile into off-the-record mode for the
        // ephemeral path (no cookies/cache touch disk).  offTheRecord = true
        // is also pinned on instance() below as defense-in-depth.
        const prototype = profileComponent.createObject(root, {
            profileAuthId: key,
            storageName: isEphemeral
                ? ""
                : Plasmoid.metaData.pluginId + "-" + (Plasmoid.id || 0) + "-" + key,
            persistentCookiesPolicy: isEphemeral
                ? WebEngineProfile.NoPersistentCookies
                : WebEngineProfile.ForcePersistentCookies,
            persistentStoragePath: isEphemeral
                ? ""
                : root.profileStorageRoot + "/" + key
        });
        if (!prototype) {
            console.warn("iframe-plasma[profile] prototype createObject failed for id=" + key);
            return null;
        }
        const profile = prototype.instance();
        if (!profile) {
            // Per Qt docs, instance() returns null on persistentStoragePath
            // collision — should never happen with our per-authProfileId
            // path layout but log defensively.
            console.warn("iframe-plasma[profile] prototype.instance() returned null for id=" + key);
            prototype.destroy();
            return null;
        }
        // Runtime fields, applied post-construction.  offTheRecord on the
        // ephemeral profile is belt-and-braces: storageName/path are already
        // empty so the underlying profile is in-memory anyway.
        if (isEphemeral) profile.offTheRecord = true;
        // Defense-in-depth: pin spellCheck so a future Qt default-flip can't
        // start posting Grafana template-variable typings to the platform
        // dictionary service.
        profile.spellCheckEnabled = false;
        profile.httpUserAgent = root._sanitisedUserAgent();
        // Bound the HTTP cache so a widget left running for days can't let it
        // grow without limit (0 = Qt-auto-managed). 50 MB is ample for the
        // JS/CSS/font assets a handful of Grafana dashboards reuse.
        profile.httpCacheMaximumSize = 50 * 1024 * 1024;
        // Refuse downloads outright: the widget is a passive dashboard viewer.
        profile.downloadRequested.connect(root._blockDownload);
        root._profiles[key] = profile;
        if (isEphemeral) {
            console.info("iframe-plasma[profile] created ephemeral profile");
            return profile;
        }
        if (root.authSupport && Plasmoid.configuration.useBasicAuthInjection) {
            const interceptor = root.authSupport.createInterceptor();
            if (interceptor && interceptor.attachTo(profile)) {
                root._interceptors[key] = interceptor;
                console.info("iframe-plasma[profile] created+attached interceptor for id=" + key);
            } else {
                console.warn("iframe-plasma[profile] failed to create/attach interceptor for id=" + key);
            }
        } else {
            console.info("iframe-plasma[profile] created named profile id=" + key + " (injection disabled, no interceptor)");
        }
        return profile;
    }

    // Shared download blocker — same callback identity per profile so a
    // future disconnect() can match (signal.disconnect() needs the same
    // function reference, not just one with the same body).
    function _blockDownload(item) {
        console.warn("iframe-plasma[dl] blocked download url=" + item.url
            + " mime=" + item.mimeType);
        item.cancel();
    }

    // Strip CR/LF/NUL — parity with the auth-interceptor header guard
    // (3cedd16).  Centralised so the createObject + UA-config-changed paths
    // both sanitise identically.
    function _sanitisedUserAgent() {
        const ua = Plasmoid.configuration.userAgentOverride;
        return ua.length > 0 ? ua.replace(/[\r\n\0]/g, "") : "";
    }

    // Attach/detach the interceptor whenever the toggle or plugin availability changes.
    // Signal fired from root-level events; WebTab listens and reloads its view.
    // Cleaner than reaching into fullRepresentation's StackLayout from outside.
    signal reloadAllRequested()
    function reloadAll() { reloadAllRequested() }

    // Fired by savePickedSelector when a thumb-scope save happened —
    // the compact rep listens and applies the new selector to its
    // mini-view if the saved tab is the currently-previewed one. We
    // pass the new selector through the signal because the compact's
    // declarative `thumbSelector` binding can't see a JS-object
    // property mutation on root.tabs[i], so the previous "fire a
    // reload and let onLoadingChanged re-apply" pattern would have
    // re-applied the OLD cached binding value.
    signal _thumbSelectorSaved(int tabIdx, string newSelector)

    function syncInterceptor() {
        const enabled = Plasmoid.configuration.useBasicAuthInjection;
        console.info("iframe-plasma[sync] authSupport=" + (root.authSupport ? "available" : "null")
            + " useBasicAuthInjection=" + enabled);
        if (!root.authSupport) return;
        // Walk every named profile (the ephemeral profile is intentionally
        // skipped — auth=None tabs never get an Authorization header).
        for (const key in root._profiles) {
            if (key.length === 0) continue;
            const profile = root._profiles[key];
            let interceptor = root._interceptors[key];
            if (enabled) {
                if (!interceptor) {
                    interceptor = root.authSupport.createInterceptor();
                    if (!interceptor) continue;
                    root._interceptors[key] = interceptor;
                }
                const ok = interceptor.attachTo(profile);
                console.info("iframe-plasma[sync] attachTo id=" + key + " -> " + ok);
            } else if (interceptor) {
                const ok = interceptor.detachFrom(profile);
                console.info("iframe-plasma[sync] detachFrom id=" + key + " -> " + ok);
            }
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
        // Reset every per-profile interceptor (covers profiles whose URLs got
        // reassigned away — old host→header entries shouldn't outlive the
        // reassignment).
        for (const key in root._interceptors) {
            root._interceptors[key].clearAll();
        }
        // Re-apply each in-use profile via its own interceptor.  Ensures the
        // profile (and its interceptor) exist even if no WebTab has bound to
        // it yet — primeAuthProfiles can fire before fullRepresentation has
        // constructed its Repeater.
        for (const id in profilesInUse) {
            const { profile, hosts } = profilesInUse[id];
            const secrets = root.authSupport.getMap(root.authSupport.profileKey(id)) || {};
            const secret = secrets.password || secrets.bearerToken || secrets.rawHeader || "";
            if (secret.length === 0) {
                console.info("iframe-plasma[auth] profile " + id + " has no stored secret — skipping");
                continue;
            }
            root.profileForAuthId(id);   // ensure profile + interceptor exist
            const interceptor = root._interceptors[id];
            if (!interceptor) {
                console.info("iframe-plasma[auth] no interceptor for profile id=" + id + " (injection disabled?)");
                continue;
            }
            interceptor.applyProfile(id, profile.authType || "basic",
                profile.username || "", secret, hosts);
        }
    }

    // Receives the result of WebTab.startPicker(). `sel == ""` means the
    // user pressed Esc / cancelled — no-op. Otherwise hands off to the
    // save dialog which lets the user choose whether to apply the selector
    // to the panel-slot thumbnail or the popup widget.
    function handlePickedSelector(tabIdx, sel) {
        console.info("iframe-plasma[picker] handlePickedSelector idx=" + tabIdx
            + " sel=" + JSON.stringify(sel));
        if (!sel || sel.length === 0) return;
        // The dialog lives inside fullRepresentation (it has to be parented
        // to a real Item that's part of the popup window so Kirigami's
        // Dialog overlay machinery has something to anchor to). Walk via
        // the popup item reference; bail quietly if the popup hasn't been
        // realised yet (shouldn't happen — picker runs from inside it).
        const popup = root.fullRepresentationItem;
        if (popup && typeof popup.showSavePickedDialog === "function") {
            popup.showSavePickedDialog(tabIdx, sel);
        } else {
            console.warn("iframe-plasma[picker] no fullRepresentationItem; selector dropped");
        }
    }

    // Persist a picked selector into urlsJson at `tabIdx`. `scope` is
    // "thumb" | "popup" | "both". Flips the corresponding *Mode(s) to
    // "custom" so the selector field actually engages. "both" writes
    // both fields in a single parse/stringify cycle.
    //
    // CRITICAL: the prior implementation just wrote urlsJson and let
    // the Connections.onUrlsJsonChanged cascade reassign root.tabs,
    // which destroyed the Repeater delegates and forced every
    // WebEngineView to reload from scratch (the "blank greyish page"
    // bug). This version mutates the live tabs[] entry in place,
    // pushes selector updates directly to the live WebTab + compact
    // thumbnail, and sets the _suppressTabsRebuildOnce guard so the
    // urlsJson write triggers persistence WITHOUT a rebuild.
    function savePickedSelector(tabIdx, scope, sel) {
        try {
            const arr = JSON.parse(Plasmoid.configuration.urlsJson || "[]");
            if (!Array.isArray(arr) || tabIdx < 0 || tabIdx >= arr.length) return;
            const entry = arr[tabIdx] || {};
            if (scope === "thumb" || scope === "both") {
                entry.thumbMode = "custom";
                entry.thumbSelector = sel;
            }
            if (scope === "popup" || scope === "both") {
                entry.popupMode = "custom";
                entry.popupSelector = sel;
            }
            arr[tabIdx] = entry;

            // Mutate the live tabs[] entry in place so any binding
            // that re-reads modelData fields sees the new values
            // without the Repeater being rebuilt.
            if (root.tabs[tabIdx]) {
                root.tabs[tabIdx].thumbMode    = entry.thumbMode;
                root.tabs[tabIdx].thumbSelector = entry.thumbSelector;
                root.tabs[tabIdx].popupMode    = entry.popupMode;
                root.tabs[tabIdx].popupSelector = entry.popupSelector;
            }

            // Apply the new popup selector DIRECTLY via WebTab's
            // applyImmediately(). The lookup of the live WebTab MUST
            // go through fullRoot.applyPopupSelectorAt — the
            // Repeater's `id: repeater` lives inside the
            // fullRepresentation Component's ID scope, which root
            // can't see. A direct `repeater.itemAt(tabIdx)` here
            // threw `ReferenceError: repeater is not defined` and
            // the try/catch silently swallowed it, leaving every
            // picker save a no-op (the urlsJson write below never
            // even ran). Confirmed in journal as `save error:
            // repeater is not defined`.
            if (scope === "popup" || scope === "both") {
                const newPopupSel = (entry.popupMode === "custom")
                                  ? (entry.popupSelector || "") : "";
                const fr = root.fullRepresentationItem;
                if (fr && typeof fr.applyPopupSelectorAt === "function") {
                    const ok = fr.applyPopupSelectorAt(tabIdx, newPopupSel);
                    if (!ok) console.warn("iframe-plasma[picker] no live WebTab at idx=" + tabIdx);
                } else {
                    console.warn("iframe-plasma[picker] fullRepresentationItem unavailable");
                }
            }

            // Notify the thumbnail (if currently showing this tab)
            // with the NEW selector — compact's binding-based
            // thumbSelector can't see the modelData mutation, so we
            // pass the resolved selector explicitly. Mirror the same
            // preset→selector mapping the compact's `thumbSelector`
            // binding uses (chartOnly→.u-wrap>canvas etc.).
            if (scope === "thumb" || scope === "both") {
                const newThumbSel =
                      entry.thumbMode === "chartOnly"     ? ".u-wrap > canvas"
                    : entry.thumbMode === "chartWithAxes" ? ".u-wrap"
                    : entry.thumbMode === "custom"        ? (entry.thumbSelector || "")
                    : "";   // fullPanel / unknown
                root._thumbSelectorSaved(tabIdx, newThumbSel);
            }

            // Persist to urlsJson — guarded so onUrlsJsonChanged
            // skips the tabs[] reassignment that would have rebuilt
            // the Repeater (blanking every WebEngineView).
            root._suppressTabsRebuildOnce = true;
            Plasmoid.configuration.urlsJson = JSON.stringify(arr);
            console.info("iframe-plasma[picker] saved scope=" + scope
                + " sel=" + JSON.stringify(sel) + " idx=" + tabIdx);
        } catch (e) {
            console.warn("iframe-plasma[picker] save error:", e.message);
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
                 && root.compactObservable
        repeat: true
        onTriggered: root.advanceCycleTab((root.currentTabIndex + 1) % root.tabs.length)
    }

    // Cookie clearing per-host needs `profile.cookieStore` which QML doesn't
    // expose for QQuickWebEngineProfile. Phase 4 adds a small C++ helper on the
    // shared plugin to do this properly. For now the toolbar action falls back
    // to clearing the HTTP cache (which alone does not invalidate the Authelia
    // session cookie — by design, so a refresh after auth changes still works).
    //
    // clearHttpCache() is async — it schedules a wipe on Chromium's IO thread
    // and returns immediately.  Firing reload() on the next line races the
    // wipe: the new fetch's in-flight requests can collide with the cache
    // teardown and die mid-handshake ("Failed to fetch" toasts + endless
    // spinner inside the dashboard JS).  Wait for clearHttpCacheCompleted
    // (Qt 6.7+) before reloading so the cache state is settled when the
    // new requests go out.
    function clearCacheAndReload() {
        const tab = root.activeTab;
        if (!tab) return;
        const profile = tab.profile;
        if (!profile) { tab.reload(); return; }
        let fired = false;
        function onCompleted() {
            if (fired) return;
            fired = true;
            try { profile.clearHttpCacheCompleted.disconnect(onCompleted); } catch (e) { /* profile gone */ }
            console.info("iframe-plasma: HTTP cache cleared, reloading");
            try { tab.reload(); } catch (e) {
                console.warn("iframe-plasma: reload after cache-clear failed:", e.message);
            }
        }
        profile.clearHttpCacheCompleted.connect(onCompleted);
        profile.clearHttpCache();
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

    // Auto-cycle advances the runtime index only — it must NOT persist.
    // Routing the cycle through setCurrentTab would rewrite the on-disk
    // appletsrc every autoCycleIntervalSec for the whole session (a disk
    // write every 5–30 s, forever). The next *user* tab switch still
    // persists via setCurrentTab, so session restore keeps working.
    function advanceCycleTab(idx) {
        root.currentTabIndex = idx;
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
    // Uses the same per-authProfileId profile as the full WebTab, so cookies
    // and auth are reused for the active/preview tab and Authed dashboards
    // render correctly in the thumbnail.
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

        // The thumbnail is "active" — live, rendering, polling — when the
        // panel slot is observable (not screen-locked, panel on screen). It
        // stays live while the popup is open. When false the miniView is
        // hidden (so QtWebEngine permits a non-Active lifecycleState) and
        // frozen, and the icon fallback takes the slot.
        readonly property bool miniActive: previewLive
                                           && root.compactObservable

        // The panel window's own visibility — false when the panel's Activity
        // is not the current one. `Window.window` is null before the slot is
        // shown; treat that as visible so the thumbnail is never wrongly paused.
        readonly property bool panelWindowVisible:
            Window.window ? Window.window.visible : true

        // Feed panel-window visibility up to root.compactObservable.
        Binding {
            target: root
            property: "compactWindowVisible"
            value: compact.panelWindowVisible
        }

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

        // Direct trigger from savePickedSelector when the picker save
        // touched a thumb-scope selector. The compact's thumbSelector
        // binding can't see a JS-object property mutation on
        // root.tabs[i], so the onThumbSelectorChanged handler above
        // won't fire automatically — this signal route forces the
        // apply with the EXPLICIT new selector (passed through the
        // signal payload). A full reload would re-fetch the URL
        // unnecessarily AND re-apply via the still-cached binding
        // value, so we call applyThumbCrop directly.
        Connections {
            target: root
            function on_ThumbSelectorSaved(tabIdx, newSelector) {
                if (tabIdx !== compact.previewTabIdx) return;
                if (!miniLoader.item) return;
                if (newSelector && newSelector.length > 0
                    && typeof miniLoader.item.applyThumbCrop === "function") {
                    console.info("iframe-plasma[compact] thumb-save apply idx=" + tabIdx
                        + " sel=" + JSON.stringify(newSelector));
                    miniLoader.item.applyThumbCrop(newSelector);
                } else {
                    // fullPanel / empty selector — fall back to a
                    // reload (no clear-attribute path on the mini
                    // view today; reload returns the page to its
                    // natural un-cropped state).
                    console.info("iframe-plasma[compact] thumb-save reload idx=" + tabIdx);
                    miniLoader.item.reload();
                }
            }
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
            // `active` keeps the WebEngineView instantiated whenever the
            // preview feature is on, so freeze/thaw is instant; `visible`
            // narrows to miniActive so the view goes invisible (freezable)
            // when the slot isn't observed.
            active:  compact.previewLive
            visible: compact.miniActive
            sourceComponent: miniViewComp
        }

        Component {
            id: miniViewComp

            WebEngineView {
                id: miniView
                anchors.fill: parent
                profile: root.profileForAuthId(compact.previewTab ? compact.previewTab.authProfileId : "")
                url: compact.previewTab ? root.resolveThumbUrl(compact.previewTab) : "about:blank"

                settings.javascriptEnabled: true
            settings.showScrollBars: false
            settings.localStorageEnabled: true
            settings.pluginsEnabled: false
            settings.javascriptCanPaste: false
            // Defense-in-depth: thumbnail is passive (enabled:false) — no
            // interaction needed, so clamp every capability that could be
            // abused by a hostile page sneaking through a configured URL.
            settings.localContentCanAccessFileUrls: false
            settings.localContentCanAccessRemoteUrls: false
            settings.javascriptCanOpenWindows: false
            settings.javascriptCanAccessClipboard: false
            settings.allowRunningInsecureContent: false
            settings.pdfViewerEnabled: false
            settings.webRTCPublicInterfacesOnly: true
            backgroundColor: "transparent"
            zoomFactor: 1.0
            enabled: false   // pass clicks through to the MouseArea above
            smooth: true

            // Mirror WebTab.qml policy pins on the thumbnail; `enabled:false`
            // only suppresses input, not Chromium-side capability defaults, so
            // the miniView still needs explicit denies in case a configured
            // URL or downstream redirect triggers any of these requests during
            // the thumb's render window.
            onFeaturePermissionRequested: function(securityOrigin, feature) {
                console.warn("iframe-plasma[mini-perm] denied feature=" + feature
                    + " origin=" + securityOrigin);
                miniView.grantFeaturePermission(securityOrigin, feature, false);
            }
            onPermissionRequested: function(perm) {
                console.warn("iframe-plasma[mini-perm] denied permission=" + perm.permissionType
                    + " origin=" + perm.origin);
                perm.deny();
            }
            onFullScreenRequested: function(request) {
                console.warn("iframe-plasma[mini-fs] rejected fullScreen request");
                request.reject();
            }
            onRegisterProtocolHandlerRequested: function(request) {
                console.warn("iframe-plasma[mini-proto] rejected scheme=" + request.scheme);
                request.reject();
            }
            onFileDialogRequested: function(request) {
                console.warn("iframe-plasma[mini-file] rejected dialog mode=" + request.mode);
                request.dialogReject();
            }
            // Mirror WebTab pins: suppress default context menu, reject
            // client-cert auto-select, cancel WebAuthn ceremonies. `enabled:false`
            // suppresses input but not Chromium-side capability defaults, so
            // a configured URL hitting any of these during the thumb's render
            // window must still be denied.
            onContextMenuRequested: function(request) {
                console.info("iframe-plasma[mini-ctx] suppressed menu pos=" + request.position);
                request.accepted = true;
            }
            onSelectClientCertificate: function(selection) {
                console.warn("iframe-plasma[mini-cert] rejected client-cert request host="
                    + selection.host + " count=" + selection.certificates.length);
                selection.selectNone();
            }
            onWebAuthUxRequested: function(request) {
                console.warn("iframe-plasma[mini-webauth] cancelled state=" + request.state);
                request.cancel();
            }
            // Parity with WebTab.qml's tooltipRequested suppression — Qt's
            // default tooltip is a top-level platform widget that escapes the
            // miniView's clip rect, so a hostile page can paint arbitrary
            // text next to the panel slot. The thumb is `enabled:false` so
            // pointer hover doesn't reach Chromium normally, but the request
            // can still fire from JS-injected `dispatchEvent` paths or
            // touch-equivalent inputs depending on Qt build flags.
            onTooltipRequested: function(request) {
                request.accepted = true;
            }
            onColorDialogRequested: function(request) {
                console.warn("iframe-plasma[mini-color] rejected color dialog");
                request.dialogReject();
            }
            onDesktopMediaRequested: function(request) {
                console.warn("iframe-plasma[mini-dispmedia] cancelled screen-capture request");
                request.cancel();
            }
            onFileSystemAccessRequested: function(request) {
                console.warn("iframe-plasma[mini-fs-access] rejected origin=" + request.origin
                    + " handleType=" + request.handleType);
                request.reject();
            }
            onQuotaRequested: function(request) {
                console.warn("iframe-plasma[mini-quota] rejected origin=" + request.origin
                    + " requestedSize=" + request.requestedSize);
                request.reject();
            }
            // Reject every page-driven HTTP-auth dialog on the thumb. Without
            // this, a 401 from a configured or redirect-chain URL pops Qt's
            // system Basic-auth dialog over the panel slot — the thumb is
            // passive (enabled:false) but the modal credential prompt is a
            // separate top-level widget that still appears, prompting an
            // unattended user with no widget interaction. WebTab.qml routes
            // 401s through the controlled overlay flow; the thumb has no UX
            // path for that, so deny outright.
            onAuthenticationDialogRequested: function(request) {
                console.warn("iframe-plasma[mini-auth] rejected dialog type=" + request.type
                    + " url=" + request.url);
                request.dialogReject();
                request.accepted = true;
            }
            // Log-only on the thumb (no auto-reload): the thumb is a passive
            // render of an unattended URL. A crash-loop here would keep
            // hammering Chromium with no UI feedback to the user. Surface the
            // event to the journal so plasmashell-restart hooks have a trail.
            onRenderProcessTerminated: function(status, exitCode) {
                console.warn("iframe-plasma[mini-render] terminated status=" + status
                    + " exitCode=" + exitCode);
            }

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
            //
            // `message` originates from JS running in an attacker-controlled
            // page (compromised Grafana panel, hostile redirect target). Strip
            // C0 / DEL bytes — a crafted `console.log("[ifp-thumb] \x1b[2J…")`
            // injects ANSI escapes that terminal-bound journalctl viewers
            // interpret (clear-screen, fake prompt, log-spoofed lines). Cap at
            // 512 chars so a single megabyte log line can't blow up the
            // journal buffer.
            onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID) {
                if (message && message.indexOf('[ifp-thumb]') !== -1) {
                    const safe = String(message).replace(/[\x00-\x1f\x7f]/g, '?').slice(0, 512);
                    console.info("iframe-plasma" + safe);
                }
            }

            // Crop IIFE source comes from CropEngine.js — shared with the
            // popup view in WebTab.qml. apply() dispatches on element tag:
            // <canvas> → uPlot pixel-blit (Grafana presets); anything else
            // → generic element-isolation (hide siblings, position target
            // fixed at viewport — Streamystats, Jellyfin etc.).
            function applyThumbCrop(selector) {
                console.info("iframe-plasma[thumb] applyThumbCrop ENTRY selector=" + JSON.stringify(selector)
                    + " loading=" + miniView.loading + " url=" + miniView.url);
                runJavaScript(CropEngine.buildApplyJs(selector), function(r) {
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

            // Freeze the thumbnail (suspends its Grafana JS, the in-page
            // refresh and the 3 s crop poll) when the slot isn't observed —
            // screen locked or panel off-screen. stalenessSec is the auto-
            // cycle interval: a thumbnail frozen longer than one rotation
            // reloads on resume, so the rotating preview is never stale.
            WebViewLifecycle {
                target: miniView
                desiredActive: compact.miniActive
                freezeDelaySec: Plasmoid.configuration.webViewFreezeDelaySec
                discardDelaySec: Plasmoid.configuration.webViewDiscardDelaySec
                stalenessSec: Math.max(5, Plasmoid.configuration.autoCycleIntervalSec)
            }

            }
        }

        // --- Icon fallback --------------------------------------------------
        // Shows whenever the live thumbnail isn't: feature disabled, no tab,
        // screen locked, or panel slot off-screen.
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) - Kirigami.Units.smallSpacing
            height: width
            visible: !compact.miniActive
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
        id: fullRoot
        // Layout.preferred* only applies on first-ever open; once the user
        // drag-resizes the popup, Plasma persists `popupWidth/popupHeight`
        // in appletsrc and that value wins on subsequent opens.
        Layout.minimumWidth:  Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth:  800
        Layout.preferredHeight: 500
        spacing: 0

        // Bridge for root.savePickedSelector — it can't reach the
        // Repeater's `id: repeater` directly because QML Components
        // are ID-isolated (a lazy fullRepresentation Component owns a
        // separate ID namespace from root). The previous direct
        // `repeater.itemAt(tabIdx)` from root scope threw
        // `ReferenceError: repeater is not defined`, the try/catch
        // swallowed it, and every picker save silently no-op'd
        // (urlsJson never even got written). This helper lives in
        // scope and routes the apply through WebTab.applyImmediately.
        function applyPopupSelectorAt(tabIdx, sel) {
            const wt = repeater.itemAt(tabIdx);
            if (wt && typeof wt.applyImmediately === "function") {
                wt.applyImmediately(sel);
                return true;
            }
            return false;
        }

        // Save-selector dialog (opened from picker callback). Lazy-built via
        // Component.createObject so the dialog gets a real parent Item (this
        // ColumnLayout's id `fullRoot`) at construction time. A plain inline
        // QQC.Dialog inside a plasmoid fullRepresentation silently renders
        // nothing — the popup host is a PlasmaWindow (not a Kirigami
        // ApplicationWindow), so the dialog's default `applicationWindow().
        // overlay` parent resolves undefined and the popup escapes the
        // layout flow into a zero-sized item. Same pattern as KDE's
        // bluedevil ForgetDeviceDialog.
        Component {
            id: savePickedDialogComponent
            Kirigami.PromptDialog {
                id: savePickedDialog
                parent: fullRoot
                modal: true
                title: i18n("Save picked element selector")
                property int tabIdx: -1
                property string pickedSelector: ""
                standardButtons: Kirigami.Dialog.NoButton
                customFooterActions: [
                    Kirigami.Action {
                        text: i18n("Save for both")
                        icon.name: "edit-copy"
                        onTriggered: {
                            root.savePickedSelector(savePickedDialog.tabIdx, "both",
                                                    savePickedDialog.pickedSelector);
                            savePickedDialog.close();
                        }
                    },
                    Kirigami.Action {
                        text: i18n("Save as Thumbnail")
                        icon.name: "view-preview"
                        onTriggered: {
                            root.savePickedSelector(savePickedDialog.tabIdx, "thumb",
                                                    savePickedDialog.pickedSelector);
                            savePickedDialog.close();
                        }
                    },
                    Kirigami.Action {
                        text: i18n("Save as Widget popup")
                        icon.name: "view-fullscreen"
                        onTriggered: {
                            root.savePickedSelector(savePickedDialog.tabIdx, "popup",
                                                    savePickedDialog.pickedSelector);
                            savePickedDialog.close();
                        }
                    },
                    Kirigami.Action {
                        text: i18n("Cancel")
                        icon.name: "dialog-cancel"
                        onTriggered: savePickedDialog.close()
                    }
                ]
                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing
                    QQC.Label {
                        Layout.fillWidth: true
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 28
                        wrapMode: Text.Wrap
                        text: i18n("Picked selector — choose where to apply it:")
                    }
                    QQC.TextField {
                        Layout.fillWidth: true
                        readOnly: true
                        selectByMouse: true
                        text: savePickedDialog.pickedSelector
                        font.family: Theme.fontBody
                    }
                    QQC.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Kirigami.Theme.disabledTextColor
                        text: i18n("Thumbnail crops the panel slot only; Widget crops the full popup view.")
                    }
                }
                // Save path: savePickedSelector already called
                // applyImmediately() — no need to re-fire here, doing so
                // would race the property-binding chain and risk
                // re-applying the OLD value (the property's declarative
                // binding may not have re-evaluated yet from the
                // in-place modelData mutation). Cancel path: pickerTimer
                // already called _applyPopupSelector on the empty result
                // restore path before this dialog had a chance to open
                // (cancel doesn't open the dialog at all). Just clean up
                // the Dialog instance.
                onClosed: destroy()
            }
        }

        function showSavePickedDialog(tabIdx, sel) {
            const dlg = savePickedDialogComponent.createObject(fullRoot, {
                tabIdx: tabIdx,
                pickedSelector: sel
            });
            if (dlg) dlg.open();
        }

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
            isGrafana:       root.activeTab ? root.isGrafanaEmbed(root.activeTab.webView.url) : false
            onReloadClicked:        root.activeTab?.reload()
            onHardReloadClicked:    root.activeTab?.hardReload()
            onOpenExternalClicked:  root.activeTab?.openExternal()
            onClearCookiesClicked:  root.clearCacheAndReload()
            onSelectTimeRange:        range    => root.activeTab?.setTimeRange(range)
            onSelectRefreshInterval:  interval => root.activeTab?.setRefreshInterval(interval)
            // Toggle: if the active tab's picker is already running,
            // cancel it (same shape as in-page Esc); otherwise start.
            onPickElementClicked: {
                const t = root.activeTab;
                if (!t) return;
                if (t.pickerActive) t.cancelPicker();
                else                t.startPicker();
            }
        }

        CyberTabBar {
            id: tabBar
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showTabBar && root.tabs.length > 1
            tabs: root.tabs
            currentIndex: root.currentTabIndex
            statuses: root.tabStatuses
            popupExpanded: root.expanded
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

                    profile: root.profileForAuthId(modelData.authProfileId)
                    // Authelia host is now per-profile (0.4.0+). Falls back to
                    // the deprecated global setting for unmigrated configs.
                    autheliaHost: {
                        const p = root.profileById(modelData.authProfileId);
                        return (p && p.autheliaHost) || Plasmoid.configuration.autheliaHost || "";
                    }
                    zoomPct: Plasmoid.configuration.zoomFactor
                    url: root.resolveUrl(modelData)
                    // Popup-only CSS-selector crop. fullPanel mode (or empty
                    // selector) → no crop; custom mode passes the user's
                    // selector to CropEngine isolation in WebTab.qml.
                    popupSelector: (modelData.popupMode === "custom")
                                   ? (modelData.popupSelector || "")
                                   : ""
                    debugPort: Plasmoid.configuration.remoteDebuggingPort
                    // Live only for the tab actually on screen; the rest are
                    // frozen, then discarded after a long idle.
                    desiredActive: root.fullRepVisible
                                   && index === root.currentTabIndex
                                   && !root.screenLocked
                    freezeDelaySec: Plasmoid.configuration.webViewFreezeDelaySec
                    discardDelaySec: Plasmoid.configuration.webViewDiscardDelaySec
                    onBasicAuthRequested: req => root.handleBasicAuth(req, modelData)
                    onAuthRequired: () => root.expanded = true
                    onLoadStatusChanged: root.setTabStatus(index, loadStatus)
                    onSelectorPicked: sel => root.handlePickedSelector(index, sel)
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
