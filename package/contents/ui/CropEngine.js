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
    if (!el) {
      // Fail open: when the new selector can't match yet (SPA hasn't
      // mounted the target, page mid-route-change), drop the gating
      // data-ifp-* attributes so the body is fully visible instead
      // of blanked by the leftover isolation rule from the previous
      // selector. Observers will re-engage isolation on the next
      // mutation if/when the target eventually appears.
      document.documentElement.removeAttribute('data-ifp-isolate');
      document.documentElement.removeAttribute('data-ifp-thumb');
      return 'wait';
    }
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
  let missStreak = 0;
  // Inject a small in-page banner after a sustained miss so the user
  // knows the selector didn't match (instead of staring at an
  // unexpectedly-uncropped page). Self-removes when apply() matches.
  function showMissBanner() {
    if (document.getElementById('ifp-miss-banner')) return;
    const b = document.createElement('div');
    b.id = 'ifp-miss-banner';
    b.style.cssText = 'position:fixed!important;bottom:8px!important;left:8px!important;background:#1f1f1f!important;color:#fff!important;padding:6px 12px!important;border:1px solid #ff8000!important;border-radius:4px!important;font:12px/1.4 sans-serif!important;z-index:2147483647!important;pointer-events:none!important;max-width:60vw!important;box-shadow:0 2px 6px rgba(0,0,0,0.6)!important;';
    b.textContent = "iframe-plasma: selector '" + sel + "' not found — showing full page";
    (document.body || document.documentElement).appendChild(b);
  }
  function hideMissBanner() {
    const b = document.getElementById('ifp-miss-banner');
    if (b && b.parentNode) b.parentNode.removeChild(b);
  }
  function schedule() {
    if (rafId) return;
    rafId = requestAnimationFrame(function(){
      rafId = 0;
      const r = apply();
      if (r === 'wait') {
        // ~10 consecutive misses. With the 3 s poll alone that's 30 s;
        // burst MutationObserver fires usually reach the threshold within
        // a few seconds of an SPA mounting nothing matching.
        if (++missStreak >= 10) showMissBanner();
      } else if (r === 'matched') {
        missStreak = 0;
        hideMissBanner();
      }
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
  // SPA navigation hook: WebTab.qml installs a MainWorld bridge that
  // dispatches an \`ifp-navigation\` CustomEvent on history.{push,replace}-
  // State / popstate / hashchange. Custom DOM events cross worlds, so we
  // can listen here in the isolated world and re-evaluate the selector
  // when the React/Vue router changes route without a full reload. The
  // window.__ifpThumbSchedule indirection lets a re-injected IIFE swap
  // in a fresh schedule() closure without re-adding the listener.
  window.__ifpThumbSchedule = schedule;
  if (!window.__ifpNavListenerAdded) {
    window.__ifpNavListenerAdded = true;
    window.addEventListener('ifp-navigation', function(){
      if (window.__ifpThumbSchedule) window.__ifpThumbSchedule();
    });
  }
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
    window.__ifpThumbSchedule = null;
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
    const banner = document.getElementById('ifp-miss-banner');
    if (banner && banner.parentNode) banner.parentNode.removeChild(banner);
    return 'cleared';
  } catch (e) { return 'clear-error: ' + e.message; }
})()`;

// Element picker. Highlights hovered elements with an outline and a small
// instruction banner, then on click computes a robust CSS selector and
// stashes it on `window.__ifpPicked`. QML polls that property via
// buildPickerPollJs(). Esc cancels (sets __ifpPicked = "").
//
// Selector preference: unique #id → unique [data-testid|data-test|data-cy|
// data-qa] → unique [aria-label] → unique stable class chain (filters out
// CSS-Modules-style `__hash` and Vite-style `_HASH` suffixes that change
// between builds) → short structural path with nth-of-type fallback.
const _PICKER_START_BODY = `(function(){
  // Defensive teardown inline at start — folding the equivalent of
  // buildClearJs into the same runJavaScript call eliminates the
  // microtask gap between WebTab's previous two-call sequence
  // (buildClearJs → buildPickerStartJs). The renderer used to keep
  // the isolated layout cached between the two callbacks long enough
  // for elementFromPoint to return descendants of the previously-
  // isolated card; folding here + a synchronous reflow guarantees
  // a fresh layout before the picker's first listener fires.
  if (window.__ifpThumbObserver)     try { window.__ifpThumbObserver.disconnect();     } catch(e) {}
  if (window.__ifpThumbWrapObserver) try { window.__ifpThumbWrapObserver.disconnect(); } catch(e) {}
  if (window.__ifpThumbResize)       try { window.__ifpThumbResize.disconnect();       } catch(e) {}
  if (window.__ifpThumbInterval)     clearInterval(window.__ifpThumbInterval);
  window.__ifpThumbObserver = null;
  window.__ifpThumbWrapObserver = null;
  window.__ifpThumbResize = null;
  window.__ifpThumbInterval = null;
  window.__ifpThumbSchedule = null;
  document.documentElement.removeAttribute('data-ifp-thumb');
  document.documentElement.removeAttribute('data-ifp-isolate');
  const _keeps = document.querySelectorAll('[data-ifp-keep="1"]');
  for (let _i = 0; _i < _keeps.length; _i++) _keeps[_i].removeAttribute('data-ifp-keep');
  const _targets = document.querySelectorAll('[data-ifp-target="1"]');
  for (let _j = 0; _j < _targets.length; _j++) _targets[_j].removeAttribute('data-ifp-target');
  const _st = document.getElementById('ifp-thumb-style');
  if (_st && _st.parentNode) _st.parentNode.removeChild(_st);
  const _dispOld = document.getElementById('ifp-thumb-display');
  if (_dispOld && _dispOld.parentNode) _dispOld.parentNode.removeChild(_dispOld);
  const _miss = document.getElementById('ifp-miss-banner');
  if (_miss && _miss.parentNode) _miss.parentNode.removeChild(_miss);
  // Synchronous layout flush — reading offsetHeight forces Blink to
  // re-compute layout NOW, before the picker attaches listeners. Without
  // this, the first elementFromPoint() can return stale-layout hits.
  void document.documentElement.offsetHeight;

  if (window.__ifpPickerActive) return 'already-active';
  window.__ifpPickerActive = true;
  window.__ifpPicked = null;

  const outline = document.createElement('div');
  outline.id = '__ifpPickerOutline';
  outline.style.cssText = 'position:fixed!important;pointer-events:none!important;z-index:2147483647!important;background:rgba(255,128,0,0.20)!important;outline:2px solid #ff8000!important;outline-offset:-2px!important;box-shadow:0 0 0 1px rgba(0,0,0,0.6)!important;transition:none!important;';
  document.documentElement.appendChild(outline);

  const banner = document.createElement('div');
  banner.id = '__ifpPickerBanner';
  banner.style.cssText = 'position:fixed!important;top:8px!important;left:50%!important;transform:translateX(-50%)!important;background:#1f1f1f!important;color:#fff!important;padding:6px 14px!important;border:1px solid #ff8000!important;border-radius:4px!important;font:13px/1.4 sans-serif!important;z-index:2147483647!important;pointer-events:none!important;box-shadow:0 2px 8px rgba(0,0,0,0.6)!important;';
  banner.textContent = 'iframe-plasma: pick an element — Esc to cancel';
  document.documentElement.appendChild(banner);

  function cssEscape(s) {
    // Chromium (Qt WebEngine) always exposes CSS.escape; the fallback is
    // belt-and-braces for older WebEngine builds. Escapes the same set as
    // the CSS Object Model spec — anything not [A-Za-z0-9_-].
    if (window.CSS && CSS.escape) return CSS.escape(s);
    return String(s).replace(/[^a-zA-Z0-9_-]/g, function(c){ return '\\\\' + c; });
  }
  // True for tokens that look like CSS-Modules / Vite / styled-components
  // hash suffixes — we exclude them from the class-chain selector because
  // they change on every build.
  function looksHashed(c) {
    if (!/^[a-zA-Z][\\w-]*$/.test(c)) return true;
    if (/__[a-z0-9]{4,}$/i.test(c)) return true;        // CSS Modules: Foo__abc123
    if (/_[A-Z0-9]{4,}$/.test(c))   return true;        // Vite: foo_ABC12
    if (/^css-[a-z0-9]{4,}$/i.test(c)) return true;     // emotion: css-abc123
    if (/^sc-[a-zA-Z0-9]{6,}$/.test(c)) return true;    // styled-components: sc-aBcDeF
    return false;
  }
  function structural(el) {
    const parts = [];
    let cur = el, depth = 0;
    while (cur && cur.tagName && cur !== document.body && depth < 4) {
      if (cur.id) { parts.unshift('#' + cssEscape(cur.id)); break; }
      let part = cur.tagName.toLowerCase();
      const sibs = cur.parentElement
        ? Array.from(cur.parentElement.children).filter(c => c.tagName === cur.tagName)
        : [];
      if (sibs.length > 1) part += ':nth-of-type(' + (sibs.indexOf(cur) + 1) + ')';
      parts.unshift(part);
      cur = cur.parentElement;
      depth++;
    }
    return parts.join(' > ');
  }
  function compute(el) {
    if (!el || !el.tagName) return '';
    if (el.id) {
      const sel = '#' + cssEscape(el.id);
      try { if (document.querySelectorAll(sel).length === 1) return sel; } catch(e) {}
    }
    const attrs = ['data-testid','data-test','data-cy','data-qa'];
    for (let i = 0; i < attrs.length; i++) {
      const v = el.getAttribute(attrs[i]);
      if (v) {
        const sel = '[' + attrs[i] + '="' + v.replace(/"/g, '\\\\"') + '"]';
        try { if (document.querySelectorAll(sel).length === 1) return sel; } catch(e) {}
      }
    }
    const aria = el.getAttribute('aria-label');
    if (aria) {
      const sel = '[aria-label="' + aria.replace(/"/g, '\\\\"') + '"]';
      try { if (document.querySelectorAll(sel).length === 1) return sel; } catch(e) {}
    }
    if (el.classList && el.classList.length > 0) {
      const stable = Array.from(el.classList).filter(c => !looksHashed(c));
      if (stable.length > 0) {
        const sel = '.' + stable.map(cssEscape).join('.');
        try { if (document.querySelectorAll(sel).length === 1) return sel; } catch(e) {}
      }
    }
    return structural(el);
  }

  let lastHover = null;
  function move(e) {
    // Hide the outline so elementFromPoint returns the underlying element,
    // not the outline itself.
    outline.style.display = 'none';
    const t = document.elementFromPoint(e.clientX, e.clientY);
    outline.style.display = 'block';
    if (!t || t === outline || t === banner) return;
    if (t === lastHover) return;
    lastHover = t;
    const r = t.getBoundingClientRect();
    outline.style.left   = r.left   + 'px';
    outline.style.top    = r.top    + 'px';
    outline.style.width  = Math.max(2, r.width)  + 'px';
    outline.style.height = Math.max(2, r.height) + 'px';
  }
  function click(e) {
    outline.style.display = 'none';
    const t = document.elementFromPoint(e.clientX, e.clientY) || lastHover;
    e.preventDefault();
    e.stopImmediatePropagation();
    e.stopPropagation();
    finish(compute(t));
  }
  function key(e) {
    if (e.key === 'Escape') {
      // Also stop propagation so Chromium doesn't re-post the unhandled
      // key event to the host window — without that Plasma's popup-close
      // shortcut fires before the QML layer can decide whether to swallow.
      e.preventDefault();
      e.stopImmediatePropagation();
      e.stopPropagation();
      finish('');
    }
  }
  function finish(result) {
    window.__ifpPickerActive = false;
    window.__ifpPicked = result || '';
    document.removeEventListener('mousemove', move, true);
    document.removeEventListener('click',     click, true);
    document.removeEventListener('keydown',   key,   true);
    if (outline.parentNode) outline.parentNode.removeChild(outline);
    if (banner.parentNode)  banner.parentNode.removeChild(banner);
    console.info('[ifp-picker] result=' + JSON.stringify(window.__ifpPicked));
  }
  document.addEventListener('mousemove', move,  true);
  document.addEventListener('click',     click, true);
  document.addEventListener('keydown',   key,   true);
  return 'started';
})()`;

const _PICKER_POLL_BODY = "(window.__ifpPicked === undefined ? null : window.__ifpPicked)";
const _PICKER_CLEAR_BODY = "(function(){ const v = window.__ifpPicked; window.__ifpPicked = null; return v; })()";

function buildApplyJs(selector) {
    return _APPLY_BODY + "(" + JSON.stringify(selector) + ")";
}

function buildClearJs() {
    return _CLEAR_BODY;
}

function buildPickerStartJs() {
    return _PICKER_START_BODY;
}

function buildPickerPollJs() {
    return _PICKER_POLL_BODY;
}

function buildPickerClearJs() {
    return _PICKER_CLEAR_BODY;
}
