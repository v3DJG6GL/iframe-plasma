/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Sources of user scripts injected into every embedded page. Pure string
 * builders so tests/js/pagescripts.test.mjs can run them against fakes.
 */
.pragma library

// Qt WebEngine 6.10 garbage-collection workaround (QTBUG-141377).
//
// Qt 6.10 builds V8 with write barriers disabled and a single generation,
// so allocations on the Blink (Oilpan) heap never trigger a collection: a
// page that keeps repainting (a live Grafana panel) grows toward ~2 GB per
// renderer. Fixed upstream for Qt 6.11 only. A full gc() — which also
// collects Oilpan — every 10–30 s keeps it flat, but `gc` only exists when
// plasmashell starts with QTWEBENGINE_CHROMIUM_FLAGS=--js-flags=--expose-gc
// (see docs/PERFORMANCE.md). Without the flag the script does nothing.
//
// Injected in MainWorld at DocumentCreation, so `gc` is captured before
// any page script can shadow it. The first call waits a random fraction
// of the interval, spreading the (synchronous) GC pauses of several views.
// Returns "" when intervalSec <= 0 (workaround disabled).
function gcWorkaroundSource(intervalSec) {
    const ms = Math.round(Number(intervalSec) * 1000);
    if (!(ms > 0)) return "";
    return "(function(){\n" +
           "  if (window.__ifpGcArmed) return;\n" +
           "  var g = (typeof gc === 'function') ? gc : null;\n" +
           "  if (!g) return;\n" +
           "  window.__ifpGcArmed = true;\n" +
           "  var ms = " + ms + ";\n" +
           "  setTimeout(function(){\n" +
           "    try { g(); } catch (e) {}\n" +
           "    setInterval(function(){ try { g(); } catch (e) {} }, ms);\n" +
           "  }, Math.floor(Math.random() * ms));\n" +
           "})();";
}

// Grafana refresh "Off" control. Patches history.{push,replace}State so
// any URL the page writes has `refresh=` stripped while
// window.__iframePlasmaRefreshOff is true.
//
// `off` is baked into the source and seeded on every run: the script is
// injected at DocumentCreation, and a flag set on the live page would not
// survive the navigation that applies the user's choice. Seeding comes
// before the already-patched guard so the newest copy of the script wins.
function refreshControlSource(off) {
    return "(function(){\n" +
           "  window.__iframePlasmaRefreshOff = " + (off === true ? "true" : "false") + ";\n" +
           "  if (window.__iframePlasmaRefreshPatched) return;\n" +
           "  window.__iframePlasmaRefreshPatched = true;\n" +
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
}
