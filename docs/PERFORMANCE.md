<!--
    SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
    SPDX-License-Identifier: AGPL-3.0-or-later
-->
# Performance & system load

Each tab in this widget is a full Chromium renderer running JavaScript,
network polling and continuous chart repainting. A handful of live Grafana
dashboards left open for days is, by far, the widget's dominant cost. This
page covers what the widget does automatically and what you can tune.

## What the widget does for you

The widget pauses web content whenever it is **not being looked at**:

- **Background tabs** — in a multi-tab popup, only the visible tab runs at
  full speed. The others are *frozen* (their JavaScript and Grafana
  auto-refresh suspended).
- **Collapsed popup** — when the popup is closed, every tab is frozen, then
  *discarded* after a longer idle (the renderer subprocess is shut down and
  its memory reclaimed). Reopening reloads a discarded tab.
- **Screen locked** — while the session is locked, web views, the in-panel
  thumbnail and the auto-cycle all pause.
- **Panel thumbnail** — pauses while the screen is locked or its panel slot is
  off-screen, and resumes refreshed.

The two delays are configurable under **Configure → Advanced**:

- *Freeze hidden views after* — default **30 s**.
- *Discard frozen views after* — default **600 s** (10 min). Set this very
  high to only ever freeze and never reclaim renderer memory.

A brief reload when reopening a tab that was discarded after a long idle is
expected — it is the renderer being recreated, not a bug.

## Recommended: one renderer process for all tabs

By default Chromium spawns a separate renderer process per site. If all your
tabs point at the **same Grafana host**, you can collapse them onto a single
shared renderer — a large memory saving — with the `--process-per-site`
Chromium flag.

The widget cannot set this itself; it must be in the environment **before
plasmashell starts**, in the same place you set `QML_IMPORT_PATH`:

```sh
export QTWEBENGINE_CHROMIUM_FLAGS=--process-per-site
```

Add it to `~/.config/plasma-workspace/env/` (a script there is sourced at
session start) or your shell profile, then restart plasmashell.

Do **not** set `--single-process` (a renderer crash would take down
plasmashell) or `--disable-background-timer-throttling` (the opposite of what
you want).

## Tuning Grafana dashboards

The refresh rate and panel count of the dashboard itself are the biggest CPU
levers — bigger than anything in the widget:

- **Refresh interval** — use the longest interval you can tolerate, or
  Grafana's `Auto` (it scales the refresh to the time range). Each panel
  re-queries and re-renders on every refresh.
- **Kiosk mode / `d-solo`** — the widget's Grafana URL helper already rewrites
  links to the chrome-less `/d-solo/...&kiosk` form; fewer DOM nodes to render.
- **Fewer panels per dashboard** — every embedded panel is its own set of
  queries and its own render surface.
- **Limit the time range / data points** — less data for the browser to chart.

## Measuring

- `powertop` — compare the wakeups attributed to `plasmashell` with the widget
  enabled vs disabled, and with the popup open vs collapsed.
- `top` / `htop` — watch the `QtWebEngineProcess` processes; collapsed and
  locked states should show them idle or gone.
- The widget supports `QTWEBENGINE_REMOTE_DEBUGGING` (see **Configure →
  Advanced**) — Chrome DevTools' Performance and Memory tabs profile the
  embedded Grafana page directly.
