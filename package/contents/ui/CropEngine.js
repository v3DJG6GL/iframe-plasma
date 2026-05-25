/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * In-page CSS-selector crop helpers, shared by main.qml's panel-slot
 * mini-view and WebTab.qml's full popup view.
 *
 * `buildApplyJs(selector)` returns the JS source for a single
 * runJavaScript() call. The returned IIFE installs (idempotently)
 * styles, observers and timers that find `selector`, then either
 *
 *   1. uPlot canvas crop — when the matched element is a <canvas>,
 *      pixel-blit the chart area (excluding axis margins) onto a
 *      full-viewport overlay canvas. Same logic as the previous
 *      inline implementation in main.qml. Used by Grafana presets
 *      (chartOnly = `.u-wrap > canvas`).
 *
 *   2. Generic element-isolation — when the matched element is any
 *      other tag, walk the ancestor chain to <body> tagging each
 *      node with data-ifp-keep="1" and the target with
 *      data-ifp-target="1", then set data-ifp-isolate="1" on <html>.
 *      A stylesheet hides every child of a kept node that is not
 *      itself kept or the target, and positions the target fixed
 *      at the viewport. Survives SPA re-renders because the rules
 *      key on data-attributes and the MutationObserver re-applies
 *      them on every subtree mutation.
 *
 * Both paths share the existing observer wiring (rAF-coalesced
 * MutationObserver on body, ResizeObserver on the matched element's
 * parent, 3 s setInterval poll for Grafana's canvas-pixel refresh
 * which fires no DOM mutation).
 *
 * `buildClearJs()` returns code to tear down all marker attributes
 * and disconnect observers — used when the popup-view selector is
 * cleared so the original page is restored without a reload.
 */
.pragma library

// The IIFE body is selector-agnostic; only the trailing call-args
// string is appended per invocation. Built once per import.
const _APPLY_BODY = `(function(sel){
  function ensureStyle() {
    if (document.getElementById('ifp-thumb-style')) return;
    const s = document.createElement('style');
    s.id = 'ifp-thumb-style';
    s.textContent = [
      // Grafana-specific chrome hiding (gated on data-ifp-thumb so it
      // never affects the isolation path). Harmless on non-Grafana
      // pages because the selectors don't match anything there.
      'html[data-ifp-thumb="1"],html[data-ifp-thumb="1"] body{margin:0!important;padding:0!important;overflow:hidden!important;background:#181b1f!important;}',
      'html[data-ifp-thumb="1"] [data-testid="data-testid header-container"]{display:none!important;}',
      'html[data-ifp-thumb="1"] img[alt="Grafana"],html[data-ifp-thumb="1"] div:has(>img[alt="Grafana"]),html[data-ifp-thumb="1"] div:has(>span+img[alt="Grafana"]),html[data-ifp-thumb="1"] div[class*="logoContainer"]{display:none!important;}',
      'html[data-ifp-thumb="1"] [data-testid^="data-testid Panel menu "],html[data-ifp-thumb="1"] [data-testid="panel-menu-button"],html[data-ifp-thumb="1"] button[aria-label^="Menu for panel "],html[data-ifp-thumb="1"] [data-testid^="data-testid Panel menu item "]{display:none!important;}',
      // Display canvas for the cropAxes path.
      '#ifp-thumb-display{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;z-index:2147483647!important;background:#181b1f!important;display:block!important;margin:0!important;padding:0!important;border:none!important;transform:none!important;}',
      // Generic element-isolation rules (gated on data-ifp-isolate).
      // Hide every child of a kept node that isn't itself kept or the
      // target. Two-level rule covers body-direct-children AND every
      // intermediate kept ancestor in the target's chain — so e.g.
      // body>div.app>div.sidebar gets hidden even though div.app is kept.
      'html[data-ifp-isolate="1"]{margin:0!important;padding:0!important;background:#181b1f!important;}',
      'html[data-ifp-isolate="1"] body{margin:0!important;padding:0!important;background:#181b1f!important;overflow:hidden!important;}',
      'html[data-ifp-isolate="1"] body > *:not([data-ifp-keep="1"]):not([data-ifp-target="1"]),html[data-ifp-isolate="1"] [data-ifp-keep="1"] > *:not([data-ifp-keep="1"]):not([data-ifp-target="1"]){display:none!important;}',
      'html[data-ifp-isolate="1"] [data-ifp-target="1"]{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;max-width:100vw!important;max-height:100vh!important;margin:0!important;z-index:2147483647!important;overflow:auto!important;}'
    ].join('');
    (document.head||document.documentElement).appendChild(s);
  }

  // uPlot pixel-blit crop. Source canvas keeps its natural CSS box so
  // bufW/cr.width = devicePixelRatio uniformly and drawImage math is
  // correct. Used only when the matched element is a <canvas>.
  function cropAxes(srcCanvas) {
    if (!srcCanvas || srcCanvas.tagName !== 'CANVAS') return;
    const wrap = srcCanvas.parentElement;
    const over = wrap && wrap.querySelector(':scope > .u-over');
    if (!wrap || !over) return;
    const cr = srcCanvas.getBoundingClientRect();
    if (cr.width === 0 || cr.height === 0) return;
    const orct = over.getBoundingClientRect();
    let cssL, cssT, cssW, cssH;
    if (orct.width > 0 && orct.height > 0) {
      cssL = orct.left - cr.left;
      cssT = orct.top  - cr.top;
      cssW = orct.width;
      cssH = orct.height;
    } else {
      const oL = parseFloat(over.style.left)   || 0;
      const oT = parseFloat(over.style.top)    || 0;
      const oW = parseFloat(over.style.width)  || 0;
      const oH = parseFloat(over.style.height) || 0;
      if (oW === 0 || oH === 0) return;
      const wr = wrap.getBoundingClientRect();
      cssL = oL - (cr.left - wr.left); cssT = oT - (cr.top - wr.top);
      cssW = oW; cssH = oH;
    }
    const bufW = srcCanvas.width;
    const bufH = srcCanvas.height;
    if (bufW === 0 || bufH === 0) return;
    const scaleX = bufW / cr.width;
    const scaleY = bufH / cr.height;
    const sL = cssL * scaleX, sT = cssT * scaleY;
    const sW = cssW * scaleX, sH = cssH * scaleY;
    let disp = document.getElementById('ifp-thumb-display');
    if (!disp) {
      disp = document.createElement('canvas');
      disp.id = 'ifp-thumb-display';
      document.body.appendChild(disp);
    }
    const dpr = window.devicePixelRatio || 1;
    const dispCssW = window.innerWidth;
    const dispCssH = window.innerHeight;
    disp.width  = Math.max(1, Math.round(dispCssW * dpr));
    disp.height = Math.max(1, Math.round(dispCssH * dpr));
    const ctx = disp.getContext('2d');
    try { ctx.drawImage(srcCanvas, sL, sT, sW, sH, 0, 0, disp.width, disp.height); }
    catch (e) { console.warn('[ifp-thumb] drawImage failed:', e.message); return; }
    console.info('[ifp-thumb] CROP canvas-css=' + cr.width.toFixed(0) + 'x' + cr.height.toFixed(0)
      + ' src=' + bufW + 'x' + bufH + ' scale=' + scaleX.toFixed(3) + ',' + scaleY.toFixed(3)
      + ' srcRect=' + sL.toFixed(0) + ',' + sT.toFixed(0) + ',' + sW.toFixed(0) + ',' + sH.toFixed(0)
      + ' disp=' + disp.width + 'x' + disp.height);
  }

  // Generic isolation. Walks ancestors of \`el\` up to <body>, tagging
  // each with data-ifp-keep="1", tags \`el\` itself with data-ifp-target="1",
  // and sets data-ifp-isolate="1" on <html>. The stylesheet does the rest.
  // Cheap to re-run: re-tagging is idempotent and a no-op once the chain is
  // already marked. Strips stale data-ifp-keep from nodes that are no longer
  // ancestors (so SPA route changes that pick a different target self-clean).
  function isolateElement(el) {
    if (!el || !el.parentNode) return;
    const keep = new Set();
    let node = el;
    while (node && node !== document.body && node.nodeType === 1) {
      keep.add(node);
      node = node.parentElement;
    }
    // Clear stale keep markers outside the new ancestor chain.
    const stale = document.querySelectorAll('[data-ifp-keep="1"]');
    for (let i = 0; i < stale.length; i++) {
      if (!keep.has(stale[i])) stale[i].removeAttribute('data-ifp-keep');
    }
    // Tag the new chain.
    keep.forEach(function(n){ if (n !== el) n.setAttribute('data-ifp-keep', '1'); });
    // Tag the target last so a previous data-ifp-target on a different element
    // is cleared first.
    const oldTargets = document.querySelectorAll('[data-ifp-target="1"]');
    for (let j = 0; j < oldTargets.length; j++) {
      if (oldTargets[j] !== el) oldTargets[j].removeAttribute('data-ifp-target');
    }
    el.setAttribute('data-ifp-target', '1');
    document.documentElement.setAttribute('data-ifp-isolate', '1');
  }

  function apply() {
    let el;
    try { el = document.querySelector(sel); }
    catch(e) { console.warn('[ifp-thumb] invalid selector "'+sel+'": '+e.message); return 'invalid'; }
    if (!el) return 'wait';
    ensureStyle();
    if (el.tagName === 'CANVAS') {
      document.documentElement.setAttribute('data-ifp-thumb','1');
      cropAxes(el);
    } else {
      isolateElement(el);
    }
    return 'matched';
  }

  const first = apply();
  if (first === 'invalid') return first;

  // Robust observer architecture:
  //   - rAF-coalesced re-application: handles burst mutations naturally.
  //   - MutationObserver on document.body{childList,subtree}: catches
  //     deep insertions AND React re-mounts that strip our data-attrs.
  //   - When a target is matched, also observe its parent for
  //     attributes:{style,width,height} so Grafana's Y-axis-width
  //     drift between refreshes triggers a transform recompute.
  //   - ResizeObserver on the parent for viewport changes.
  //   - NO timeout disconnect: same-size refreshes don't touch DOM
  //     so the observer idles cheaply when nothing changes.
  if (window.__ifpThumbObserver) window.__ifpThumbObserver.disconnect();
  if (window.__ifpThumbWrapObserver) window.__ifpThumbWrapObserver.disconnect();
  if (window.__ifpThumbResize) { try{window.__ifpThumbResize.disconnect();}catch(e){} }
  let rafId = 0;
  let lastEl = null;
  function schedule() {
    if (rafId) return;
    rafId = requestAnimationFrame(function(){
      rafId = 0;
      const r = apply();
      const el = document.querySelector(sel);
      if (r === 'matched' && el && el !== lastEl) {
        lastEl = el;
        const wrap = el.parentElement;
        if (wrap && window.__ifpThumbWrapObserver) window.__ifpThumbWrapObserver.disconnect();
        if (wrap) {
          const wo = new MutationObserver(schedule);
          wo.observe(wrap, { childList: true, subtree: true, attributes: true, attributeFilter: ['style','width','height'] });
          window.__ifpThumbWrapObserver = wo;
          try { const ro = new ResizeObserver(schedule); ro.observe(wrap); window.__ifpThumbResize = ro; } catch(e) {}
        }
        console.info('[ifp-thumb] MATCHED tag=' + el.tagName + (el.className ? '.' + String(el.className).split(' ').slice(0,2).join('.') : ''));
      }
    });
  }
  const obs = new MutationObserver(schedule);
  obs.observe(document.body, { childList: true, subtree: true });
  window.__ifpThumbObserver = obs;
  // Periodic re-copy: Grafana's \`refresh=30s\` re-renders the canvas
  // pixel buffer via canvas 2D context calls — those do NOT fire any
  // DOM mutation, so the MutationObserver doesn't catch new data.
  // Cheap: a single drawImage + getBoundingClientRect call.
  if (window.__ifpThumbInterval) clearInterval(window.__ifpThumbInterval);
  window.__ifpThumbInterval = setInterval(schedule, 3000);
  return first === 'matched' ? 'matched-and-observing' : 'observing';
})`;

// Tears down all crop state (data attributes, observers, timers,
// the overlay display canvas). Used when the popup-view selector
// is cleared to restore the original page without a reload.
const _CLEAR_BODY = `(function(){
  try {
    if (window.__ifpThumbObserver) window.__ifpThumbObserver.disconnect();
    if (window.__ifpThumbWrapObserver) window.__ifpThumbWrapObserver.disconnect();
    if (window.__ifpThumbResize) window.__ifpThumbResize.disconnect();
    if (window.__ifpThumbInterval) clearInterval(window.__ifpThumbInterval);
    window.__ifpThumbObserver = null;
    window.__ifpThumbWrapObserver = null;
    window.__ifpThumbResize = null;
    window.__ifpThumbInterval = null;
    document.documentElement.removeAttribute('data-ifp-thumb');
    document.documentElement.removeAttribute('data-ifp-isolate');
    const keeps = document.querySelectorAll('[data-ifp-keep="1"]');
    for (let i = 0; i < keeps.length; i++) keeps[i].removeAttribute('data-ifp-keep');
    const targets = document.querySelectorAll('[data-ifp-target="1"]');
    for (let j = 0; j < targets.length; j++) targets[j].removeAttribute('data-ifp-target');
    const disp = document.getElementById('ifp-thumb-display');
    if (disp && disp.parentNode) disp.parentNode.removeChild(disp);
    const style = document.getElementById('ifp-thumb-style');
    if (style && style.parentNode) style.parentNode.removeChild(style);
    return 'cleared';
  } catch (e) { return 'clear-error: ' + e.message; }
})()`;

function buildApplyJs(selector) {
    return _APPLY_BODY + "(" + JSON.stringify(selector) + ")";
}

function buildClearJs() {
    return _CLEAR_BODY;
}
