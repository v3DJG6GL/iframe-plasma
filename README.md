# iframe-plasma

A KDE Plasma 6 widget that embeds authenticated web pages — primarily designed
for pinning **Grafana panels** onto your desktop or panel — with first-class
support for **Authelia SSO** and **HTTP Basic Auth** behind a reverse proxy.

## Features

- One widget holds **multiple URLs as tabs**, with optional auto-cycle.
- **Persistent isolated `WebEngineProfile`** per widget — Authelia/Grafana
  session cookies survive plasmashell restarts.
- **Authelia redirect detection** with a click-to-login overlay; log in once
  in the embedded view, then the panel stays alive.
- **HTTP Basic Auth** via KDE Wallet — passwords stored in `kwalletmanager6`
  under the `iframe-plasma` folder, never in plaintext config.
- Optional **pre-emptive `Authorization: Basic …` header injection** via a
  `QWebEngineUrlRequestInterceptor` — skips the 401 round-trip.
- **Grafana URL helper** (0.3): paste any `/d/…?viewPanel=panel-N` (or
  `/goto/<id>` short link) — the helper rewrites it to Grafana's
  chrome-less `/d-solo/<uid>/...?panelId=N&kiosk` form and applies your
  preferred default time range / theme / auto-refresh.
- **Live toolbar dropdowns** (0.3): time-frame + refresh-interval selectors
  above the tab bar — override the active tab live, session-only (configured
  URL is preserved).
- **Theme matching**: substitute `${theme}` in any URL — resolves to `light` or
  `dark` from the current KDE color scheme.
- Sane defaults that work as a **panel applet** (compact icon → click expands)
  or a **desktop widget** (inline view).
- **Live panel-inline preview** (0.2): when the widget is on a Plasma panel,
  the slot renders a live mini-view of one configured tab — works best with
  d-solo URLs (the helper sets this up automatically). See
  [Panel preview setup](#panel-preview-setup).
- **Cyberpunk visual design** (0.2): Tokyo Night Storm palette, monospace
  headers, accent-glow active-tab indicator, status dots per tab, HTTP status +
  latency chip, hostname + TLS chip — fully theme-respecting.
- **Refresh toolbar** (0.2): split reload button with menu (soft reload,
  hard reload bypassing cache, clear HTTP cache + reload, open in browser);
  keyboard shortcuts (Ctrl+R / Ctrl+Shift+R / Ctrl+W / Ctrl+Tab / Ctrl+1-9).
- **Load-aware**: web views freeze (JavaScript and auto-refresh suspended)
  when their tab isn't on screen, when the popup is collapsed, or when the
  session is locked — and are discarded after a longer idle to reclaim
  renderer memory. See [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

## Requirements

- KDE Plasma 6.4+ (developed against 6.4.5)
- Qt 6.7+ with QtWebEngine (developed against 6.9.2)
- KDE Frameworks 6 (Wallet, KCMUtils, I18n, CoreAddons, Package)
- For Ubuntu 25.04+: the AppArmor fix that allows `plasmashell` to spawn
  `QtWebEngineProcess` (shipped in `apparmor 4.1.0~beta5-0ubuntu14.1` and
  later — verify with `grep QtWebEngineProcess /etc/apparmor.d/plasmashell`).

## Install

### Build dependencies

```bash
sudo apt install --no-install-recommends \
    cmake extra-cmake-modules gettext \
    libkf6wallet-dev libkf6kcmutils-dev libkf6coreaddons-dev \
    libkf6i18n-dev libkf6package-dev libplasma-dev \
    qt6-webengine-dev qt6-webengine-dev-tools
```

### Per-user build & install

```bash
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=$HOME/.local -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
cmake --install build

# Tell Plasma where to find the C++ QML plugin
echo 'export QML_IMPORT_PATH=$HOME/.local/lib/x86_64-linux-gnu/qt6/qml:$QML_IMPORT_PATH' \
    >> ~/.config/plasma-workspace/env/iframe-plasma.sh
chmod +x ~/.config/plasma-workspace/env/iframe-plasma.sh

# Restart plasmashell so it picks up the env var and the new widget
kquitapp6 plasmashell && kstart plasmashell
```

Right-click the desktop or a panel → **Add Widgets…** → search "iframe Plasma".

### System-wide install (requires root)

```bash
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
sudo cmake --install build
```

No `QML_IMPORT_PATH` tweak needed in this case — `/usr/lib/x86_64-linux-gnu/qt6/qml`
is already in Qt's default search path.

## Configuration

Right-click the widget → **Configure iframe Plasma…**.

### URLs tab

Add one row per URL. Each tab gets:

- **Label** — appears in the tab bar
- **URL** — supports `${theme}` placeholder for Grafana theme matching
- **Auth** — pick a named auth profile (defined on the Authentication tab) or `None (public URL)`. Multiple URLs can share a profile; rotating a password is a one-place edit.
- **Thumbnail** — how the panel-slot mini-view crops this tab:
  - `Chart only` (default) — uPlot's painted canvas. Recommended for Grafana
    TimeSeries panels — the chart fills the slot, no axes / title / legend.
  - `Chart + axes` — `.u-wrap`. Chart plus tick labels.
  - `Full panel` — no cropping. Use for non-TimeSeries panels (Stat, Gauge)
    or when the panel title is part of the information you want.
  - `Custom CSS selector…` — re-exposes a free-text selector for non-Grafana
    sites. **`.u-over` / `.u-under` are transparent uPlot overlay layers and
    will render blank** — use `.u-wrap`, `canvas`, or Grafana's stable test
    selector `[data-testid='data-testid panel content']` instead.

The **From Grafana URL…** button is the easy way to add a panel:

- Paste any Grafana URL — `/d/<uid>/...?viewPanel=panel-N` from the dashboard, or
  the `/goto/<id>` short link from the share dialog.
- With **Single panel** enabled (default), `/d/` is rewritten to `/d-solo/`
  (Grafana's chrome-less single-panel endpoint) and `viewPanel=panel-N` is
  converted to `panelId=N`. Result: the embedded page IS the panel — no
  sidebar, no header, no axis-label clipping.
- **Default time range** lets you override `from`/`to` with a preset
  (5m–90d). Pick `(keep URL's range)` to preserve the URL's own time params.
- **Kiosk** appends `&kiosk` (Grafana strips remaining chrome).
- **Match KDE theme** appends `&theme=${theme}` — the widget substitutes
  `light`/`dark` at render time from your KDE color scheme.
- **Auto-refresh** appends `&refresh=<n>s`.
- **Hide "Powered by Grafana" badge** appends `&hideLogo=true` (Grafana 12.4+,
  silently ignored on older versions — the panel-slot thumbnail CSS catches it
  there regardless).

`/goto/<id>` short links can't be d-solo-rewritten client-side (Grafana would
need to resolve them first). For full conversion paste the resolved
`/d/...?...&viewPanel=panel-N` form. The kiosk/theme/refresh/time-range
overrides do still apply, because Grafana 302-preserves query params across
the goto redirect.

### Display tab

Zoom, theme override (auto / force light / force dark), preferred popup size,
tab-bar visibility, and **Panel preview**:

- **Preview source** — `Active popup tab (auto)` (default) makes the panel
  slot mirror whichever tab is active in the popup. Pick a specific URL to
  pin the thumbnail to that tab regardless of popup state.
- **Preview size** — long-axis pixel size of the panel slot (cross-axis is
  the panel's thickness). Accepts any integer 16–4000.
- **Show URL label** — when on, overlays the tab's `label` field as a
  semi-transparent dark bar across the top of the thumbnail. Hidden for
  tabs that have no label set.

### Live toolbar controls

Above the tab bar, two dropdowns let you override the active tab's
time-range and refresh-interval **for the current session only** — the
configured URL in `urlsJson` is not touched, so reopening the widget restores
the original.

- **Time range**: `5m / 15m / 30m / 1h / 6h / 12h / 24h / 7d / 30d`.
- **Refresh**: `Off / 5s / 30s / 1m / 5m / 30m`.

These rewrite `from=now-<X>&to=now` and `refresh=<X>` on the WebEngineView's
URL and reload.

### Authentication tab

Define named **auth profiles** that URLs can reference. Each profile has:

- **Name** — user-visible label (e.g. `Grafana Production`)
- **Type** — one of:
  - **HTTP Basic** (username + password)
  - **Bearer token** (paste a JWT or similar; the widget prefixes `Bearer ` automatically)
  - **Raw Authorization header** — for cases where Qt's automatic Basic encoding mangles special characters
- **Username** — only used for Basic
- **Password / Token / Header value** — stored in KDE Wallet under folder `iframe-plasma`, key `profile:<uuid>`
- **Authelia host** — when the embedded view is redirected to this host, an "Authentication required" overlay appears. Per-profile so different SSO setups can coexist.

**Inject Authorization header pre-emptively** — toggle on if your reverse proxy requires basic auth on every request (skips the 401 round-trip). When on, profiles are applied via a `QWebEngineUrlRequestInterceptor` that injects `Authorization` headers for matching hosts before they leave the renderer.

Deleting a profile that's still referenced by URLs warns you and unlinks the URLs (they fall back to "None").

### Advanced tab

User-Agent override; remote DevTools port (for debugging embedded pages — set
port then run plasmashell with `QTWEBENGINE_REMOTE_DEBUGGING=<port> kstart
plasmashell`); and the **freeze / discard delays** that control how soon a tab
you are not looking at has its JavaScript suspended and, later, its renderer
process shut down. See [docs/PERFORMANCE.md](docs/PERFORMANCE.md) for tuning
guidance, including the `--process-per-site` flag for multi-tab setups.

## Grafana server-side setup

Add to `grafana.ini`:

```ini
[security]
allow_embedding = true       ; removes X-Frame-Options: deny
cookie_samesite = lax        ; or "none" if Grafana and the widget are on different sites
cookie_secure   = true       ; required when samesite=none
```

For embed URLs, prefer `/d-solo/<uid>/<slug>?panelId=<n>&kiosk&theme=${theme}&refresh=30s`
(single panel) over `/d/<uid>/<slug>?kiosk=1` (full dashboard).

## Panel preview setup

When the widget lives on a Plasma panel, the panel slot renders a **live
mini-view** of one configured tab. There is no CSS-selector cropping — the
mini-view just loads the configured URL at the panel-slot size. For Grafana
that means **the URL should be a `/d-solo/...` one** (created automatically
when you use the *From Grafana URL…* helper with **Single panel** enabled).

To turn it on:

1. Add your panel URL via the helper (or paste a d-solo URL directly).
2. *Configure → Display* → check **Panel preview** and pick the source tab
   in the **Preview source** combo.
3. Drag the widget onto a Plasma panel.

### Caveats

- **TimeSeries panels won't render below ~150 px viewport** ([Grafana
  forum](https://community.grafana.com/t/display-time-series-on-small-screen-width-800pix/61121)).
  If the panel slot is too small (e.g. a thin Plasma panel at 24 px tall),
  the chart area collapses to nothing. For small slots, prefer a **Stat
  panel** or a panel without axes/legend.
- **Grafana stretches the panel to fit the iframe** — no aspect preservation.
  If your Grafana panel is portrait-ish (e.g. 1032×1085) and your popup is
  landscape (800×444), the chart will be visually stretched (or letterboxed
  depending on Grafana's responsive rendering).
- For dramatically-mismatched aspect ratios, choose a panel that's natively
  landscape in the Grafana dashboard grid (e.g. 24 units wide × 6 units tall).

### Authelia in front of Grafana

The widget detects Authelia redirects and prompts you to log in once via the
embedded view. The session cookie is stored in an isolated `WebEngineProfile`
under `~/.local/share/iframe-plasma/<plasmoidId>/` and survives plasmashell
restarts.

If you want **zero-prompt** access from the widget while still requiring
Authelia from a browser, you have two options:

1. **Grafana anonymous auth in a separate org behind Authelia** — pair
   `[auth.anonymous] enabled = true` (org = `Homelab-Public`) with Authelia
   `policy: bypass` on the Grafana hostname for internal traffic.

2. **OIDC: Authelia as IdP for Grafana** — `[auth.generic_oauth]` in Grafana,
   `identity_providers.oidc` in Authelia. One login covers both layers; the
   widget needs no changes.

API/service-account tokens authenticate Grafana's JSON API but **not** the
rendered HTML routes (`/d-solo/…`) — for token-based embedding use
`[auth.jwt] url_login = true` (see Grafana docs).

## Verification & debugging

```bash
# QML / plasmashell logs
journalctl --user -f -t plasmashell

# WebEngine debug logging
QT_LOGGING_RULES="qt.webenginecontext.debug=true" kstart plasmashell

# Inspect cookies stored in the widget's isolated profile
sqlite3 ~/.local/share/iframe-plasma/<plasmoidId>/Cookies \
    "SELECT host_key, name, expires_utc FROM cookies;"

# Verify wallet entries
kwalletmanager6  # browse → folder "iframe-plasma"
```

## Acknowledgements

The bundled "Icon" thumbnail set under
[`package/contents/icons/bundled/`](package/contents/icons/bundled) ships
~30 hand-picked monitoring/dashboard glyphs from
[Phosphor Icons](https://phosphoricons.com) (MIT-licensed; see
[`package/contents/icons/bundled/LICENSE`](package/contents/icons/bundled/LICENSE)).

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE).
