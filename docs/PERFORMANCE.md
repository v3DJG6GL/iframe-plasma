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

- **Popup tabs load on demand** — a tab's web view (and its renderer
  process) is only created the first time you open that tab.
- **Background tabs** — in a multi-tab popup, only the visible tab runs at
  full speed. The others are *frozen* (their JavaScript and Grafana
  auto-refresh suspended).
- **Collapsed popup** — when the popup is closed, every tab is frozen, then
  *discarded* after a longer idle (the renderer subprocess is shut down and
  its memory reclaimed). Reopening reloads a discarded tab. Plasma keeps the
  popup alive after closing, so the discard delay is what bounds how long
  closed tabs hold memory.
- **Screen locked** — while the session is locked, web views, the in-panel
  thumbnail and the auto-cycle all pause.
- **Panel thumbnail** — with the auto-cycle, each thumbnail is frozen a few
  seconds after it rotates out and resumes where it left off when it comes
  back (Grafana refreshes itself on becoming visible). It also pauses while
  the screen is locked or its panel slot is off-screen.
- **Renderer recycling** — a thumbnail whose renderer process has run longer
  than the recycle age is discarded right after it next rotates out and
  reloads fresh on its next appearance, capping memory a long-running page
  accumulates.

The delays are configurable under **Configure → Advanced**:

| Setting | Default | Applies to |
|---|---|---|
| Popup → *Freeze hidden tabs after* | 30 s | popup tabs |
| Popup → *Discard frozen tabs after* | 900 s | popup tabs |
| Panel thumbnail → *Freeze hidden thumbnails after* | 5 s | thumbnails; keep it below the auto-cycle interval, or rotating thumbnails never freeze |
| Panel thumbnail → *Discard frozen thumbnails after* | 600 s | thumbnails that stay off-screen (a rotating thumbnail comes back sooner) |
| Panel thumbnail → *Reload on return if frozen for* | never | thumbnails of pages that don't refresh themselves |
| Panel thumbnail → *Recycle renderers after* | 120 min | thumbnails; 0 = never |
| Memory → *Force garbage collection every* | 20 s | all views; needs the flag below |

A brief reload when reopening a tab that was discarded after a long idle is
expected — it is the renderer being recreated, not a bug.

Freezing stops a page from doing work but does not return its memory; only
discarding (or recycling) does.

## Qt WebEngine 6.10: memory growth

Qt WebEngine 6.10 has a garbage-collection regression
([QTBUG-141377](https://qt-project.atlassian.net/browse/QTBUG-141377)): V8 is
built without write barriers, so memory on the Blink heap is never collected
on its own and a constantly repainting page — a live Grafana panel — grows
toward ~2 GB per renderer process. It is fixed for Qt 6.11 only
([Gerrit 772657](https://codereview.qt-project.org/c/qt/qtwebengine-chromium/+/772657));
there is no fix for 6.10, and Qt 6.12 is not confirmed yet. Check your
version with `dpkg -l libqt6webenginecore6` (or your distribution's
equivalent).

The widget works around it by calling a full garbage collection in every
page every 20 s (**Configure → Advanced → Memory**). The call only exists
when plasmashell starts with V8's `--expose-gc` flag, so add it to the file
where you set `QML_IMPORT_PATH`, `~/.config/plasma-workspace/env/iframe-plasma.sh`:

```sh
export QTWEBENGINE_CHROMIUM_FLAGS="--js-flags=--expose-gc ${QTWEBENGINE_CHROMIUM_FLAGS}"
```

then log out and back in (or restart plasmashell from a shell that sourced
the file). Scripts in `plasma-workspace/env/` apply to every Qt WebEngine
application in the session; the flag is harmless for them. To scope it to
plasmashell only, use a systemd drop-in instead — note that it is ignored
when plasmashell is restarted by hand with `kstart`:

```sh
systemctl --user edit plasma-plasmashell.service
# [Service]
# Environment=QTWEBENGINE_CHROMIUM_FLAGS=--js-flags=--expose-gc
```

Check it took effect: `tr '\0' '\n' < /proc/$(pgrep -u "$(id -un)" -x plasmashell)/environ | grep CHROMIUM`.
With remote debugging enabled, `typeof gc` in a page's console returns
`"function"`. `--max-old-space-size` and similar V8 heap flags do **not**
help: the growing heap is Blink's, not V8's.

## One renderer process for all tabs (`--process-per-site`)

By default each web view gets its own renderer process
([process models](https://doc.qt.io/qt-6/qtwebengine-overview.html#process-models)).
If all your tabs point at the **same Grafana host**, the
`--process-per-site` Chromium flag puts them in one shared renderer. This is
**not recommended by default** any more:

- discarding or recycling a view no longer shuts its renderer down (Chromium
  only kills a renderer that hosts that one page), so the widget cannot
  reclaim memory from it;
- on Qt WebEngine 6.10 every page's leak (see above) and every crash lands in
  that one process.

If you still want it, add it to the same variable, before plasmashell starts:

```sh
export QTWEBENGINE_CHROMIUM_FLAGS="--process-per-site --js-flags=--expose-gc"
```

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
  locked states should show them idle or gone. With the auto-cycle, only the
  thumbnail on screen should use CPU.
- Lifecycle trace — start plasmashell with
  `QT_LOGGING_RULES="io.github.v3djg6gl.iframe.lifecycle.debug=true"`; the
  journal then shows every `active->frozen`, `frozen->discarded` and
  `(recycle)` step per view (`thumb[i]` / `popup[i]`).
- The widget supports `QTWEBENGINE_REMOTE_DEBUGGING` (see **Configure →
  Advanced**) — Chrome DevTools' Performance and Memory tabs profile the
  embedded Grafana page directly.
