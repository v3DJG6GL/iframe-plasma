// SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for package/contents/ui/CropEngine.js. Loads the library, strips
// Qt's `.pragma library` directive (a no-op in V8), and exercises the
// exported build*Js() functions. Some assertions verify the *shape* of
// the returned JS source (JSON-escaping, presence of key markers); the
// rest spin up jsdom and execute the returned IIFE to check DOM-side
// behaviour (data-ifp-* tagging, isolation cleanup, picker installation).

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { JSDOM } from "jsdom";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const CROP_PATH = path.join(__dirname, "..", "..", "package", "contents", "ui", "CropEngine.js");

// Load CropEngine.js, strip the .pragma library directive, and evaluate it
// in a fresh sandbox. The exports are `module.exports`-style attached to
// the sandbox via a small footer that wraps each `function buildXxx`.
function loadCropEngine() {
    const raw = fs.readFileSync(CROP_PATH, "utf8");
    const stripped = raw.replace(/^\.pragma library/m, "");
    const footer = `
        module.exports = {
            buildApplyJs, buildClearJs, buildPickerStartJs,
            buildPickerPollJs, buildPickerClearJs
        };
    `;
    const sandbox = { module: { exports: {} }, console };
    vm.runInNewContext(stripped + footer, sandbox, { filename: "CropEngine.js" });
    return sandbox.module.exports;
}

const ce = loadCropEngine();

// ============================================================
// 1. Shape-of-output tests — no DOM needed
// ============================================================

test("buildApplyJs returns IIFE-shaped JS appending selector arg", () => {
    const js = ce.buildApplyJs(".u-wrap > canvas");
    // Signature is function(sel, opts) — opts is omitted from the call
    // tail when the single-arg form is used (legacy parity).
    assert.ok(js.startsWith("(function(sel, opts){"));
    assert.ok(js.endsWith('(".u-wrap > canvas")'),
        `expected to end with selector arg, got: ${js.slice(-60)}`);
});

test("buildApplyJs JSON-escapes selector with embedded quotes", () => {
    const js = ce.buildApplyJs("[data-testid='foo']");
    // JSON.stringify wraps in double-quotes and escapes none of the singles.
    assert.ok(js.endsWith("(\"[data-testid='foo']\")"));
});

test("buildApplyJs JSON-escapes selector with backslash", () => {
    const js = ce.buildApplyJs(".foo\\bar");
    // backslash escapes to \\\\ in JSON.
    assert.ok(js.includes('".foo\\\\bar"'));
});

test("buildApplyJs JSON-escapes selector with double quotes", () => {
    const js = ce.buildApplyJs('div[title="x"]');
    assert.ok(js.includes('"div[title=\\"x\\"]"'));
});

test("buildApplyJs with empty selector still emits a callable", () => {
    const js = ce.buildApplyJs("");
    assert.ok(js.endsWith('("")'));
});

test("buildClearJs returns non-empty teardown IIFE", () => {
    const js = ce.buildClearJs();
    assert.ok(js.length > 50);
    assert.ok(js.includes("data-ifp-keep") || js.includes("ifp-thumb"),
        "teardown must reference the marker attributes it clears");
});

test("buildPickerStartJs returns IIFE that installs window-level listeners", () => {
    const js = ce.buildPickerStartJs();
    assert.ok(js.includes("addEventListener"));
    assert.ok(js.includes("__ifpPicked") || js.includes("__ifpPicker"),
        "picker must seed a __ifp* global for QML to poll");
});

test("buildPickerPollJs returns a window.__ifpPicked read expression", () => {
    const js = ce.buildPickerPollJs();
    assert.ok(js.includes("__ifpPicked"));
});

test("buildPickerClearJs reads and resets __ifpPicked atomically", () => {
    const js = ce.buildPickerClearJs();
    assert.ok(js.includes("__ifpPicked"));
    assert.ok(js.includes("null"),
        "clear must set the global back to null");
});

// ============================================================
// 2. DOM-execution tests — load returned JS inside jsdom
// ============================================================

// Spin up a fresh jsdom and execute the returned IIFE inside its window.
// Returns { dom, applyResult } where applyResult is whatever the IIFE
// returned (status string).
function runApply(html, selector) {
    const dom = new JSDOM(html, { runScripts: "outside-only" });
    // Stub the observers + animation frame that the IIFE installs.
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    // The IIFE installs a setInterval poll; stub so it doesn't keep Node alive.
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};
    // Run the apply IIFE; capture the return value via a small wrapper.
    const js = ce.buildApplyJs(selector);
    const result = dom.window.eval(`(${js})`);
    return { dom, result };
}

test("apply: returns status string for valid selector that matches", () => {
    const { result } = runApply(
        "<!doctype html><html><body><div id='target'>x</div></body></html>",
        "#target");
    assert.ok(typeof result === "string");
    // Either "matched", "observing", or "matched-and-observing".
    assert.ok(/match|observ/.test(result), `unexpected status: ${result}`);
});

test("apply: tags html with data-ifp-isolate when selector matches", () => {
    const { dom } = runApply(
        "<!doctype html><html><body><div id='target'>x</div></body></html>",
        "#target");
    const isolate = dom.window.document.documentElement.getAttribute("data-ifp-isolate");
    assert.equal(isolate, "1");
});

test("apply: tags target element with data-ifp-target", () => {
    const { dom } = runApply(
        "<!doctype html><html><body><section><div id='target'>x</div></section></body></html>",
        "#target");
    const target = dom.window.document.getElementById("target");
    assert.equal(target.getAttribute("data-ifp-target"), "1");
});

test("apply: tags every ancestor of target with data-ifp-keep", () => {
    const { dom } = runApply(
        "<!doctype html><html><body><section><article><div id='target'>x</div></article></section></body></html>",
        "#target");
    const doc = dom.window.document;
    assert.equal(doc.querySelector("section").getAttribute("data-ifp-keep"), "1");
    assert.equal(doc.querySelector("article").getAttribute("data-ifp-keep"), "1");
});

test("apply: invalid selector does not throw; status is 'invalid'", () => {
    const { result } = runApply(
        "<!doctype html><html><body><div/></body></html>",
        "div[unclosed");
    assert.ok(typeof result === "string");
    assert.ok(/invalid|wait|observ/.test(result),
        `expected non-throwing status, got: ${result}`);
});

test("apply: selector that doesn't match returns observing/wait status", () => {
    const { result } = runApply(
        "<!doctype html><html><body><div/></body></html>",
        "#missing");
    assert.ok(/observ|wait/.test(result),
        `expected fail-open status, got: ${result}`);
});

test("apply: re-injection clears previous data-ifp-keep markers", () => {
    const dom = new JSDOM(
        "<!doctype html><html><body><section id='a'><div id='t1'/></section><article id='b'><div id='t2'/></article></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    // The IIFE installs a setInterval poll; stub so it doesn't keep Node alive.
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};

    dom.window.eval(`(${ce.buildApplyJs("#t1")})`);
    assert.equal(dom.window.document.getElementById("a").getAttribute("data-ifp-keep"), "1");

    // Re-apply with a different target — old ancestor's keep marker should
    // be cleared.
    dom.window.eval(`(${ce.buildApplyJs("#t2")})`);
    assert.equal(dom.window.document.getElementById("a").getAttribute("data-ifp-keep"), null);
    assert.equal(dom.window.document.getElementById("b").getAttribute("data-ifp-keep"), "1");
});

test("clear: removes data-ifp-isolate marker", () => {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'/></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    // The IIFE installs a setInterval poll; stub so it doesn't keep Node alive.
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};

    dom.window.eval(`(${ce.buildApplyJs("#t")})`);
    assert.equal(dom.window.document.documentElement.getAttribute("data-ifp-isolate"), "1");

    dom.window.eval(ce.buildClearJs());
    assert.equal(dom.window.document.documentElement.getAttribute("data-ifp-isolate"), null);
});

test("clear: removes data-ifp-target from previously isolated element", () => {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'/></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    // The IIFE installs a setInterval poll; stub so it doesn't keep Node alive.
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};

    dom.window.eval(`(${ce.buildApplyJs("#t")})`);
    dom.window.eval(ce.buildClearJs());
    assert.equal(dom.window.document.getElementById("t").getAttribute("data-ifp-target"), null);
});

test("picker: start sets window.__ifpPickerArmed", () => {
    const dom = new JSDOM("<!doctype html><html><body/></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    // The IIFE installs a setInterval poll; stub so it doesn't keep Node alive.
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};

    dom.window.eval(ce.buildPickerStartJs());
    assert.equal(dom.window.__ifpPickerArmed, true);
});

test("picker: poll returns null when nothing picked yet", () => {
    const dom = new JSDOM("<!doctype html><html><body/></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    // The IIFE installs a setInterval poll; stub so it doesn't keep Node alive.
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};

    dom.window.eval(ce.buildPickerStartJs());
    const polled = dom.window.eval(ce.buildPickerPollJs());
    assert.equal(polled, null);
});

// ============================================================
// 3. Two-arg buildApplyJs(selector, opts) — feature 1 + 2 plumbing
// ============================================================

test("buildApplyJs: legacy single-arg shape unchanged (no opts)", () => {
    // Pin the existing call shape: single-arg form emits `("sel")`
    // with NO trailing opts. The IIFE inside treats missing opts as
    // an empty object — stretch mode, no keyword scan.
    const js = ce.buildApplyJs(".x");
    assert.ok(js.endsWith('(".x")'),
        `expected single-arg call, got: ${js.slice(-30)}`);
});

test("buildApplyJs: two-arg form appends JSON opts", () => {
    const js = ce.buildApplyJs(".x", { scaleMode: "fit", keywords: ["No data"] });
    assert.ok(js.includes('"scaleMode":"fit"'));
    assert.ok(js.includes('"keywords":["No data"]'));
    assert.ok(js.endsWith(")"));
});

test("buildApplyJs: opts with special chars are JSON-escaped", () => {
    const js = ce.buildApplyJs(".x", { keywords: ['Error "503"', "/^x/"] });
    // The full opts JSON is embedded as a literal — quotes inside
    // are escaped per JSON, not concatenated.
    assert.ok(js.includes('Error \\"503\\"'),
        `expected JSON-escaped double-quote, got: ${js.slice(-200)}`);
});

test("apply: stretch is default scale mode for legacy callers", () => {
    // No opts → data-ifp-scale should be "stretch" (legacy parity).
    const { dom } = runApply(
        "<!doctype html><html><body><div id='t'>x</div></body></html>",
        "#t");
    const scale = dom.window.document.documentElement.getAttribute("data-ifp-scale");
    assert.equal(scale, "stretch");
});

test("apply: fit scale mode is recorded on <html>", () => {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>x</div></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};
    dom.window.eval(`(${ce.buildApplyJs("#t", { scaleMode: "fit" })})`);
    assert.equal(dom.window.document.documentElement.getAttribute("data-ifp-scale"), "fit");
});

test("apply: original scale mode is recorded on <html>", () => {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>x</div></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};
    dom.window.eval(`(${ce.buildApplyJs("#t", { scaleMode: "original" })})`);
    assert.equal(dom.window.document.documentElement.getAttribute("data-ifp-scale"), "original");
});

test("apply: unknown scale mode falls back to stretch", () => {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>x</div></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};
    dom.window.eval(`(${ce.buildApplyJs("#t", { scaleMode: "garbage" })})`);
    assert.equal(dom.window.document.documentElement.getAttribute("data-ifp-scale"), "stretch");
});

test("keyword scan: empty keywords list emits no [ifp-keyword] log", () => {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>hello world</div></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};
    const logs = [];
    dom.window.console = { info: (m) => logs.push(String(m)), warn: () => {}, error: () => {} };
    dom.window.eval(`(${ce.buildApplyJs("#t", { keywords: [] })})`);
    const kwLogs = logs.filter(l => l.indexOf("[ifp-keyword]") !== -1);
    assert.equal(kwLogs.length, 0,
        `expected no keyword logs when list is empty, got: ${kwLogs.join(",")}`);
});

test("keyword scan: substring match emits hit=true on apply", () => {
    // The keyword scan runs inside schedule()'s rAF — we stub rAF to
    // fire synchronously so the scan runs before assertion.
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>No active streams</div></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => { cb(); return 0; };
    dom.window.cancelAnimationFrame = () => {};
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};
    const logs = [];
    dom.window.console = { info: (m) => logs.push(String(m)), warn: () => {}, error: () => {} };
    // Schedule needs at least one trigger; the apply() call inside the
    // IIFE does not by itself run schedule. Inject a fake mutation by
    // calling __ifpThumbSchedule (set by the IIFE after install).
    dom.window.eval(`(${ce.buildApplyJs("#t", { keywords: ["No active streams"] })})`);
    if (typeof dom.window.__ifpThumbSchedule === "function") {
        dom.window.__ifpThumbSchedule();
    }
    const kwLogs = logs.filter(l => l.indexOf("[ifp-keyword]") !== -1);
    assert.ok(kwLogs.some(l => l.indexOf("hit=true") !== -1),
        `expected a hit=true emission, got: ${kwLogs.join(" | ")}`);
});

test("keyword scan: text without match emits hit=false (or no transition)", () => {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>everything fine</div></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => { cb(); return 0; };
    dom.window.cancelAnimationFrame = () => {};
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};
    const logs = [];
    dom.window.console = { info: (m) => logs.push(String(m)), warn: () => {}, error: () => {} };
    dom.window.eval(`(${ce.buildApplyJs("#t", { keywords: ["No active streams"] })})`);
    if (typeof dom.window.__ifpThumbSchedule === "function") {
        dom.window.__ifpThumbSchedule();
    }
    const hitTrues = logs.filter(l => l.indexOf("[ifp-keyword] hit=true") !== -1);
    assert.equal(hitTrues.length, 0,
        `expected no hit=true on clean text, got: ${hitTrues.join(" | ")}`);
});

test("keyword scan: regex form /pattern/flags matches", () => {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>Error: 503 Service Unavailable</div></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => { cb(); return 0; };
    dom.window.cancelAnimationFrame = () => {};
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};
    const logs = [];
    dom.window.console = { info: (m) => logs.push(String(m)), warn: () => {}, error: () => {} };
    // In the JS source, `\\d` is the string `\d` (single backslash + d);
    // JSON.stringify escapes it again so the emitted IIFE sees `\d`
    // verbatim and builds the regex /^Error: \d+/ correctly.
    dom.window.eval(`(${ce.buildApplyJs("#t", { keywords: ["/^Error: \\d+/"] })})`);
    if (typeof dom.window.__ifpThumbSchedule === "function") {
        dom.window.__ifpThumbSchedule();
    }
    const kwLogs = logs.filter(l => l.indexOf("[ifp-keyword]") !== -1);
    assert.ok(kwLogs.some(l => l.indexOf("hit=true") !== -1),
        `expected regex hit=true, got: ${kwLogs.join(" | ")}`);
});

test("keyword scan: malformed regex falls through to literal substring", () => {
    // The literal "/[unclosed" substring should match itself in the page
    // text even though the regex parse fails — graceful degradation.
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>see /[unclosed for details</div></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => { cb(); return 0; };
    dom.window.cancelAnimationFrame = () => {};
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};
    const logs = [];
    const warns = [];
    dom.window.console = {
        info: (m) => logs.push(String(m)),
        warn: (m) => warns.push(String(m)),
        error: () => {},
    };
    // "/[unclosed/" — the IIFE detects the /…/ shape, fails the
    // RegExp construction, warns, and stores as substring "/[unclosed/".
    dom.window.eval(`(${ce.buildApplyJs("#t", { keywords: ["/[unclosed/"] })})`);
    if (typeof dom.window.__ifpThumbSchedule === "function") {
        dom.window.__ifpThumbSchedule();
    }
    assert.ok(warns.some(w => w.indexOf("[ifp-keyword] bad regex") !== -1),
        "expected bad-regex warning");
});

test("clear: emits final [ifp-keyword] hit=false", () => {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>hi</div></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};
    const logs = [];
    dom.window.console = { info: (m) => logs.push(String(m)), warn: () => {}, error: () => {} };
    dom.window.eval(`(${ce.buildApplyJs("#t")})`);
    dom.window.eval(ce.buildClearJs());
    const finalHits = logs.filter(l => l.indexOf("[ifp-keyword] hit=false") !== -1);
    assert.ok(finalHits.length >= 1,
        "teardown must emit a final hit=false to drop stale runtime exclusions");
});

test("clear: removes data-ifp-scale attribute", () => {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>hi</div></body></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};
    dom.window.eval(`(${ce.buildApplyJs("#t", { scaleMode: "fit" })})`);
    dom.window.eval(ce.buildClearJs());
    assert.equal(dom.window.document.documentElement.getAttribute("data-ifp-scale"), null);
});

// ============================================================
// 4. Picker tests (existing) continue below
// ============================================================

test("picker: clear returns prior value and resets to null", () => {
    const dom = new JSDOM("<!doctype html><html><body/></html>",
        { runScripts: "outside-only" });
    dom.window.MutationObserver = class { observe() {} disconnect() {} };
    dom.window.ResizeObserver = class { observe() {} disconnect() {} };
    dom.window.requestAnimationFrame = (cb) => 0;
    dom.window.cancelAnimationFrame = () => {};
    // The IIFE installs a setInterval poll; stub so it doesn't keep Node alive.
    dom.window.setInterval = () => 0;
    dom.window.clearInterval = () => {};

    dom.window.eval(ce.buildPickerStartJs());
    dom.window.__ifpPicked = "#chosen";
    const v = dom.window.eval(ce.buildPickerClearJs());
    assert.equal(v, "#chosen");
    assert.equal(dom.window.__ifpPicked, null);
});

// ============================================================
// CROP logging only on geometry change
// ============================================================

// A uPlot-shaped page (.u-wrap > canvas + .u-over). jsdom has no layout or
// 2D context, so the canvas/overlay rects and drawImage are stubbed; `rect`
// is mutable so a test can resize the canvas between ticks.
function runCanvasApply() {
    const dom = new JSDOM(
        "<!doctype html><html><body><div class='u-wrap'>" +
        "<canvas id='c' width='600' height='300'></canvas>" +
        "<div class='u-over'></div></div></body></html>",
        { runScripts: "outside-only" });
    const w = dom.window;
    const rect = { width: 600, height: 300 };
    w.HTMLCanvasElement.prototype.getContext = () => ({ drawImage() {} });
    const canvas = w.document.getElementById("c");
    canvas.getBoundingClientRect = () =>
        ({ left: 0, top: 0, width: rect.width, height: rect.height });
    w.document.querySelector(".u-over").getBoundingClientRect = () =>
        ({ left: 40, top: 0, width: rect.width - 40, height: rect.height - 20 });
    w.MutationObserver = class { observe() {} disconnect() {} };
    w.ResizeObserver = class { observe() {} disconnect() {} };
    w.requestAnimationFrame = (cb) => { cb(); return 0; };
    w.cancelAnimationFrame = () => {};
    w.setInterval = () => 0;
    w.clearInterval = () => {};
    const logs = [];
    w.console = { info: (m) => logs.push(String(m)), warn: () => {}, error: () => {} };
    const result = w.eval(`(${ce.buildApplyJs("#c")})`);
    const crops = () => logs.filter(l => l.indexOf("[ifp-thumb] CROP") !== -1);
    const tick = () => w.__ifpThumbSchedule();
    return { dom, rect, result, crops, tick };
}

test("CROP: logged once while the geometry stays the same", () => {
    const t = runCanvasApply();
    assert.equal(t.result, "matched-and-observing");
    t.tick();
    t.tick();
    t.tick();
    assert.equal(t.crops().length, 1, t.crops().join(" | "));
});

test("CROP: logged again when the canvas is resized", () => {
    const t = runCanvasApply();
    t.tick();
    t.rect.width = 500;
    t.tick();
    t.tick();
    assert.equal(t.crops().length, 2, t.crops().join(" | "));
});

test("CROP: a failed crop re-arms the log for the same geometry", () => {
    // QML heals a "blank" placeholder only on a CROP line. After a
    // canvas-pending (not painted yet) the next success must log even
    // though its geometry equals the last logged one.
    const t = runCanvasApply();
    assert.equal(t.crops().length, 1);
    t.rect.width = 0;                 // canvas not laid out → cropAxes fails
    t.tick();
    assert.equal(t.crops().length, 1);
    t.rect.width = 600;               // same geometry as the first CROP
    t.tick();
    assert.equal(t.crops().length, 2, t.crops().join(" | "));
});

test("CROP: a fresh apply (re-inject) logs its first crop", () => {
    const t = runCanvasApply();
    assert.equal(t.crops().length, 1);
    t.dom.window.eval(`(${ce.buildApplyJs("#c")})`);
    assert.equal(t.crops().length, 2, t.crops().join(" | "));
});

test("CROP: clear resets the remembered geometry", () => {
    const t = runCanvasApply();
    assert.ok(t.dom.window.__ifpLastCropKey);
    t.dom.window.eval(`(${ce.buildClearJs()})`);
    assert.equal(t.dom.window.__ifpLastCropKey, null);
});

// ============================================================
// Hidden page: keyword scan without animation frames (H1)
// ============================================================

// Chromium runs no rAF on a hidden page (a keyword-excluded thumbnail is
// invisible), so the 3 s interval must scan directly while hidden.
// rAF is stubbed to never fire; the interval callback is captured.
function runKeywordApply(hidden) {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>No active streams</div></body></html>",
        { runScripts: "outside-only" });
    const w = dom.window;
    Object.defineProperty(w.document, "hidden", { configurable: true, get: () => hidden.value });
    w.MutationObserver = class { observe() {} disconnect() {} };
    w.ResizeObserver = class { observe() {} disconnect() {} };
    let rafCalls = 0;
    w.requestAnimationFrame = () => { rafCalls++; return 7; };   // never fires
    w.cancelAnimationFrame = () => {};
    let intervalCb = null;
    w.setInterval = (cb) => { intervalCb = cb; return 1; };
    w.clearInterval = () => {};
    const logs = [];
    w.console = { info: (m) => logs.push(String(m)), warn: () => {}, error: () => {} };
    w.eval(`(${ce.buildApplyJs("#t", { keywords: ["No active streams"] })})`);
    return {
        w, logs,
        tickInterval: () => intervalCb(),
        rafCalls: () => rafCalls,
        kw: () => logs.filter(l => l.indexOf("[ifp-keyword]") !== -1),
    };
}

test("hidden page: interval scans keywords without rAF", () => {
    const hidden = { value: true };
    const t = runKeywordApply(hidden);
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true"]);
    t.w.document.getElementById("t").textContent = "Streaming now";
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true", "[ifp-keyword] hit=false"]);
    assert.equal(t.rafCalls(), 0, "hidden page must not queue animation frames");
});

test("visible page: interval still goes through rAF", () => {
    const hidden = { value: false };
    const t = runKeywordApply(hidden);
    t.tickInterval();
    assert.equal(t.rafCalls(), 1);
    assert.equal(t.kw().length, 0, "scan rides on the (stubbed, never-firing) rAF");
});

test("hidden page: an armed picker suppresses the scan", () => {
    const hidden = { value: true };
    const t = runKeywordApply(hidden);
    t.w.__ifpPickerArmed = true;
    t.tickInterval();
    assert.equal(t.kw().length, 0);
});

// ============================================================
// Fit mode: no self-retriggering (H2)
// ============================================================

// A wrapper MutationObserver stub that records takeRecords() calls, and a
// target whose intrinsic size / viewport are stubbed (jsdom has no layout).
function runFitApply() {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='wrap'><div id='t'>x</div></div></body></html>",
        { runScripts: "outside-only" });
    const w = dom.window;
    const size = { cw: 100, ch: 60, vw: 400, vh: 300 };
    const el = w.document.getElementById("t");
    Object.defineProperty(el, "scrollWidth", { get: () => size.cw });
    Object.defineProperty(el, "scrollHeight", { get: () => size.ch });
    Object.defineProperty(w, "innerWidth", { configurable: true, get: () => size.vw });
    Object.defineProperty(w, "innerHeight", { configurable: true, get: () => size.vh });
    let takeRecords = 0;
    w.MutationObserver = class { observe() {} disconnect() {} takeRecords() { takeRecords++; return []; } };
    w.ResizeObserver = class { observe() {} disconnect() {} };
    w.requestAnimationFrame = (cb) => { cb(); return 0; };
    w.cancelAnimationFrame = () => {};
    w.setInterval = () => 0;
    w.clearInterval = () => {};
    let resizes = 0;
    w.addEventListener("resize", () => { resizes++; });
    w.eval(`(${ce.buildApplyJs("#t", { scaleMode: "fit" })})`);
    return {
        w, el, size,
        tick: () => w.__ifpThumbSchedule(),
        resizes: () => resizes,
        takeRecords: () => takeRecords,
    };
}

test("fit: same scale re-applied does not dispatch resize again", () => {
    const t = runFitApply();
    assert.equal(t.el.style.transform, "scale(4)");   // min(400/100, 300/60)
    assert.equal(t.resizes(), 1);
    t.tick();   // installs the wrapper observer, re-applies
    t.tick();
    t.tick();
    assert.equal(t.el.style.transform, "scale(4)");
    assert.equal(t.resizes(), 1);
});

test("fit: a viewport change re-scales and dispatches resize once", () => {
    const t = runFitApply();
    t.tick();
    t.size.vw = 200;
    t.tick();
    t.tick();
    assert.equal(t.el.style.transform, "scale(2)");
    assert.equal(t.resizes(), 2);
});

test("fit: own style writes are dropped from the wrapper observer", () => {
    const t = runFitApply();
    t.tick();                       // wrapper observer now installed
    const before = t.takeRecords();
    t.tick();
    assert.ok(t.takeRecords() > before, "applyFitTransform must call takeRecords()");
});

test("fit: re-inject after teardown announces its scale again", () => {
    const t = runFitApply();
    assert.equal(t.resizes(), 1);
    t.w.eval(`(${ce.buildApplyJs("#t", { scaleMode: "fit" })})`);
    assert.equal(t.resizes(), 2);
});
