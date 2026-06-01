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
import "./RowSchema.js" as RowSchema
import "./UrlUtils.js" as UrlUtils

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

    // Default Plasma popups auto-close on focus loss. For a live-dashboard
    // widget the user often wants to keep the popup open while working in
    // another window — the toolbar pin button writes this kcfg key. The
    // binding re-evaluates the moment the key flips. Canonical pattern from
    // plasma-workspace systemtray/digital-clock applets.
    hideOnWindowDeactivate: !Plasmoid.configuration.popupPinned

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
        return UrlUtils.parseAuthProfiles(jsonStr);
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
        // Depend on the metadata serial: an in-place Apply that renames
        // the active tab's label leaves this tooltip painting the old
        // name otherwise. See _tabsMetadataSerial docblock.
        const _tick = root._tabsMetadataSerial;
        if (tabs.length === 0) return i18n("iframe Plasma");
        const cur = tabs[currentTabIndex];
        return cur && cur.label ? cur.label : i18n("iframe Plasma");
    }
    toolTipSubText: {
        // Subtext is index-position-only, no per-tab fields — serial
        // dependency unnecessary.
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
        return UrlUtils.isSafeTabUrl(s);
    }

    function parseTabs(jsonStr) {
        return UrlUtils.parseTabs(jsonStr);
    }

    function resolveTheme() {
        return UrlUtils.pickThemeForBackground(
            Plasmoid.configuration.themeMode,
            Kirigami.Theme.backgroundColor);
    }

    function resolveUrl(tab) {
        if (!tab || !tab.url) return "about:blank";
        return UrlUtils.substituteTheme(tab.url, resolveTheme());
    }

    // Used by the toolbar to gate the Time-range and Refresh-interval
    // chips, which rewrite Grafana-shaped URL params. Implementation
    // lives in UrlUtils.js (also shared by ConfigUrls.qml).
    function isGrafanaEmbed(u) {
        return UrlUtils.isGrafanaEmbed(u);
    }

    // Live session time-range from the popup's active WebTab — updates when
    // the user picks a different preset in the toolbar's time-range
    // dropdown. Surfaced for per-thumbnail Connections handlers in the
    // compact rep, which pass it as the `overrideRange` argument to
    // resolveThumbUrlWith — but ONLY when this delegate's tab is the
    // popup-active one AND the user explicitly changed the range (i.e. the
    // active tab itself didn't just swap). See the compact rep's per-
    // delegate handler for the gating logic that distinguishes user-
    // edited range changes from tab-switch / auto-rotate side effects.
    readonly property string activeTabSessionRange:
        (activeTab && activeTab.currentTimeRange) || ""

    // Per-thumbnail URL resolver. `thumbTimeRange` semantics:
    //   - "" or "auto"     → use the URL's own from/to (no rewrite). When
    //                         the popup's currently-active tab is THIS tab
    //                         and the user picked a range in the popup
    //                         toolbar, the per-delegate handler bumps
    //                         `sessionRangeOverride` and that range comes
    //                         in here via `overrideRange`.
    //   - "5m"/"24h"/"7d"  → hard-override the URL's from/to for the
    //                         thumbnail; popup unaffected.
    //
    // Static URL for a single per-tab thumbnail. Reads ONLY per-tab data
    // (tab.url, tab.thumbTimeRange) plus the optional `overrideRange`
    // parameter the caller passes — does NOT read root.currentTabIndex or
    // root.activeTabSessionRange. That decoupling is what stops a popup tab
    // switch (or auto-rotate tick) from cascade-reloading every per-tab
    // WebEngineView in the compact rep: each delegate's url binding now
    // re-evaluates only when its own tab object's fields change or when its
    // own `sessionRangeOverride` updates (controlled by the per-delegate
    // Connections handler down in compactRepresentation).
    //
    // `thumbTimeRange === "auto"` is now opaque to the URL: callers that
    // want the auto-follow-popup-time-range behaviour pass the popup's
    // current session range as `overrideRange` (handled per-delegate; see
    // the compact-rep WebEngineView's Connections handler).
    function resolveThumbUrlWith(tab, overrideRange) {
        if (!tab || !tab.url) return "about:blank";
        let url = String(tab.url);
        let range = "";
        if (overrideRange && overrideRange.length > 0) {
            range = overrideRange;
        } else if (tab.thumbTimeRange && tab.thumbTimeRange !== "auto") {
            range = tab.thumbTimeRange;
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
            // Split off the fragment first: the from/to strip char class `[^&]*`
            // does not terminate on `#`, so a tab URL with a trailing fragment
            // (e.g. Grafana's `Share → Direct link` appends `#viewPanel-N`) would
            // have the second strip greedily eat through the fragment, and the
            // append would land params after `#`, silently absorbed by Grafana
            // as fragment text. Same regex-terminator class as Runs #4/#9.
            const hashIdx = url.indexOf('#');
            let path = hashIdx === -1 ? url : url.slice(0, hashIdx);
            const frag = hashIdx === -1 ? "" : url.slice(hashIdx);
            path = path.replace(/[?&]from=[^&]*/g, function(m) { return m.charAt(0) === '?' ? '?' : ''; });
            path = path.replace(/[?&]to=[^&]*/g,   function(m) { return m.charAt(0) === '?' ? '?' : ''; });
            path = path.replace(/\?&/, '?').replace(/[?&]$/, '');
            const sep = path.indexOf('?') === -1 ? '?' : '&';
            url = path + sep + 'from=now-' + range + '&to=now' + frag;
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
            const newTabs = root.parseTabs(Plasmoid.configuration.urlsJson);
            // Fast path: metadata-only Apply (keyword chip add, scale-mode
            // pick, hide-label toggle, label rename, etc.) leaves URLs +
            // profile assignments + ordering intact. In that case mutate
            // root.tabs[i] in place — no Repeater rebuild, no
            // WebEngineView destruction, no popup blank. Same template
            // savePickedSelector uses for picker writes (L771-869).
            if (UrlUtils.isMetadataOnlyTabsChange(root.tabs, newTabs)) {
                root._applyTabsMetadataInPlace(newTabs);
                return;
            }
            // Structural change — accept the rebuild. URL added/removed/
            // edited or profile reassigned: the WebEngineView at the
            // affected index has to navigate to the new URL or rebind
            // to a different profile, so destroying the delegates is
            // the cheapest correct path.
            root.tabs = newTabs;
            // Tab indices just shifted; the index-keyed runtime-exclusion map
            // would now apply stale entries to the wrong tabs. Live thumbnail
            // miniViews re-emit their hit state on reload, so clearing here is
            // safe and avoids a non-live (text/icon) tab inheriting a
            // stale-excluded index and being dropped from the rotation.
            root._runtimeExcluded = ({});
            if (root.currentTabIndex >= root.tabs.length) {
                root.setCurrentTab(Math.max(0, root.tabs.length - 1));
            }
            root.primeAuthProfiles();
        }
        function onAuthProfilesJsonChanged() {
            // Snapshot the pre-change profile bodies BEFORE we replace
            // root.authProfiles. Each entry's full JSON body — minus the
            // KWallet-resident secret which doesn't live in this JSON
            // anyway — is the diff target. Profiles with identical bodies
            // don't need any tab to reload.
            const oldById = {};
            for (const p of root.authProfiles) {
                if (p && p.id) oldById[p.id] = JSON.stringify(p);
            }
            root.authProfiles = root.parseAuthProfiles(Plasmoid.configuration.authProfilesJson);
            // Per-profile preempt flags may have flipped — resync interceptor
            // attach/detach BEFORE priming so applyProfile writes hit only
            // profiles that are actually attached.
            root.syncInterceptor();
            root.primeAuthProfiles();
            // Compute the set of changed profile ids (added / removed /
            // body-different). Only tabs referencing a changed id need
            // the soft reload — the blanket reloadAll() this used to call
            // re-navigated every other tab in the pinned popup for no
            // reason.
            const changed = {};
            const newById = {};
            for (const p of root.authProfiles) {
                if (p && p.id) {
                    newById[p.id] = JSON.stringify(p);
                    if (newById[p.id] !== oldById[p.id]) changed[p.id] = true;
                }
            }
            for (const id in oldById) {
                if (!(id in newById)) changed[id] = true;
            }
            const changedIds = Object.keys(changed);
            if (changedIds.length === 0) {
                console.info("iframe-plasma[auth] profiles unchanged; no tab reloads");
                return;
            }
            console.info("iframe-plasma[auth] changed profile ids=" + JSON.stringify(changedIds)
                + " — reloading referencing tabs");
            for (let i = 0; i < root.tabs.length; i++) {
                const t = root.tabs[i];
                if (t && t.authProfileId && (t.authProfileId in changed)) {
                    root._tabReloadRequested(i, "soft");
                }
            }
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
        // Bumped by ConfigAuth on every successful setMap/removeKey.
        // The C++ secretsChanged QML signal can't cross from the
        // config-dialog engine to the widget engine, so we route the
        // notification via KConfig instead. On bump, re-prime + reload
        // so the live interceptor picks up a freshly typed password
        // and any 401-stuck WebTab re-requests with the new header.
        function onAuthProfilesSecretsSerialChanged() {
            console.info("iframe-plasma[auth] authProfilesSecretsSerial bumped -> re-prime + reloadAll");
            root.primeAuthProfiles();
            root.reloadAll();
        }
    }

    // After the user saves a fresh password (typical post-Backup-Import
    // case: profile metadata round-trips fine but the wallet entry is
    // missing), re-prime AND reload so the interceptor picks up the new
    // secret AND any tab currently sitting on a 401/Authelia page re-
    // requests with the now-registered Authorization header. Mirrors
    // the onAuthProfilesJsonChanged path. Pre-fix, the freshly-saved
    // password reached KWallet and the interceptor, but the active
    // WebTab kept showing its cached failed-auth render.
    Connections {
        target: root.authSupport
        enabled: !!root.authSupport
        function onSecretsChanged() {
            console.info("iframe-plasma[auth] secretsChanged -> re-prime + reloadAll");
            root.primeAuthProfiles();
            root.reloadAll();
        }
    }

    // Cancel any active selector picker when the popup hides. Without
    // this, the per-tab pickerTimer keeps polling __ifpPicked for up
    // to 2 minutes after the popup is gone (the timer lives in the
    // WebTab body, not the popup), and a successful pick lands in
    // handlePickedSelector with fullRepresentationItem==null → the
    // selector is silently dropped with only a warn log. Up to 2
    // minutes of pick effort silently lost on every unpinned popup
    // auto-close mid-pick.
    onExpandedChanged: {
        if (!expanded && fullRepresentationItem
            && typeof fullRepresentationItem.cancelAllPickers === "function")
        {
            fullRepresentationItem.cancelAllPickers();
        }
    }

    Component.onCompleted: {
        // Seed root.tabs from the current urlsJson. The `property var
        // tabs: []` declaration above intentionally has NO binding —
        // see the comment there.
        root.tabs = root.parseTabs(Plasmoid.configuration.urlsJson);

        // Prime the auth interceptor once the initial config is parsed.
        Qt.callLater(function() {
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
        return base + "/io.github.v3DJG6GL.iframe-plasma/" + (Plasmoid.id || 0);
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
        // Per-profile preempt gate. Only attach the URL-interceptor when this
        // specific profile wants pre-emption — bearer/raw default true,
        // basic defaults false (the 401-dialog fallback in handleBasicAuth
        // handles those without leaking the header to cross-origin requests).
        const profileEntry = root.profileById(key);
        const wantsPreempt = profileEntry && profileEntry.preempt === true;
        if (root.authSupport && wantsPreempt) {
            const interceptor = root.authSupport.createInterceptor();
            if (interceptor && interceptor.attachTo(profile)) {
                root._interceptors[key] = interceptor;
                console.info("iframe-plasma[profile] created+attached interceptor for id=" + key);
            } else {
                console.warn("iframe-plasma[profile] failed to create/attach interceptor for id=" + key);
            }
        } else {
            console.info("iframe-plasma[profile] created named profile id=" + key + " (preempt=false, no interceptor)");
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

    // Per-URL `thumbIconName` is a tagged string with three forms:
    //   plain name           → KDE theme icon ("applications-internet")
    //   "bundled:<name>"     → ./icons/bundled/<name>.svg
    //   "file:///path"       → straight file URL (Kirigami.Icon accepts it)
    // Empty / undefined falls back to the plasmoid icon so a half-
    // configured `icon` mode still looks intentional. ConfigUrls.qml has
    // its own copy (resolveIconPreview) for the per-card preview.
    function resolveIconSource(name) {
        // DiD allow-list. parseTabs runs before normaliseTabRow on the
        // import path, so a malicious thumbIconName can reach here in the
        // gap between Import-Apply and the next ConfigUrls.repopulate().
        const safe = RowSchema.sanitizeIconName(name);
        if (!safe) return Plasmoid.icon || "applications-internet";
        if (safe.startsWith("bundled:"))
            return Qt.resolvedUrl("../icons/bundled/" + safe.substring(8) + ".svg");
        return safe;
    }

    // Resolve the LIVE row object for a Repeater delegate at `idx`. In
    // Qt 6.10, a Repeater whose `model` is a JS array snapshots each
    // element into the delegate's `modelData` AT DELEGATE CREATION TIME —
    // mutating `root.tabs[idx].x` later is NOT visible through
    // `modelData.x`. Bindings that need to react to in-place metadata
    // Apply (or picker save) must read through `root.tabs[idx]` instead.
    // Pair this with `const _tick = root._tabsMetadataSerial;` to install
    // the metadata-serial dep; the serial bump re-triggers the binding,
    // and _liveRow returns the now-mutated row.
    //
    // The `fallback` arg is used during the brief window where a
    // structural change shrinks root.tabs while a delegate is being torn
    // down — idx may transiently be out-of-range. Passing modelData /
    // ownTab as the fallback keeps the binding well-defined; QML schedules
    // the delegate destruction shortly after.
    function _liveRow(idx, fallback) {
        const arr = root.tabs;
        if (arr && idx >= 0 && idx < arr.length) return arr[idx];
        return fallback || null;
    }

    // Per-tab thumbnail CSS selector. Lifted out of the compact rep so the
    // new N-parallel architecture lets each per-tab WebEngineView compute
    // its own selector instead of all sharing one tied to the popup's
    // active tab. Presets target Grafana's uPlot DOM; .u-wrap > canvas is
    // the painted bitmap, guaranteed non-transparent.
    function thumbSelectorFor(tab) {
        if (!tab) return "";
        switch (tab.thumbMode || "chartOnly") {
        case "chartOnly":     return ".u-wrap > canvas";
        case "chartWithAxes": return ".u-wrap";
        case "custom":        return tab.thumbSelector || "";
        default:              return "";   // fullPanel / text / icon / excluded
        }
    }

    // Attach/detach the interceptor whenever the toggle or plugin availability changes.
    // Signal fired from root-level events; WebTab listens and reloads its view.
    // Cleaner than reaching into fullRepresentation's StackLayout from outside.
    signal reloadAllRequested()
    function reloadAll() { reloadAllRequested() }

    // Per-tab reload broadcast. Both the popup WebTab and the compact-rep
    // miniView delegate subscribe and filter by their own index — so a
    // single toolbar click / keyboard shortcut reloads both the popup tab
    // AND its matching panel-slot thumbnail. `kind`:
    //   "soft" → reload() on each
    //   "hard" → triggerWebAction(ReloadAndBypassCache) — bypasses HTTP cache
    // The cache-clear path (clearCacheAndReload) emits "soft" once the
    // profile-wide clearHttpCache completes; cache-clear is profile-scoped
    // so both views observe the cleared cache on their next fetch.
    signal _tabReloadRequested(int tabIdx, string kind)

    // Soft-reload ONLY the background compact miniView at tabIdx — not the
    // foreground popup tab. Used after an auth-completion: the popup tab that
    // fired authSucceeded is already on the authenticated page, but the
    // compact-rep view at the same index is still parked on the redirected
    // /login render and needs to re-fetch with the now-valid cookies.
    // Reusing _tabReloadRequested here would also reload the foreground tab.
    signal _compactReloadRequested(int tabIdx)

    // Monotonic NOTIFY counter for in-place metadata updates to
    // root.tabs[]. When the KCM Apply path detects a metadata-only
    // urlsJson change (no URL/profile/order change — see
    // UrlUtils.isMetadataOnlyTabsChange), it writes the new fields onto
    // the existing root.tabs[i] JS objects rather than reassigning the
    // whole array. QML emits no NOTIFY for plain-JS field writes on a
    // `var`, so any binding that reads `t.label`, `t.thumbMode`, etc.
    // would stay stale. Bumping this serial inside the in-place
    // applicator re-evaluates every binding that touches it. Mirrors the
    // `authProfilesSecretsSerial` pattern in config/main.xml.
    //
    // Read it as a const-assigned dependency at the top of binding
    // expressions:
    //     readonly property string foo: {
    //         const _tick = root._tabsMetadataSerial;   // depend
    //         return modelData.thumbText || "";
    //     }
    //
    // IMPORTANT: do NOT use `void root._tabsMetadataSerial;` for this —
    // the Qt 6.10 QML/V4 JIT treats a bare `void X.Y` statement as dead
    // code (no observable side effect, result discarded) and drops the
    // read, taking the dependency-capture with it. The binding then only
    // re-evaluates when its other deps change — for the metadata-only
    // Apply path (no Repeater rebuild) that means NEVER, and the
    // selector / mode / label silently freezes at first-load value. Use
    // `const _tick = ...` instead — the const-declaration cannot be
    // elided, so the property read survives the optimizer.
    property int _tabsMetadataSerial: 0

    // Companion signal for IMPERATIVE consumers (Connections handlers
    // that need to re-run applyThumbCrop / _applyPopupSelector when a
    // tab's metadata changes underneath them). `tabIdx` is -1 to mean
    // "any/all tabs changed" — the in-place applicator emits -1 since
    // it processes the whole array at once.
    signal _tabsMetadataChanged(int tabIdx)

    // Apply metadata-only field updates from `newArr` onto the existing
    // root.tabs[i] objects in place, then bump the serial + emit the
    // signal so live delegates pick up the change without their
    // WebEngineView being destroyed and re-navigated. Precondition:
    // UrlUtils.isMetadataOnlyTabsChange(root.tabs, newArr) === true.
    function _applyTabsMetadataInPlace(newArr) {
        const cur = root.tabs;
        if (!Array.isArray(cur) || !Array.isArray(newArr)
            || cur.length !== newArr.length) {
            console.warn("iframe-plasma[urls] in-place apply called with"
                + " mismatched lengths cur=" + (cur ? cur.length : "?")
                + " new=" + (newArr ? newArr.length : "?"));
            return;
        }
        // Rows where the visible render MODE flipped (chartOnly ↔ custom ↔
        // fullPanel etc. on either the thumbnail or the popup). The
        // lightweight selector-swap path (CropEngine buildApplyJs / buildClearJs
        // via the serial+signal) cannot reliably re-flow stateful page
        // engines (Grafana's uPlot canvas caches its constrained size, SPA
        // routers keep stale layouts) when the wrapping isolation flips on
        // or off — the *intended* viewport is now genuinely different. A
        // soft reload re-navigates to the same URL and lets the page paint
        // at its new natural extent. Per-tab only, no other tabs touched.
        const reloadTabs = [];
        // Tabs whose exclude-keyword list changed AND that currently hold a
        // runtime exclusion. Their excluded miniView is frozen/discarded
        // (desiredActive is gated by previewTabIdx, which this exclusion
        // forces to -1), so it can never run the CropEngine hit=false scan
        // that would clear itself — a deadlock. Drop the stale entry here so
        // the tab rejoins the rotation, revives its renderer, and re-emits
        // its live keyword state fresh against the new list.
        let exclusionCleared = false;
        for (let i = 0; i < cur.length; i++) {
            const o = cur[i];
            const n = newArr[i];
            if (!o || !n) continue;
            const oldThumbMode = o.thumbMode || "";
            const oldPopupMode = o.popupMode || "";
            const newThumbMode = n.thumbMode || "";
            const newPopupMode = n.popupMode || "";
            const oldKeywords = Array.isArray(o.thumbExcludeKeywords)
                                ? o.thumbExcludeKeywords.join(" ") : "";
            const newKeywords = Array.isArray(n.thumbExcludeKeywords)
                                ? n.thumbExcludeKeywords.join(" ") : "";
            // Copy every metadata field. authProfileId and url are
            // checked structurally above, but copy authProfileId too
            // so the row object stays internally consistent if a
            // future Apply changes a metadata field that depends on
            // it (none today, but cheap).
            o.label                = n.label || "";
            o.thumbMode            = n.thumbMode || "chartOnly";
            o.thumbSelector        = n.thumbSelector || "";
            o.thumbText            = n.thumbText || "";
            o.thumbIconName        = n.thumbIconName || "";
            o.thumbTimeRange       = n.thumbTimeRange || "";
            o.thumbScaleMode       = n.thumbScaleMode || "fit";
            o.thumbExcludeKeywords = Array.isArray(n.thumbExcludeKeywords)
                                     ? n.thumbExcludeKeywords.slice()
                                     : [];
            o.thumbShowLabel       = n.thumbShowLabel === true;
            o.popupMode            = n.popupMode || "fullPanel";
            o.popupSelector        = n.popupSelector || "";
            if (oldThumbMode !== newThumbMode || oldPopupMode !== newPopupMode) {
                reloadTabs.push(i);
            }
            if (oldKeywords !== newKeywords && root._runtimeExcluded[i]) {
                delete root._runtimeExcluded[i];
                exclusionCleared = true;
                console.info("iframe-plasma[runtime-excl] cleared idx=" + i
                    + " (exclude-keyword list changed)");
            }
        }
        if (exclusionCleared) root._runtimeExclusionSerial++;
        root._tabsMetadataSerial = root._tabsMetadataSerial + 1;
        root._tabsMetadataChanged(-1);
        console.info("iframe-plasma[urls] metadata-only apply rows=" + cur.length
            + " serial=" + root._tabsMetadataSerial
            + " modeChangedTabs=" + JSON.stringify(reloadTabs));
        // Per-tab soft reloads (popup WebTab + miniView) for the mode-flip
        // rows. Uses the broadcast _tabReloadRequested signal — same
        // routing as Ctrl+R / the toolbar reload button — so the popup
        // tab + slot delegate both pick it up, and the page renders fresh
        // at the now-correct viewport size.
        for (let r = 0; r < reloadTabs.length; r++) {
            root._tabReloadRequested(reloadTabs[r], "soft");
        }
    }

    // Session-only runtime exclusion map. Populated by miniView delegates
    // when their CropEngine-injected JS reports `[ifp-keyword] hit=true`
    // for a configured exclude-keyword (see ConfigUrls' thumbExcludeKeywords
    // field). Read by cycleTimer via UrlUtils.nextCycleTabIndex — the
    // auto-cycle steps past indices that appear here. NOT persisted; on
    // reload the next CropEngine apply re-emits the live state within ~250ms.
    //
    // The exclusion is STICKY: an entry stays until the tab's own CropEngine
    // emits hit=false (keyword cleared) or its keyword config changes. There
    // is deliberately no TTL re-check — that flapped the tab back into the
    // rotation every interval showing a placeholder, then could not re-confirm
    // because the rejoined tab was frozen. Instead an excluded tab is kept
    // Active-but-invisible (ownIsRuntimeExcluded → desiredActive) so its
    // CropEngine keeps scanning and reports the keyword clearing on its own.
    //
    // Plain object {tabIdx: <exclusion timestamp in ms>}. The value is the
    // Date.now() at which the exclusion was recorded (kept for diagnostics);
    // both nextCycleTabIndex and previewTabIdx only test truthiness, so the
    // timestamp reads as "excluded". cycleTimer reads imperatively inside its
    // handler, so we do NOT depend on a binding invalidation here — the
    // auto-generated _runtimeExcludedChanged NOTIFY exists for QML book-keeping
    // but no consumer subscribes to it. setRuntimeExcluded mutates the same
    // object in place, which is intentional and safe because the read path
    // doesn't cache.
    property var _runtimeExcluded: ({})

    // Bumped on every _runtimeExcluded mutation (set / clear).
    // The map is mutated in place and fires no NOTIFY of its own, so the
    // panel-slot's previewTabIdx binding depends on this serial to drop a
    // tab the instant its keyword matches (and restore it when cleared).
    // Mirrors the _tabsMetadataSerial pattern. cycleTimer still reads the
    // map imperatively and does not need it.
    property int _runtimeExclusionSerial: 0

    // Idempotent setter for the runtime-exclusion map. Called from each
    // miniView's onJavaScriptConsoleMessage handler when the
    // [ifp-keyword] hit boolean transitions. Skips the mutation when
    // the desired state already holds (CropEngine itself only emits on
    // transitions, but a tab reload re-seeds and could produce a
    // duplicate post-restart emit).
    function setRuntimeExcluded(tabIdx, hit) {
        if (tabIdx < 0) return;
        const was = !!root._runtimeExcluded[tabIdx];
        if (was === !!hit) return;
        if (hit) {
            root._runtimeExcluded[tabIdx] = Date.now();
        } else {
            delete root._runtimeExcluded[tabIdx];
        }
        root._runtimeExclusionSerial++;
        console.info("iframe-plasma[runtime-excl] idx=" + tabIdx + " hit=" + hit);
    }

    function syncInterceptor() {
        console.info("iframe-plasma[sync] authSupport=" + (root.authSupport ? "available" : "null"));
        if (!root.authSupport) return;
        // Per-profile attach/detach. Walk every named profile (the ephemeral
        // profile is intentionally skipped — auth=None tabs never get an
        // Authorization header). The gate is `preempt` on the matching
        // authProfilesJson entry; profiles whose entry was removed get
        // detached defensively.
        for (const key in root._profiles) {
            if (key.length === 0) continue;
            const profile = root._profiles[key];
            const entry = root.profileById(key);
            const wantsPreempt = entry && entry.preempt === true;
            let interceptor = root._interceptors[key];
            if (wantsPreempt) {
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
            // Resolve ${theme} (and any future placeholders) before parsing:
            // `new URL("https://${theme}.example.com/")` throws because
            // `$`/`{`/`}` are invalid in a WHATWG host, and the inner catch
            // would silently `continue` — the tab would never get its host
            // added to profilesInUse, so applyProfile would not register
            // a header for it and the tab would land unauthenticated.
            let host;
            try { host = new URL(root.resolveUrl(t)).host; } catch (e) { continue; }
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
            // `none` profiles inject no header — page handles its own login.
            // Skip the KWallet read entirely so unlock prompts don't fire
            // for profiles that semantically don't need a secret.
            if ((profile.authType || "basic") === "none") {
                continue;
            }
            const secrets = root.authSupport.getMap(root.authSupport.profileKey(id)) || {};
            // Pick the secret keyed by authType. The previous positional
            // `||` chain returned secrets.password first — so a basic→bearer
            // type switch on a profile whose wallet still held the old
            // password silently fed that password into applyProfile, which
            // synthesises `Authorization: Bearer <plaintext-password>` and
            // emits it on every preempted request. Mismatched type now
            // resolves to "" → skipped below.
            const authType = profile.authType || "basic";
            const secret =
                  authType === "basic"  ? (secrets.password    || "")
                : authType === "bearer" ? (secrets.bearerToken || "")
                : authType === "raw"    ? (secrets.rawHeader   || "")
                                        : "";
            if (secret.length === 0) {
                // Distinguish wallet-unavailable (locked / disabled /
                // user-cancelled unlock at autostart) from wallet-open-
                // but-entry-missing. Both surface as empty QVariantMap,
                // but operator triage is very different: the first means
                // "the wallet is locked at primeAuthProfiles time —
                // probably plasmashell autostart firing before KWallet
                // daemon, retry on first unlock", the second means
                // "profile configured in KCM but secret never written —
                // operator needs to re-enter it". Without this split,
                // every Authelia-flash-at-autostart looked identical to
                // a real config error.
                if (root.authSupport.isWalletReady()) {
                    console.info("iframe-plasma[auth] profile " + id
                        + " has no stored secret (wallet open, entry missing) — skipping");
                } else {
                    console.warn("iframe-plasma[auth] profile " + id
                        + " skipped — wallet not available (locked, disabled, or unlock cancelled)");
                }
                continue;
            }
            root.profileForAuthId(id);   // ensure profile + interceptor exist
            const interceptor = root._interceptors[id];
            if (!interceptor) {
                console.info("iframe-plasma[auth] no interceptor for profile id=" + id + " (injection disabled?)");
                continue;
            }
            interceptor.applyProfile(id, authType,
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
        // Hoist fr so the early-return and catch paths can re-engage
        // popup isolation that the picker's _PICKER_START_BODY stripped
        // before the dialog opened. savePickedDialog._saved=true skips
        // its onClosed restore, so this function owns the restore on
        // every exit path.
        const fr = root.fullRepresentationItem;
        function _restoreOnAbort() {
            if (fr && typeof fr.restorePopupSelectorAt === "function") {
                fr.restorePopupSelectorAt(tabIdx);
            }
        }
        try {
            const arr = JSON.parse(Plasmoid.configuration.urlsJson || "[]");
            if (!Array.isArray(arr) || tabIdx < 0 || tabIdx >= arr.length) {
                _restoreOnAbort();
                return;
            }
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
            // that reads root.tabs[tabIdx] (the live array, NOT the
            // Repeater's per-delegate `modelData` snapshot) sees the new
            // values without the Repeater being rebuilt. Capture the row
            // reference once — multiple `root.tabs[tabIdx]` reads through
            // the property var indexer risk going through fresh wrappers
            // (the proven-working `_applyTabsMetadataInPlace` uses the
            // same captured-reference pattern, hence the mirror here).
            const liveRow = root.tabs[tabIdx];
            if (liveRow) {
                liveRow.thumbMode     = entry.thumbMode;
                liveRow.thumbSelector = entry.thumbSelector;
                liveRow.popupMode     = entry.popupMode;
                liveRow.popupSelector = entry.popupSelector;
            }

            // Drive every live consumer through the same serial-bump +
            // signal mechanism used by the KCM-Apply metadata path. This
            // converges the two save paths (picker save and config-dialog
            // Apply) on ONE source of truth — no more imperative writes to
            // wt.popupSelector or miniView.ownSelector that would sever
            // those bindings (Qt6 destroys a binding permanently on any
            // imperative property write). After this:
            //   - WebTab.popupSelector binding re-evaluates → produces
            //     the new value → fires onPopupSelectorChanged →
            //     _applyPopupSelector → applyImmediately. ONE apply,
            //     no flicker.
            //   - miniView.ownSelector binding re-evaluates → its
            //     on_TabsMetadataChanged Connections handler reads the
            //     fresh value and re-runs applyThumbCrop / buildClearJs.
            root._tabsMetadataSerial = root._tabsMetadataSerial + 1;
            root._tabsMetadataChanged(tabIdx);

            // Ground-truth diagnostic — proves the mutation actually
            // landed on the live row that bindings will read. If a future
            // regression resurfaces this is the first line to check: if
            // these print the OLD value, the mutation never took (look
            // at the `liveRow` capture above); if they print the NEW
            // value but a consumer still applies the OLD, the consumer
            // is reading through a stale `modelData` snapshot (look at
            // its binding for `root._liveRow`).
            console.info("iframe-plasma[picker] post-mutation idx=" + tabIdx
                + " liveRow.thumbSelector=" + JSON.stringify(liveRow && liveRow.thumbSelector)
                + " liveRow.popupSelector=" + JSON.stringify(liveRow && liveRow.popupSelector));

            // Thumb-only save edge case: the picker's _PICKER_START_BODY
            // teardown stripped popup isolation BEFORE the dialog opened.
            // popupSelector hasn't changed, so the binding update above
            // produces an identical value — onPopupSelectorChanged elides
            // and nothing re-applies the isolation. Force it back here.
            if (scope === "thumb") {
                if (fr && typeof fr.restorePopupSelectorAt === "function") {
                    fr.restorePopupSelectorAt(tabIdx);
                }
            }

            // Persist to urlsJson — guarded so onUrlsJsonChanged
            // skips the tabs[] reassignment that would have rebuilt
            // the Repeater (blanking every WebEngineView). Compare
            // first: QML's setter elides change-notification for
            // identical values, so re-saving the same selector
            // (e.g. confirming the same pick twice) would leave
            // _suppressTabsRebuildOnce stuck-true and swallow the
            // NEXT legitimate urlsJson change.
            const newJson = JSON.stringify(arr);
            if (newJson === Plasmoid.configuration.urlsJson) {
                console.info("iframe-plasma[picker] urlsJson unchanged; suppression flag not raised");
            } else {
                root._suppressTabsRebuildOnce = true;
                Plasmoid.configuration.urlsJson = newJson;
            }
            console.info("iframe-plasma[picker] saved scope=" + scope
                + " sel=" + JSON.stringify(sel) + " idx=" + tabIdx);
        } catch (e) {
            console.warn("iframe-plasma[picker] save error:", e.message);
            _restoreOnAbort();
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
            // Resolve ${theme} (and any future placeholder) before parsing —
            // `new URL("https://${theme}.example.com/")` throws because $/{ /}
            // are invalid host chars. primeAuthProfiles applies the same
            // substitution; without it here, handleBasicAuth's outer catch
            // swallows the parse error and Qt falls back to its default
            // basic-auth prompt despite stored creds being present.
            const tabHost = new URL(root.resolveUrl(tabConfig)).host;
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

    // Auto-cycle through tabs ONLY while the popup is closed — the panel-slot
    // thumbnail rotates through tabs in the background, but the moment the
    // user opens the widget the cycle pauses so they can browse without the
    // active tab being yanked out from under them.
    //
    // Tabs marked thumbMode="excluded" on the URLs tab are skipped: the next-
    // index walk advances past them in order. If every tab is excluded (or
    // only the current one is non-excluded) the timer keeps running but
    // advanceCycleTab is a no-op for that tick.
    Timer {
        id: cycleTimer
        interval: Math.max(5, Plasmoid.configuration.autoCycleIntervalSec) * 1000
        running: Plasmoid.configuration.autoCycleEnabled
                 && root.tabs.length > 1
                 && !root.expanded
                 && root.compactObservable
        repeat: true
        onTriggered: {
            // Pass the live runtime-exclusion map so any tab whose configured
            // keyword is currently visible on its rendered thumbnail is skipped
            // this tick — and STAYS skipped while the keyword matches. The
            // exclusion is sticky: there is no TTL re-check that would drop the
            // entry and let the tab flap back into the rotation showing a
            // placeholder. An excluded tab keeps its WebEngineView Active (but
            // invisible — see ownIsRuntimeExcluded → desiredActive below), so
            // its CropEngine keeps scanning and emits [ifp-keyword] hit=false
            // the instant the keyword clears, which clears the entry and lets
            // the tab rejoin the rotation on its own. The map is plain-object
            // {idx: timestampMs}; UrlUtils duck-types Set vs object and only
            // tests truthiness.
            const next = UrlUtils.nextCycleTabIndex(
                root.currentTabIndex, root.tabs, root._runtimeExcluded);
            if (next >= 0) root.advanceCycleTab(next);
        }
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
        const idx = root.currentTabIndex;
        const profile = tab.profile;
        if (!profile) { root._tabReloadRequested(idx, "soft"); return; }
        let fired = false;
        function onCompleted() {
            if (fired) return;
            fired = true;
            try { profile.clearHttpCacheCompleted.disconnect(onCompleted); } catch (e) { /* profile gone */ }
            console.info("iframe-plasma: HTTP cache cleared, reloading");
            // Soft reload BOTH the popup tab and its matching panel-slot
            // thumbnail. Cache is profile-scoped so both observe the wipe.
            root._tabReloadRequested(idx, "soft");
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
        root._currentTabIsAutoCycle = false;
        Plasmoid.configuration.currentTabIndex = idx;
    }

    // Auto-cycle advances the runtime index only — it must NOT persist.
    // Routing the cycle through setCurrentTab would rewrite the on-disk
    // appletsrc every autoCycleIntervalSec for the whole session (a disk
    // write every 5–30 s, forever). The next *user* tab switch still
    // persists via setCurrentTab, so session restore keeps working.
    function advanceCycleTab(idx) {
        root.currentTabIndex = idx;
        root._currentTabIsAutoCycle = true;
    }

    // True when the current tab was reached by the auto-cycle stepper,
    // false when the user selected it explicitly (popup tab click, Ctrl+Tab,
    // Ctrl+1..9) or it was restored from config on load. Gates whether a
    // runtime keyword exclusion HIDES the compact preview: keyword exclusion
    // exists to skip a tab during rotation, so blanking a tab the user
    // deliberately opened to a placeholder icon gives no benefit — the user
    // wants to see exactly what they selected. Defaults false so the
    // config-restored tab on first load is treated as a user choice.
    property bool _currentTabIsAutoCycle: false

    // Active WebTab reference. Set from inside fullRepresentation's
    // Component.onCompleted (the Repeater's id is scoped to that Component
    // and not reachable from this document scope otherwise).
    // Bound expression — re-evaluates on currentTabIndex or repeater.count change.
    property var activeTab: null

    // --- Keyboard shortcuts (scoped to popup-open so panel use isn't grabby) ---
    // Ctrl+R is the browser muscle-memory chord; StandardKey.Refresh is F5
    // on Linux/KDE (the platform-conventional reload key). Both bound here
    // so either works.
    Shortcut {
        sequences: ["Ctrl+R", StandardKey.Refresh]
        enabled: root.expanded
        onActivated: root._tabReloadRequested(root.currentTabIndex, "soft")
    }
    Shortcut {
        sequence: "Ctrl+Shift+R"
        enabled: root.expanded
        onActivated: root._tabReloadRequested(root.currentTabIndex, "hard")
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

        // Thumbnail tab source: follow the popup's currentTabIndex,
        // skipping tabs the user marked thumbMode=excluded on the URLs tab.
        // QML's binding system handles auto-follow automatically:
        // currentTabIndex change → previewTabIdx re-evaluates → previewTab
        // → miniView.url → WebEngineView reloads.
        //
        // Returns -1 when there is no eligible tab to show (no tabs at all,
        // current tab is excluded, or out-of-range). The render path falls
        // back to the plasmoid icon in that case.
        readonly property int previewTabIdx: {
            // In-place metadata writes mutate t.thumbMode without firing
            // NOTIFY on root.tabs (the array reference is unchanged),
            // so depend on the serial to re-evaluate after a metadata
            // Apply switches a tab to thumbMode="excluded".
            const _tick = root._tabsMetadataSerial;
            // Also re-evaluate when a runtime keyword exclusion is recorded
            // or cleared for the current tab. Without this the slot keeps
            // painting excluded content the moment its keyword matches, and
            // if every other tab is excluded too nextCycleTabIndex returns -1,
            // so the cycle never advances off it and the excluded tab stays
            // pinned on screen for the rest of the session.
            const _exclTick = root._runtimeExclusionSerial;
            if (root.tabs.length === 0) return -1;
            const idx = root.currentTabIndex;
            if (idx < 0 || idx >= root.tabs.length) return -1;
            const t = root.tabs[idx];
            if (!t || t.thumbMode === "excluded") return -1;
            // Runtime keyword exclusion only hides the preview while the
            // auto-cycle put us on this tab. When the user explicitly
            // selected it (popup click / Ctrl+Tab / restored on load) show
            // the live content regardless of a keyword match — they asked to
            // see this tab, and a placeholder icon helps no one. The cycle
            // stepper still skips the tab independently via nextCycleTabIndex.
            if (root._currentTabIsAutoCycle && root._runtimeExcluded[idx]) return -1;
            return idx;
        }
        readonly property var previewTab: previewTabIdx >= 0 ? root.tabs[previewTabIdx] : null

        // Primitive-typed shadow of previewTab.label. QML6's `property var`
        // change detection on `array[index]` is lossy when only the index
        // changes — the binding can keep returning a stale-but-equal-typed
        // reference, leaving consumers (thumbLabel below, plus any future
        // var-chain reads) painting yesterday's label. A `string` property
        // has proper NOTIFY semantics, so this re-evaluates reliably on
        // every previewTabIdx / root.tabs change. Same reason
        // toolTipMainText (L102-106) reads root.tabs[currentTabIndex].label
        // imperatively into a string, rather than via the var indirection.
        readonly property string previewTabLabel: {
            // Depend on the serial so an in-place metadata Apply (label
            // rename, show-label toggle) re-evaluates this binding. Without
            // the const-assigned read, mutating t.label / t.thumbShowLabel
            // in place leaves the overlay painting the pre-Apply value.
            const _tick = root._tabsMetadataSerial;
            if (previewTabIdx < 0) return "";
            const t = root.tabs[previewTabIdx];
            if (!t) return "";
            // Per-URL opt-IN for the label overlay. Folding this into
            // previewTabLabel (rather than gating visible in thumbLabel)
            // keeps the visibility chain on a single primitive-typed
            // property — same reason as the parent comment for
            // primitive-vs-var change propagation.
            if (t.thumbShowLabel !== true) return "";
            return t.label || "";
        }

        // Whether the slot has any live-rendering work to show. Used by the
        // fallback icon's visibility predicate. Replaces the older
        // miniActive / previewLive / *ThumbWanted properties — per-tab
        // gating now happens inside each StackLayout delegate.
        readonly property bool slotShowsContent: previewTabIdx >= 0
                                              && Plasmoid.configuration.compactPreviewEnabled

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

        // --- Per-tab render stack ------------------------------------------
        // One delegate per configured tab, picked by StackLayout.currentIndex
        // = compact.previewTabIdx. Each delegate carries its own renderer
        // (WebEngineView for live modes, Rectangle for text, Kirigami.Icon
        // for icon, empty Item for excluded) and its own WebViewLifecycle
        // so freeze/discard delays now apply per-thumb — switching tabs in
        // the popup reveals an already-rendered thumbnail instead of a
        // navigation-reload spinner. Mirrors the popup's WebTab Repeater
        // pattern (`fullRepresentation` further down) verbatim.
        //
        // Hidden entirely (→ fallback icon takes the slot) when:
        //   • compactPreviewEnabled is off,
        //   • previewTabIdx is -1 (no tabs, or current tab is "excluded").
        StackLayout {
            id: thumbStack
            anchors.fill: parent
            z: 0
            visible: compact.slotShowsContent
            currentIndex: Math.max(0, compact.previewTabIdx)

            Repeater {
                model: root.tabs
                delegate: Item {
                    id: thumbSlot
                    required property int index
                    required property var modelData

                    // Cache the mode + per-tab predicates so the per-delegate
                    // Loader, lifecycle, and visibility bindings stay readable.
                    // Depend on the metadata serial — in-place Apply mutates
                    // modelData.thumbMode without firing NOTIFY on the var,
                    // so without this read a mode swap (e.g. custom → text)
                    // would leave wantLive cached at the old value.
                    readonly property string slotMode: {
                        // Read through root._liveRow — `modelData.thumbMode`
                        // is a Repeater snapshot that does NOT see in-place
                        // mutations from KCM Apply / picker save. See the
                        // _liveRow docblock.
                        const _tick = root._tabsMetadataSerial;
                        const t = root._liveRow(thumbSlot.index, thumbSlot.modelData);
                        return (t && t.thumbMode) || "chartOnly";
                    }
                    readonly property bool isCurrent: thumbSlot.index === compact.previewTabIdx
                                                   && compact.previewTabIdx >= 0
                    readonly property bool wantLive: Plasmoid.configuration.compactPreviewEnabled
                                                  && slotMode !== "text"
                                                  && slotMode !== "icon"
                                                  && slotMode !== "excluded"

                    // --- Live web preview (per tab) -----------------------
                    // Loader-gated so excluded / text / icon tabs pay zero
                    // Chromium-renderer cost. When `active` flips false the
                    // WebEngineView is destroyed; flipping it true re-loads
                    // from scratch (matches today's URL-change reload, just
                    // localized to one tab). slotMode → wantLive picks up
                    // metadata-Apply mode flips via the `void
                    // root._tabsMetadataSerial` dependency on slotMode, so
                    // the old `_forceLive` picker-save override is gone.
                    Loader {
                        id: webLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                        width: compact.internalWidth
                        height: compact.internalHeight
                        active: thumbSlot.wantLive
                        sourceComponent: webThumbComp

                        // Per-instance data plumbed via Loader properties —
                        // Components are templates with no constructor args,
                        // so the loaded item reads its own context via
                        // `parent.<prop>` (parent of the loaded item is this
                        // Loader).
                        property var ownTab: thumbSlot.modelData
                        property int ownIndex: thumbSlot.index
                        property bool ownIsCurrent: thumbSlot.isCurrent
                    }

                    // --- Text mode ----------------------------------------
                    Rectangle {
                        anchors.fill: parent
                        visible: thumbSlot.slotMode === "text"
                                 && Plasmoid.configuration.compactPreviewEnabled
                        color: Kirigami.Theme.backgroundColor
                        QQC.Label {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            text: {
                                // Read through root._liveRow — `modelData`
                                // is a Repeater snapshot. See _liveRow
                                // docblock.
                                const _tick = root._tabsMetadataSerial;
                                const t = root._liveRow(thumbSlot.index, thumbSlot.modelData);
                                if (!t) return "";
                                const explicit = t.thumbText || "";
                                return explicit.length > 0 ? explicit : (t.label || "");
                            }
                            // Pin the renderer — thumbText and label both
                            // flow from imported JSON without HTML strip;
                            // AutoText would auto-promote `<img src=…>` to
                            // StyledText and beacon via the QQmlEngine NAM
                            // (same SSRF class as 5388f75, but worse here
                            // because the panel-slot is always visible).
                            textFormat: Text.PlainText
                            color: Kirigami.Theme.textColor
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            font.pixelSize: Math.max(8, Math.min(48,
                                Math.round(Math.min(parent.width, parent.height) * 0.32)))
                            font.family: Theme.fontHeader
                        }
                    }

                    // --- Icon mode ----------------------------------------
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - Kirigami.Units.smallSpacing
                        height: width
                        visible: thumbSlot.slotMode === "icon"
                                 && Plasmoid.configuration.compactPreviewEnabled
                        // isMask only for bundled SVGs — theme icons and
                        // user-picked file:// paths render full-color.
                        // Both isMask and source depend on the metadata
                        // serial so a thumbIconName swap mid-pinned-popup
                        // re-resolves the icon source.
                        isMask: {
                            // Read through root._liveRow — modelData is a
                            // Repeater snapshot. See _liveRow docblock.
                            const _tick = root._tabsMetadataSerial;
                            const t = root._liveRow(thumbSlot.index, thumbSlot.modelData);
                            const n = String(t ? t.thumbIconName : "");
                            return n.startsWith("bundled:");
                        }
                        color: Kirigami.Theme.textColor
                        source: {
                            const _tick = root._tabsMetadataSerial;
                            const t = root._liveRow(thumbSlot.index, thumbSlot.modelData);
                            return root.resolveIconSource(t ? t.thumbIconName : "");
                        }
                    }

                    // `excluded` mode: leave the delegate blank. The
                    // currentIndex pointer never lands here (previewTabIdx
                    // returns -1 for the excluded case, the StackLayout
                    // itself goes invisible, fallback icon takes over).
                }
            }
        }

        // Per-tab live-preview WebEngineView. Replicated once per Repeater
        // delegate, with per-instance config sourced from the parent Loader's
        // ownTab / ownIndex / ownIsCurrent properties. Behaviour pinning
        // (settings, permission/dialog rejects, console-log capture, crop-
        // engine apply, reflow timer, lifecycle) mirrors the old miniView
        // verbatim; the only changes are (a) source the active tab from
        // the Loader instead of compact.previewTab, and (b) self-filter the
        // _tabsMetadataChanged signal by ownIndex.
        Component {
            id: webThumbComp

            WebEngineView {
                id: miniView
                anchors.fill: parent

                readonly property var ownTab: parent.ownTab
                readonly property int ownIndex: parent.ownIndex
                readonly property bool ownIsCurrent: parent.ownIsCurrent
                // True while THIS tab holds a live keyword exclusion. Keeps the
                // view Active (but invisible — it is not the StackLayout's
                // current child) so CropEngine keeps scanning and emits
                // [ifp-keyword] hit=false the moment the keyword clears,
                // self-clearing the exclusion. Without this an excluded tab
                // would freeze and could never report the keyword going away.
                // Depends on the serial because _runtimeExcluded mutates in
                // place and fires no NOTIFY (mirrors previewTabIdx).
                readonly property bool ownIsRuntimeExcluded: {
                    const _exclTick = root._runtimeExclusionSerial;
                    return !!root._runtimeExcluded[miniView.ownIndex];
                }
                // Read through root._liveRow(ownIndex, ownTab) rather than
                // the ownTab chain — ownTab → parent.ownTab →
                // thumbSlot.modelData, and modelData is a Repeater snapshot
                // in Qt 6.10 that does NOT see in-place mutations from KCM
                // Apply / picker save. The serial bump triggers re-eval but
                // would otherwise still pick up the stale snapshot.
                //
                // Stays a declarative binding (no imperative writes
                // anywhere) so subsequent serial bumps continue to fire —
                // see Qt6 "Property Binding" docs: ANY imperative write
                // permanently destroys the binding (only Qt.binding()
                // re-arms it). The const-assigned form is also load-bearing
                // on Qt 6.10: the V4 JIT drops a bare `void` statement as
                // dead code and loses the dep-capture (see the docblock on
                // `_tabsMetadataSerial`).
                property string ownSelector: {
                    const _tick = root._tabsMetadataSerial;
                    const t = root._liveRow(miniView.ownIndex, ownTab);
                    return root.thumbSelectorFor(t);
                }

                // Set true when a hard-reload arrives while the view is
                // Discarded; consumed by onLoadingChanged on the next
                // LoadStartedStatus, which stops the engine's automatic
                // cache-honoring reload from Discarded->Active and
                // re-issues it as ReloadAndBypassCache. Without this
                // hand-off the bypass-cache intent races the auto-reload
                // on Chromium's IO thread and is typically lost.
                property bool _pendingHardReload: false

                // Per-delegate auto-follow override. Defaults to "" (use
                // tab's static thumbTimeRange / URL-own range). The
                // Connections handler below bumps this when the user picks
                // a new time range in the popup toolbar AND this delegate
                // is the popup's currently-active tab. On tab switches /
                // auto-rotate, the override stays put → URL stays put →
                // no reload.
                property string sessionRangeOverride: ""
                // Suppress propagation of activeTabSessionRange events that
                // are side effects of a tab switch (vs. a real user pick).
                // A tab switch fires onCurrentTabIndexChanged synchronously
                // and may or may not fire onActiveTabSessionRangeChanged
                // depending on whether the two tabs' ranges differ — the
                // previous approach tracked _lastSeenActiveIndex inside the
                // range handler and broke for the dominant case where every
                // tab defaults to the same range (e.g. now-24h): no range
                // event fires on switch, the index marker doesn't update,
                // and the next legitimate range pick is then misclassified
                // as a tab switch and silently dropped. Set on tab change,
                // clear on the next event-loop tick — short enough that a
                // genuine pick a beat later still propagates.
                property bool _suppressRangePropagation: false

                profile: root.profileForAuthId(ownTab ? ownTab.authProfileId : "")
                url: root.resolveThumbUrlWith(ownTab, sessionRangeOverride)

                Connections {
                    target: root
                    function onCurrentTabIndexChanged() {
                        miniView._suppressRangePropagation = true;
                        Qt.callLater(function() {
                            miniView._suppressRangePropagation = false;
                        });
                    }
                    function onActiveTabSessionRangeChanged() {
                        if (miniView._suppressRangePropagation) {
                            return;
                        }
                        const newRange = root.activeTabSessionRange;
                        const currentIdx = root.currentTabIndex;
                        // Propagate ONLY if THIS delegate is the popup's
                        // active tab AND its tab opted into auto-follow
                        // ("" or "auto" thumbTimeRange).
                        if (miniView.ownIndex !== currentIdx) return;
                        // Read through root._liveRow — ownTab is a Repeater
                        // snapshot; thumbTimeRange may have been mutated by
                        // KCM Apply since this delegate was created.
                        const t = root._liveRow(miniView.ownIndex, miniView.ownTab);
                        if (!t || (t.thumbTimeRange || "auto") !== "auto") return;
                        // 'custom' is the sentinel WebTab.currentTimeRange
                        // returns when the popup URL's from/to don't match
                        // now-Nu/now (user picked absolute timestamps in
                        // Grafana). resolveThumbUrlWith's regex validator
                        // would reject it and log a spurious "rejected
                        // invalid thumbTimeRange" warning. Skip silently;
                        // thumb keeps its configured range.
                        if (newRange === "custom") return;
                        console.info("iframe-plasma[mini-range] idx=" + miniView.ownIndex
                            + " applying override=" + JSON.stringify(newRange));
                        miniView.sessionRangeOverride = newRange;
                    }
                }

                settings.javascriptEnabled: true
                settings.showScrollBars: false
                settings.localStorageEnabled: true
                settings.pluginsEnabled: false
                settings.javascriptCanPaste: false
                settings.localContentCanAccessFileUrls: false
                settings.localContentCanAccessRemoteUrls: false
                settings.javascriptCanOpenWindows: false
                settings.javascriptCanAccessClipboard: false
                settings.allowRunningInsecureContent: false
                settings.pdfViewerEnabled: false
                settings.webRTCPublicInterfacesOnly: true
                backgroundColor: "transparent"
                zoomFactor: 1.0
                enabled: false
                smooth: true

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
                onAuthenticationDialogRequested: function(request) {
                    console.warn("iframe-plasma[mini-auth] rejected dialog type=" + request.type
                        + " url=" + request.url);
                    request.dialogReject();
                    request.accepted = true;
                }
                // Bounded one-shot reload on renderer crash, mirroring the
                // popup WebTab handler. Without this a Chromium renderer
                // termination in a thumbnail (OOM under memory pressure,
                // GPU-process loss, hostile content force-crashing its own
                // renderer) leaves the mini-view permanently blank until the
                // user re-edits the tab URL or restarts plasmashell. Cap at
                // one retry per session so a crash-loop can't hammer
                // plasmashell into the ground.
                property bool _miniRenderRetried: false
                onRenderProcessTerminated: function(status, exitCode) {
                    console.warn("iframe-plasma[mini-render] terminated status=" + status
                        + " exitCode=" + exitCode + " idx=" + miniView.ownIndex
                        + " retried=" + miniView._miniRenderRetried);
                    if (status !== WebEngineView.NormalTerminationStatus
                        && !miniView._miniRenderRetried) {
                        miniView._miniRenderRetried = true;
                        miniView.reload();
                    }
                }

                transform: Scale {
                    origin.x: 0; origin.y: 0
                    xScale: compact.renderScale
                    yScale: compact.renderScale
                }

                onLoadingChanged: function(info) {
                    console.info("iframe-plasma[mini] loadingChanged status=" + info.status
                        + " idx=" + miniView.ownIndex
                        + " url=" + info.url
                        + " thumbSelector=" + JSON.stringify(miniView.ownSelector));
                    if (info.status === WebEngineView.LoadStartedStatus
                        && miniView._pendingHardReload)
                    {
                        miniView._pendingHardReload = false;
                        hardReloadFallback.stop();
                        console.info("iframe-plasma[compact] tab-reload hard (post-discard) idx=" + miniView.ownIndex);
                        miniView.stop();
                        miniView.triggerWebAction(WebEngineView.ReloadAndBypassCache);
                        return;
                    }
                    if (info.status === WebEngineView.LoadSucceededStatus) {
                        // Each fresh successful load grants a new
                        // renderer-crash retry budget; mirror of WebTab's
                        // _renderRetried reset. Without this the one-shot
                        // latch above stays armed for the popup lifetime
                        // and a second crash hours later leaves the
                        // thumbnail permanently blank.
                        miniView._miniRenderRetried = false;
                        if (miniView.ownSelector.length > 0) {
                            applyThumbCrop(miniView.ownSelector);
                        } else {
                            // Symmetric clear — mirror the WebTab popup's
                            // applyImmediately(clear). Defensive: a reload
                            // (Ctrl+R, _tabReloadRequested, soft-reload from
                            // mode flip) followed by an empty selector
                            // shouldn't leave any stale CropEngine state
                            // lingering on the page. The state is gone after
                            // navigation in the common case, but this keeps
                            // the post-reload page state hermetically in sync
                            // with the current `ownSelector` and matches the
                            // popup path's symmetry.
                            miniView.runJavaScript(CropEngine.buildClearJs(), function(r) {
                                console.info("iframe-plasma[compact] load-succeeded clear idx="
                                    + miniView.ownIndex + " = " + r);
                            });
                        }
                    }
                }

                // Fallback for the "Discarded->Active promotion does NOT
                // emit LoadStartedStatus" case (Qt BFCache restore, or
                // rare paths where lifecycleState=Active reuses a cached
                // snapshot without re-loading). Without this, the
                // _pendingHardReload flag would stay armed indefinitely
                // and the next URL-driven LoadStartedStatus (e.g. user
                // picks a new time range → sessionRangeOverride updates
                // → url binding re-evaluates) would consume the stale
                // arming, calling stop() + bypass-cache on the brand-new
                // navigation and racing it on Chromium's IO thread.
                Timer {
                    id: hardReloadFallback
                    interval: 1500
                    repeat: false
                    onTriggered: {
                        if (!miniView._pendingHardReload) return;
                        miniView._pendingHardReload = false;
                        console.info("iframe-plasma[compact] hard-reload fallback (no LoadStarted) idx="
                            + miniView.ownIndex);
                        miniView.stop();
                        miniView.triggerWebAction(WebEngineView.ReloadAndBypassCache);
                    }
                }

                onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID) {
                    if (!message) return;
                    const safe = String(message).replace(/[\x00-\x1f\x7f]/g, '?').slice(0, 512);
                    if (safe.indexOf('[ifp-thumb]') !== -1) {
                        console.info("iframe-plasma" + safe);
                        return;
                    }
                    // CropEngine emits '[ifp-keyword] hit=true|false' on
                    // every exclusion-state transition. Forward into the
                    // root.setRuntimeExcluded map so the next cycleTimer
                    // tick can skip this tab. The receiver dedupes by
                    // current value, so duplicate emits (re-apply after
                    // reload) are free.
                    const kw = safe.indexOf('[ifp-keyword]');
                    if (kw !== -1) {
                        const hit = safe.indexOf('hit=true', kw) !== -1;
                        root.setRuntimeExcluded(miniView.ownIndex, hit);
                    }
                }

                function applyThumbCrop(selector) {
                    // Read through root._liveRow — `miniView.ownTab` is a
                    // Repeater snapshot; thumbMode / thumbScaleMode /
                    // thumbExcludeKeywords may have been mutated by KCM
                    // Apply or picker save since this delegate was created.
                    const tab = root._liveRow(miniView.ownIndex, miniView.ownTab);
                    // Scale mode applies ONLY to the user-controlled
                    // custom-selector path. Grafana presets
                    // (chartOnly canvas-blit / chartWithAxes .u-wrap)
                    // and fullPanel are designed around the legacy
                    // stretch semantics — overriding them with `fit`
                    // would force uPlot to redraw at a smaller content
                    // size and then visually upscale, producing blurry
                    // axis text. Force stretch for non-custom modes.
                    const mode = (tab && tab.thumbMode) || "chartOnly";
                    const userScale = (tab && tab.thumbScaleMode) || "fit";
                    const opts = {
                        scaleMode: mode === "custom" ? userScale : "stretch",
                        keywords: (tab && tab.thumbExcludeKeywords) || []
                    };
                    console.info("iframe-plasma[thumb] applyThumbCrop ENTRY selector=" + JSON.stringify(selector)
                        + " idx=" + miniView.ownIndex
                        + " scale=" + opts.scaleMode
                        + " kwCount=" + opts.keywords.length
                        + " loading=" + miniView.loading + " url=" + miniView.url);
                    runJavaScript(CropEngine.buildApplyJs(selector, opts), function(r) {
                        console.info("iframe-plasma[thumb] applyThumbCrop("
                            + JSON.stringify(selector) + ") = " + r);
                    });
                }

                onWidthChanged:  miniViewReflowTimer.restart()
                onHeightChanged: miniViewReflowTimer.restart()
                Timer {
                    id: miniViewReflowTimer
                    interval: 200
                    onTriggered: {
                        if (miniView.ownSelector.length > 0) {
                            miniView.runJavaScript("window.dispatchEvent(new Event('resize'));");
                        }
                    }
                }

                Connections {
                    target: root
                    // Broadcast reload from the popup toolbar / shortcuts /
                    // cache-clear. Fire on the matching thumbnail too so a
                    // single Ctrl+R refreshes both the popup tab AND its
                    // panel-slot view.
                    function on_TabReloadRequested(tabIdx, kind) {
                        if (tabIdx !== miniView.ownIndex) return;
                        // Discarded views have no live renderer; promoting
                        // lifecycleState to Active triggers WebEngine's
                        // automatic (cache-honoring) reload. For soft that
                        // is the right behavior. For hard we arm
                        // _pendingHardReload; onLoadingChanged then aborts
                        // the auto-reload and re-issues ReloadAndBypassCache
                        // once the renderer is up — calling triggerWebAction
                        // synchronously here would race the auto-reload on
                        // Chromium's IO thread and lose the bypass intent.
                        const isDiscarded = miniView.lifecycleState === WebEngineView.LifecycleState.Discarded;
                        if (isDiscarded) {
                            if (kind === "hard") {
                                miniView._pendingHardReload = true;
                                hardReloadFallback.restart();
                            }
                            miniView.lifecycleState = WebEngineView.LifecycleState.Active;
                            return;
                        }
                        if (kind === "hard") {
                            console.info("iframe-plasma[compact] tab-reload hard idx=" + tabIdx);
                            miniView.triggerWebAction(WebEngineView.ReloadAndBypassCache);
                        } else {
                            console.info("iframe-plasma[compact] tab-reload soft idx=" + tabIdx);
                            miniView.reload();
                        }
                    }

                    // Broadcast reload from secretsChanged / KConfig
                    // serial bumps. The popup StackLayout already handles
                    // this via webStack.reloadAll(); the compact thumbnail
                    // for the same tab was previously left displaying the
                    // stale 401/Authelia render until the next nav.
                    function onReloadAllRequested() {
                        on_TabReloadRequested(miniView.ownIndex, "soft");
                    }

                    // Post-auth refresh targeted at the compact view only
                    // (the popup tab that authenticated is already current).
                    function on_CompactReloadRequested(tabIdx) {
                        on_TabReloadRequested(tabIdx, "soft");
                    }

                    // In-place metadata Apply (both KCM Apply path and
                    // picker save) mutated root.tabs[i] fields and bumped
                    // the metadata serial. miniView.ownSelector is a
                    // declarative binding with `const _tick =
                    // root._tabsMetadataSerial;` dependency — so by the time
                    // this handler runs, the binding has ALREADY re-evaluated
                    // to the fresh value.
                    // Just read and dispatch: apply on non-empty, clear on
                    // empty. No imperative property write (would sever the
                    // binding and break every subsequent metadata Apply).
                    // idx === -1 means "all tabs" — filter to ours.
                    function on_TabsMetadataChanged(idx) {
                        if (idx !== -1 && idx !== miniView.ownIndex) return;
                        const sel = miniView.ownSelector;
                        if (sel.length > 0) {
                            console.info("iframe-plasma[compact] metadata apply idx=" + miniView.ownIndex
                                + " selector=" + JSON.stringify(sel));
                            miniView.applyThumbCrop(sel);
                        } else {
                            // Selector cleared (e.g. user switched mode
                            // to fullPanel/text/icon). Tear down CropEngine
                            // state so the page reverts to its full layout.
                            console.info("iframe-plasma[compact] metadata apply clear idx=" + miniView.ownIndex);
                            miniView.runJavaScript(CropEngine.buildClearJs(), function(r) {
                                console.info("iframe-plasma[compact] metadata clear = " + r);
                            });
                        }
                    }
                }

                // Per-thumb lifecycle. desiredActive is true for the tab the
                // user is currently previewing (popup or auto-cycle selection),
                // AND for any tab holding a live keyword exclusion (so it keeps
                // monitoring for the keyword clearing — see ownIsRuntimeExcluded),
                // AND only while the slot is observable. Other non-current thumbs
                // freeze after freezeDelaySec → discard after discardDelaySec.
                // Switching back reveals the existing renderer instantly (no
                // spinner flash) when within stalenessSec, or reloads on resume.
                WebViewLifecycle {
                    target: miniView
                    desiredActive: (miniView.ownIsCurrent || miniView.ownIsRuntimeExcluded)
                                   && root.compactObservable
                    freezeDelaySec: Plasmoid.configuration.webViewFreezeDelaySec
                    discardDelaySec: Plasmoid.configuration.webViewDiscardDelaySec
                    stalenessSec: Math.max(5, Plasmoid.configuration.autoCycleIntervalSec)
                }
            }
        }

        // --- Icon fallback --------------------------------------------------
        // Standard plasmoid icon when the StackLayout has nothing to show:
        // compactPreviewEnabled off, no tabs configured, or the popup's
        // currently-active tab is `excluded`. The text/icon thumbnail modes
        // are rendered INSIDE the StackLayout's delegates, so they do not
        // gate this fallback — only the slot-has-no-content case does.
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) - Kirigami.Units.smallSpacing
            height: width
            visible: !compact.slotShowsContent
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
            // Bind to the primitive previewTabLabel string. Reading via
            // `compact.previewTab.label` (a `var` indirection through an
            // array element) misses the NOTIFY when only currentTabIndex
            // changes, so the label paints yesterday's tab after an
            // auto-cycle skip. See the previewTabLabel comment above.
            visible: compact.previewTabLabel.length > 0
            z: 2

            QQC.Label {
                id: thumbLabelText
                anchors {
                    fill: parent
                    leftMargin: thumbLabel.horizontalPadding
                    rightMargin: thumbLabel.horizontalPadding
                }
                text: compact.previewTabLabel
                // Pin PlainText: the label comes from imported JSON with no
                // HTML strip (RowSchema.normalize passes it through), and
                // AutoText would let `<img src=…>` beacon via the NAM.
                textFormat: Text.PlainText
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

        // Cancel any active picker across all WebTab delegates. Called
        // from root.onExpandedChanged when the popup is collapsing —
        // otherwise pickerTimer keeps polling __ifpPicked for up to 2
        // minutes after the popup is gone, and a successful pick lands
        // in handlePickedSelector with fullRepresentationItem==null
        // (the popup auto-close tore it down) → the selector is silently
        // dropped with only a warn log. Cancelling here releases the
        // page-side listeners cleanly so the next popup-open starts
        // from a clean state.
        function cancelAllPickers() {
            for (let i = 0; i < repeater.count; ++i) {
                const wt = repeater.itemAt(i);
                if (wt && wt.pickerActive && typeof wt.cancelPicker === "function") {
                    console.info("iframe-plasma[picker] auto-cancel on popup hide idx=" + i);
                    wt.cancelPicker();
                }
            }
        }

        // Bridge for root.savePickedSelector — it can't reach the
        // Repeater's `id: repeater` directly because QML Components
        // are ID-isolated (a lazy fullRepresentation Component owns a
        // separate ID namespace from root). The previous direct
        // `repeater.itemAt(tabIdx)` from root scope threw
        // `ReferenceError: repeater is not defined`, the try/catch
        // swallowed it, and every picker save silently no-op'd
        // (urlsJson never even got written). This helper lives in
        // Force-apply helper. savePickedSelector NO LONGER calls this —
        // the binding-driven path (serial bump → popupSelector binding
        // re-evaluates → onPopupSelectorChanged → _applyPopupSelector)
        // does it on its own. Kept solely for explicit re-apply needs
        // (currently unused; harmless to leave in case a future caller
        // wants a force without going through urlsJson). NEVER writes
        // wt.popupSelector — that would sever its binding and break
        // every subsequent metadata-Apply for this tab. Same severance
        // rule applies to restorePopupSelectorAt below.
        function applyPopupSelectorAt(tabIdx, sel) {
            const wt = repeater.itemAt(tabIdx);
            if (wt && typeof wt.applyImmediately === "function") {
                wt.applyImmediately(sel);
                return true;
            }
            return false;
        }

        // Re-engage the popup's CropEngine isolation for the CURRENT
        // value of root.tabs[tabIdx] — used by the save-picked dialog's
        // Cancel path AND by savePickedSelector's thumb-only branch.
        // _PICKER_START_BODY's teardown stripped data-ifp-* + style node
        // before the dialog opened, so the popup is currently un-cropped;
        // without this restore, dismissal leaves the popup un-isolated
        // until the user reloads or switches tabs. Reads root.tabs[]
        // directly (the live model is the truth) and calls
        // applyImmediately so the page-side state matches. Does NOT
        // touch wt.popupSelector — see severance note in
        // applyPopupSelectorAt above.
        function restorePopupSelectorAt(tabIdx) {
            const wt = repeater.itemAt(tabIdx);
            if (!wt || typeof wt.applyImmediately !== "function") return false;
            const t = root.tabs[tabIdx];
            const sel = (t && t.popupMode === "custom") ? (t.popupSelector || "") : "";
            wt.applyImmediately(sel);
            return true;
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
                // Flipped by every Save action before close(). onClosed
                // uses it to distinguish "user saved" from "user cancelled
                // / Esc / click-outside". The Cancel path needs to re-engage
                // the existing popupSelector because _PICKER_START_BODY's
                // teardown stripped isolation before this dialog opened.
                property bool _saved: false
                function _finishSave(scope) {
                    savePickedDialog._saved = true;
                    root.savePickedSelector(savePickedDialog.tabIdx, scope,
                                            savePickedDialog.pickedSelector);
                    savePickedDialog.close();
                }
                standardButtons: Kirigami.Dialog.NoButton
                customFooterActions: [
                    Kirigami.Action {
                        text: i18n("Save for both")
                        icon.name: "edit-copy"
                        onTriggered: savePickedDialog._finishSave("both")
                    },
                    Kirigami.Action {
                        text: i18n("Save as Thumbnail")
                        icon.name: "view-preview"
                        onTriggered: savePickedDialog._finishSave("thumb")
                    },
                    Kirigami.Action {
                        text: i18n("Save as Widget popup")
                        icon.name: "view-fullscreen"
                        onTriggered: savePickedDialog._finishSave("popup")
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
                // re-applying the OLD value. Cancel path: the picker's
                // _PICKER_START_BODY teardown stripped isolation BEFORE
                // this dialog opened, so the popup is currently showing
                // the uncropped page. Re-engage the WebTab's existing
                // popupSelector so dismissal doesn't leave the popup
                // visually broken until manual reload.
                onClosed: {
                    if (!_saved) {
                        restorePopupSelectorAt(tabIdx);
                    }
                    destroy();
                }
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
            fullRepVisible:  root.fullRepVisible
            host:            root.activeTab ? root.activeTab.currentHost           : ""
            tlsOk:           root.activeTab ? root.activeTab.tlsOk                 : false
            httpStatus:      root.activeTab ? root.activeTab.httpStatus            : 0
            latencyMs:       root.activeTab ? root.activeTab.latencyMs             : 0
            loading:         root.activeTab ? root.activeTab.loadStatus === "loading" : false
            timeRange:       root.activeTab ? root.activeTab.currentTimeRange       : ""
            refreshInterval: root.activeTab ? root.activeTab.currentRefreshInterval : ""
            isGrafana:       root.activeTab ? root.isGrafanaEmbed(root.activeTab.webView.url) : false
            pinned:          Plasmoid.configuration.popupPinned
            onPinToggled:    Plasmoid.configuration.popupPinned = !Plasmoid.configuration.popupPinned
            onReloadClicked:        root._tabReloadRequested(root.currentTabIndex, "soft")
            onHardReloadClicked:    root._tabReloadRequested(root.currentTabIndex, "hard")
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
            // Pass through the metadata serial so the strip's per-tab
            // Label re-evaluates `modelData.label` after an in-place Apply.
            metadataSerial: root._tabsMetadataSerial
            fullRepVisible: root.fullRepVisible
            onTabSelected: idx => root.setCurrentTab(idx)
            // Route through the broadcast signal so the panel-slot
            // thumbnail for the same tab also reloads.
            onReloadRequested: idx => root._tabReloadRequested(idx, "soft")
        }

        StackLayout {
            id: webStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTabIndex

            function reloadAll() {
                // Go through the WebTab wrapper (NOT the raw webView) so the
                // Discarded/Frozen-promotion path in WebTab.reload() runs —
                // calling reload() directly on a Discarded WebEngineView is
                // silently dropped by Qt and a background tab on a stale
                // 401/Authelia render would stay stale after a wallet write.
                for (let i = 0; i < repeater.count; i++) {
                    const tab = repeater.itemAt(i);
                    if (tab) tab.reload();
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
                    // Authelia host is per-profile.
                    autheliaHost: {
                        const p = root.profileById(modelData.authProfileId);
                        return (p && p.autheliaHost) || "";
                    }
                    zoomPct: Plasmoid.configuration.zoomFactor
                    // resolveUrl reads only modelData.url, which is a
                    // STRUCTURAL field in our diff classifier — a change
                    // takes the rebuild path, not the in-place path —
                    // so this binding doesn't need _tabsMetadataSerial
                    // dependency. themeMode IS volatile, but
                    // substituteTheme() returns the same string for
                    // URLs without ${theme} and QML elides identical-
                    // value setter calls, so no spurious navigation.
                    url: root.resolveUrl(modelData)
                    // Popup-only CSS-selector crop. fullPanel mode (or empty
                    // selector) → no crop; custom mode passes the user's
                    // selector to CropEngine isolation in WebTab.qml.
                    // Depends on the metadata serial so an in-place Apply
                    // (the common "I picked a new selector via the picker
                    // in the config dialog" case) re-evaluates and fires
                    // onPopupSelectorChanged inside WebTab → applyImmediately
                    // — no full-page reload, just a CropEngine swap.
                    popupSelector: {
                        // Read through root._liveRow — `modelData` is a
                        // Repeater snapshot in Qt 6.10 that does NOT see
                        // in-place mutations from KCM Apply / picker save.
                        // See the _liveRow docblock.
                        const _tick = root._tabsMetadataSerial;
                        const t = root._liveRow(index, modelData);
                        return (t && t.popupMode === "custom")
                               ? (t.popupSelector || "")
                               : "";
                    }
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
                    // The compact-rep miniView at the same index loaded the
                    // URL before the session cookie was set and got parked
                    // on the redirected /login page. WebTab fires this once
                    // per auth-completion (both Authelia and SPA-internal
                    // logins — see WebTab.qml's onLoadingChanged for the
                    // detection gates). Re-route through the existing soft
                    // reload broadcast so the miniView re-fetches with the
                    // now-valid cookies on its own.
                    onAuthSucceeded: root._compactReloadRequested(index)

                    // Broadcast reload from the popup toolbar / shortcuts /
                    // cache-clear. Soft and hard both filter to THIS tab's
                    // index; the matching compact-rep delegate has its own
                    // listener (search webThumbComp for on_TabReloadRequested).
                    Connections {
                        target: root
                        function on_TabReloadRequested(tabIdx, kind) {
                            if (tabIdx !== index) return;
                            if (kind === "hard") hardReload();
                            else                 reload();
                        }
                    }
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
