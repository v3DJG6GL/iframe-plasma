# Changelog

All notable changes to this project will be documented in this file. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.2] — 2026-05-17

### Fixed
- **URLs tab Auth dropdown was always empty.** `ConfigUrls.qml` accessed `Plasmoid.configuration.authProfilesJson` without importing `org.kde.plasma.plasmoid`, throwing a silent ReferenceError that returned `[]`. Replaced with a `cfg_authProfilesJson` mirror property (same pattern used elsewhere for `cfg_urlsJson`) — KCM now keeps the dropdown in sync with the Authentication tab live, including unsaved changes from the same dialog session.
- **Password / token / header fields no longer vanish on tab-away.** Masked dots stay visible after save, and a green "✓ Saved" pill fades in beside the field for ~1.8 s as confirmation. Reopening the dialog still shows an empty field with placeholder `(stored — type to replace)` since secrets are never read back from KWallet.

## [0.4.1] — 2026-05-16

### Added
- **Auto-follow** is now the default thumbnail source: the panel slot automatically mirrors whichever tab is active in the popup. A new "Active popup tab (auto)" item is the first option in Configure → Display → Preview source. Existing fixed-tab selections still work (mode=fixed).
- **URL label overlay**: optional semi-transparent dark bar across the top of the panel-slot thumbnail showing the tab's `label`. Toggle on the Display tab. Hidden when the label is empty or the toggle is off. Font scales with bar height.

### Fixed
- **Preview source dropdown** now actually persists changes. The old `onActivated: store.tabIndex = currentIndex` handler suffered from the same combo-`onActivated` signal-parameter binding-fight that affected `thumbModeCombo` earlier. Switched to the arrow-form pattern `onActivated: idx => …`.

## [0.4.0] — 2026-05-16

### Added
- **Named auth profiles** on the Authentication tab. Define a credential once, then pick it from a dropdown on each URL. Multiple URLs can share a profile — rotating a password is now a one-place edit instead of repeating it per URL.
- **Bearer token** as a first-class auth type. The widget auto-prefixes `Bearer ` — paste a raw JWT without the prefix.
- **Per-profile Authelia host**: different profiles can target different SSO instances. The old global `Authelia host` setting is deprecated (still read once during migration).
- C++ `SecretsBridge::getMap`/`setMap`/`removeKey` for multi-field KWallet entries; `BasicAuthInterceptor::applyProfile`/`clearProfile` for profile-aware host registration.

### Changed (breaking)
- The per-URL `Basic-auth username`, `Password`, and `Raw Authorization header` fields have been REMOVED. They are migrated to named profiles automatically on first load — see Migration below.
- KWallet entries previously stored under `basic:<host>` are now stored under `profile:<uuid>` (multi-field map). The old entries are left in place by the migration but are no longer read.

### Migration
- One-shot at startup: tabs with legacy `basicAuthUser`/`basicAuthPasswordPlaintext`/`rawAuthHeader` are converted to auth profiles. Dedupes by `(host, username, rawHeader)` so tabs sharing credentials collapse into one profile. The global `Authelia host` is copied to each migrated profile.

## [0.3.1] — 2026-05-16

### Added
- **Grafana URL helper** now appends `hideLogo=true` (default-on). Suppresses the "Powered by Grafana" overlay added in Grafana 12.4+ (PR #115198). Silently ignored on older Grafana.
- **Panel-slot CSS selector** field replaced with a **Thumbnail mode** combo: `Chart only` (recommended for Grafana — `.u-wrap > canvas`), `Chart + axes` (`.u-wrap`), `Full panel`, `Custom CSS selector…`. Eliminates the confusing failure mode where users picked `.u-over` / `.u-under` (uPlot's *transparent* overlay layers) and got a blank thumbnail.
- Grafana panel-title and "Powered by" overlay are now hidden in the panel-slot view via stable `data-testid` and class selectors — belt-and-braces with `hideLogo=true`.
- Polling-based shim replaced with a `MutationObserver` (subtree:false, 30 s safety auto-disconnect). Catches React-portal additions (lazy tooltips, late chrome) immediately; lower CPU than the old 100 ms `setInterval`.

### Migration
- Legacy `urlsJson` entries that had a non-empty `thumbSelector` are automatically migrated to `thumbMode: "custom"` on first load. Empty / unset selectors become `chartOnly`.

## [0.3.0] — 2026-05-16

### Added
- **Grafana URL helper** now auto-rewrites `/d/<uid>/...?viewPanel=panel-N` → `/d-solo/<uid>/...?panelId=N` (the canonical Grafana single-panel embed endpoint). Also gains a "Default time range" combo (5m–90d presets). `/goto/<id>` short links pass through with kiosk/theme/refresh/time-range appended; for d-solo conversion paste the resolved `/d/` URL.
- **Time-frame & refresh dropdowns** on the widget toolbar, alongside the tabs. Mutate the active tab's URL params live — session-only override; configured URL is preserved.
- `kiosk` now emitted with no value (Grafana 11.2.x had a regression with `kiosk=1`).
- `refresh=…` is omitted entirely when disabled (Grafana #41329 — empty `refresh=` was buggy).

### Removed (breaking)
- **CSS-selector cropping shim** (`src/compactrendershim.{h,cpp}` + per-tab `widgetSelector` / `compactSelector` fields). The approach was fundamentally fragile: emotion-CSS class hashes drift, Grafana's main-view chain has a `transform` that traps `position: fixed`, axis labels live as siblings (not descendants) of `.u-wrap`, panels resize progressively, and aspect ratios mismatch. Use Grafana's native `/d-solo/...&kiosk` endpoint via the URL helper — the page IS the panel, no DOM hacks needed.
- The `widgetSelector` / `compactSelector` keys in existing `urlsJson` configs are silently dropped on next save. Harmless.

## [0.2.0] — 2026-05-16

### Added
- Theme system (`Theme.qml`): Tokyo Night Storm palette + monospace headers (Hack / IBM Plex Mono).
- `CyberTabBar.qml` replaces stock TabBar — all inactive tab labels readable, accent-glow underline + status dots per tab (loading/ok/err/auth).
- `CyberToolbar.qml`: split reload button with menu (soft / hard / clear cache / open in browser), HTTP status + latency chip, host/TLS chip.
- Keyboard shortcuts: Ctrl+R, Ctrl+Shift+R, Ctrl+W, Ctrl+Tab, Ctrl+1..9.
- Compact representation: live mini-`WebEngineView` for the Plasma panel slot.
- `CornerFrame.qml` (DPI-safe corner accents for future card decoration).

## [0.1.0] — 2026-05-12

### Added
- Initial scaffold: KDE Plasma 6 widget that embeds web content via QtWebEngine.
- Multi-URL tabs with optional auto-cycle.
- Isolated, persistent `WebEngineProfile` per widget (cookies survive plasmashell restarts).
- Authelia redirect detection with click-to-login overlay.
- HTTP Basic Auth via KDE Wallet — passwords stored in folder `iframe-plasma`.
- Pre-emptive `Authorization` header injection via `QWebEngineUrlRequestInterceptor`.
- Grafana share-URL helper that adds `kiosk`, `theme=${theme}`, and `refresh` parameters.
- KDE color-scheme detection — `${theme}` placeholder in URLs resolves automatically.
- Four-tab configuration UI: URLs / Display / Authentication / Advanced.
