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
    assert.ok(js.startsWith("(function(sel){"));
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
