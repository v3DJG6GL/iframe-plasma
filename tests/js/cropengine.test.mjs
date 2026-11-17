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
            buildPickerClearJs
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
    // The exact string main.qml's applyThumbCrop callback takes as "frame
    // confirmed" (ThumbRetryPolicy.isFrameConfirmed).
    assert.equal(result, "matched-and-observing");
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

test("apply: a body or html selector shows the whole page instead of blanking it", () => {
    // No child of <body> is an ancestor of <body>, so isolating it would
    // hide all of them and still report a match.
    for (const selector of ["body", "html"]) {
        const { dom, result } = runApply(
            "<!doctype html><html><body><header>a</header><main>b</main></body></html>",
            selector);
        const doc = dom.window.document;
        assert.equal(result, "matched-and-observing", selector);
        assert.equal(doc.documentElement.getAttribute("data-ifp-isolate"), null, selector);
        assert.equal(doc.querySelectorAll("[data-ifp-target]").length, 0, selector);
    }
});

test("apply: a first match inside <head> shows the whole page instead of blanking it", () => {
    // Isolating a <head> element would tag <head> and <html> as kept and
    // hide every child of <body>, while still reporting a match.
    for (const selector of ["title", "[href]", "meta"]) {
        const { dom, result } = runApply(
            "<!doctype html><html><head><meta charset='utf-8'><title>x</title>" +
            "<link rel='stylesheet' href='a.css'></head>" +
            "<body><div id='a' href='x'>hello</div></body></html>",
            selector);
        const doc = dom.window.document;
        assert.equal(result, "matched-and-observing", selector);
        assert.equal(doc.documentElement.getAttribute("data-ifp-isolate"), null, selector);
        assert.equal(doc.querySelectorAll("[data-ifp-keep], [data-ifp-target]").length, 0, selector);
    }
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

test("miss: a former target still in the page is no longer pinned to the viewport", () => {
    // The selector stops matching while its old element stays in the DOM
    // (the class moved away). "Showing full page" must then be true.
    for (const scaleMode of ["stretch", "fit", "original"]) {
        const dom = new JSDOM(
            "<!doctype html><html><body><div><div id='t' class='a on'>x</div></div><p>rest</p></body></html>",
            { runScripts: "outside-only" });
        const w = dom.window;
        w.MutationObserver = class { observe() {} disconnect() {} takeRecords() { return []; } };
        w.ResizeObserver = class { observe() {} disconnect() {} };
        w.requestAnimationFrame = (cb) => { cb(); return 0; };
        w.cancelAnimationFrame = () => {};
        w.setInterval = () => 0;
        w.clearInterval = () => {};
        w.console = { info: () => {}, warn: () => {}, error: () => {} };
        const el = w.document.getElementById("t");

        w.eval(`(${ce.buildApplyJs(".a.on", { scaleMode })})`);
        assert.equal(w.getComputedStyle(el).position, "fixed", scaleMode);

        el.classList.remove("on");
        w.__ifpThumbSchedule();
        assert.notEqual(w.getComputedStyle(el).position, "fixed", scaleMode);

        // The crop comes back when the selector matches again.
        el.classList.add("on");
        w.__ifpThumbSchedule();
        assert.equal(w.getComputedStyle(el).position, "fixed", scaleMode);
    }
});

test("isolate: a transformed kept ancestor does not become the target's containing block", () => {
    // react-grid-layout positions its cards with transform; a transformed
    // ancestor would pin the fixed target to the card instead of the viewport.
    for (const scaleMode of ["stretch", "fit", "original"]) {
        const dom = new JSDOM(
            "<!doctype html><html><head><style>" +
            ".card{position:absolute;transform:translate(200px,150px);filter:blur(1px);" +
            "contain:paint;will-change:transform;perspective:100px;overflow:hidden}" +
            "</style></head><body><div id='card' class='card'><div id='t'>x</div></div></body></html>",
            { runScripts: "outside-only" });
        const w = dom.window;
        w.MutationObserver = class { observe() {} disconnect() {} takeRecords() { return []; } };
        w.ResizeObserver = class { observe() {} disconnect() {} };
        w.requestAnimationFrame = (cb) => { cb(); return 0; };
        w.cancelAnimationFrame = () => {};
        w.setInterval = () => 0;
        w.clearInterval = () => {};
        w.console = { info: () => {}, warn: () => {}, error: () => {} };
        const card = w.document.getElementById("card");

        w.eval(`(${ce.buildApplyJs("#t", { scaleMode })})`);
        assert.equal(card.getAttribute("data-ifp-keep"), "1", scaleMode);
        const cs = w.getComputedStyle(card);
        assert.equal(cs.transform, "none", scaleMode);
        assert.equal(cs.filter, "none", scaleMode);
        assert.equal(cs.contain, "none", scaleMode);
        assert.equal(cs.willChange, "auto", scaleMode);
        assert.equal(cs.perspective, "none", scaleMode);

        // Without isolation the page's own styles apply again.
        w.eval(ce.buildClearJs());
        assert.notEqual(w.getComputedStyle(card).transform, "none", scaleMode);
    }
});

test("isolate: a kept ancestor's individual transform, preserve-3d and content-visibility are released too", () => {
    // Tailwind v4's translate-*/rotate-*/scale-* utilities write these
    // properties rather than `transform`; each one, like preserve-3d and
    // content-visibility:auto, makes the ancestor the fixed target's
    // containing block.
    for (const scaleMode of ["stretch", "fit", "original"]) {
        const dom = new JSDOM(
            "<!doctype html><html><head><style>" +
            ".card{position:absolute;translate:200px 150px;rotate:1deg;scale:1.1;" +
            "transform-style:preserve-3d;content-visibility:auto;overflow:hidden}" +
            "</style></head><body><div id='card' class='card'><div id='t'>x</div></div></body></html>",
            { runScripts: "outside-only" });
        const w = dom.window;
        w.MutationObserver = class { observe() {} disconnect() {} takeRecords() { return []; } };
        w.ResizeObserver = class { observe() {} disconnect() {} };
        w.requestAnimationFrame = (cb) => { cb(); return 0; };
        w.cancelAnimationFrame = () => {};
        w.setInterval = () => 0;
        w.clearInterval = () => {};
        w.console = { info: () => {}, warn: () => {}, error: () => {} };
        const card = w.document.getElementById("card");

        w.eval(`(${ce.buildApplyJs("#t", { scaleMode })})`);
        assert.equal(card.getAttribute("data-ifp-keep"), "1", scaleMode);
        const cs = w.getComputedStyle(card);
        assert.equal(cs.translate, "none", scaleMode);
        assert.equal(cs.rotate, "none", scaleMode);
        assert.equal(cs.scale, "none", scaleMode);
        assert.equal(cs.transformStyle, "flat", scaleMode);
        assert.equal(cs.contentVisibility, "visible", scaleMode);

        w.eval(ce.buildClearJs());
        assert.notEqual(w.getComputedStyle(card).translate, "none", scaleMode);
    }
});

test("isolate: a kept ancestor's clip-path and mask do not clip the target", () => {
    // Chromium clips even a fixed descendant to an ancestor's clip-path or
    // mask, so the crop would show only the ancestor's original box.
    for (const scaleMode of ["stretch", "fit", "original"]) {
        const dom = new JSDOM(
            "<!doctype html><html><head><style>" +
            ".card{clip-path:inset(0);mask:linear-gradient(black,black);overflow:hidden}" +
            "</style></head><body><div id='card' class='card'><div id='t'>x</div></div></body></html>",
            { runScripts: "outside-only" });
        const w = dom.window;
        w.MutationObserver = class { observe() {} disconnect() {} takeRecords() { return []; } };
        w.ResizeObserver = class { observe() {} disconnect() {} };
        w.requestAnimationFrame = (cb) => { cb(); return 0; };
        w.cancelAnimationFrame = () => {};
        w.setInterval = () => 0;
        w.clearInterval = () => {};
        w.console = { info: () => {}, warn: () => {}, error: () => {} };
        const card = w.document.getElementById("card");

        w.eval(`(${ce.buildApplyJs("#t", { scaleMode })})`);
        assert.equal(card.getAttribute("data-ifp-keep"), "1", scaleMode);
        const cs = w.getComputedStyle(card);
        // jsdom neither expands the mask shorthand into mask-image nor parses
        // -webkit-mask, so the shorthand is what can be checked here.
        assert.equal(cs.getPropertyValue("clip-path"), "none", scaleMode);
        assert.equal(cs.getPropertyValue("mask"), "none", scaleMode);

        w.eval(ce.buildClearJs());
        assert.notEqual(w.getComputedStyle(card).getPropertyValue("clip-path"), "none", scaleMode);
    }
});

test("isolate: the target's own transform does not shift it off the viewport", () => {
    // translate(-50%,-50%) centering, or a grid item placed by translate.
    for (const scaleMode of ["stretch", "fit", "original"]) {
        const dom = new JSDOM(
            "<!doctype html><html><head><style>" +
            ".t{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);" +
            "translate:10px 5px;rotate:1deg;scale:1.1}" +
            "</style></head><body><div><div id='t' class='t'>x</div></div></body></html>",
            { runScripts: "outside-only" });
        const w = dom.window;
        w.MutationObserver = class { observe() {} disconnect() {} takeRecords() { return []; } };
        w.ResizeObserver = class { observe() {} disconnect() {} };
        w.requestAnimationFrame = (cb) => { cb(); return 0; };
        w.cancelAnimationFrame = () => {};
        w.setInterval = () => 0;
        w.clearInterval = () => {};
        w.console = { info: () => {}, warn: () => {}, error: () => {} };
        // jsdom has no layout; content larger than the viewport keeps fit
        // mode at its natural size (no inline scale).
        Object.defineProperty(w.Element.prototype, "scrollWidth", { configurable: true, get: () => 5000 });
        Object.defineProperty(w.Element.prototype, "scrollHeight", { configurable: true, get: () => 5000 });
        const el = w.document.getElementById("t");

        w.eval(`(${ce.buildApplyJs("#t", { scaleMode })})`);
        const cs = w.getComputedStyle(el);
        assert.equal(cs.translate, "none", scaleMode);
        assert.equal(cs.rotate, "none", scaleMode);
        assert.equal(cs.scale, "none", scaleMode);
        // Fit mode owns `transform` inline (scale, or 'none' at natural size).
        if (scaleMode === "fit") assert.equal(el.style.transform, "none", scaleMode);
        else assert.equal(cs.transform, "none", scaleMode);

        w.eval(ce.buildClearJs());
        assert.notEqual(w.getComputedStyle(el).transform, "none", scaleMode);
        assert.equal(el.style.transform, "", scaleMode);
    }
});

test("fit: at natural size the page's inline transform is neutralised, and restored on clear", () => {
    // Content larger than the viewport: s <= 1, no scale written.
    const t = runFitApply("transform:translate(400px, 500px)");
    t.size.cw = 800;
    t.size.ch = 600;
    t.tick();
    assert.equal(t.el.style.transform, "none");
    t.tick();
    assert.equal(t.el.style.transform, "none");
    t.w.eval(ce.buildClearJs());
    assert.equal(t.el.style.transform, "translate(400px, 500px)");
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

test("apply: a match that moves up to an ancestor shows that ancestor's children", () => {
    // The new target was kept as the old target's ancestor; a leftover keep
    // marker on it would hide all of its children.
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='a'><div id='mid'><div id='d' class='sel'>x</div></div>" +
        "<div id='sib'>y</div></div></body></html>",
        { runScripts: "outside-only" });
    const w = dom.window;
    w.MutationObserver = class { observe() {} disconnect() {} };
    w.ResizeObserver = class { observe() {} disconnect() {} };
    w.requestAnimationFrame = (cb) => { cb(); return 0; };
    w.cancelAnimationFrame = () => {};
    w.setInterval = () => 0;
    w.clearInterval = () => {};
    w.console = { info: () => {}, warn: () => {}, error: () => {} };
    const doc = w.document;
    w.eval(`(${ce.buildApplyJs(".sel")})`);
    assert.equal(doc.getElementById("a").getAttribute("data-ifp-keep"), "1");

    doc.getElementById("a").classList.add("sel");   // now the first match
    w.__ifpThumbSchedule();
    const a = doc.getElementById("a");
    assert.equal(a.getAttribute("data-ifp-target"), "1");
    assert.equal(a.getAttribute("data-ifp-keep"), null);
    assert.notEqual(w.getComputedStyle(doc.getElementById("mid")).display, "none");
    assert.notEqual(w.getComputedStyle(doc.getElementById("sib")).display, "none");
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

test("observers: a replaced match disconnects the previous ResizeObserver", () => {
    // A re-mounted target gets a new parent observer; the old one must not
    // stay alive, or it re-applies the old selector after a clear.
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='a'><div id='t'>x</div></div><div id='b'></div></body></html>",
        { runScripts: "outside-only" });
    const w = dom.window;
    w.MutationObserver = class { observe() {} disconnect() {} };
    const resizeObservers = [];
    w.ResizeObserver = class {
        constructor() { this.disconnected = false; resizeObservers.push(this); }
        observe() {}
        disconnect() { this.disconnected = true; }
    };
    w.requestAnimationFrame = (cb) => { cb(); return 0; };
    w.cancelAnimationFrame = () => {};
    w.setInterval = () => 0;
    w.clearInterval = () => {};
    w.console = { info: () => {}, warn: () => {}, error: () => {} };

    w.eval(`(${ce.buildApplyJs("#t")})`);
    w.__ifpThumbSchedule();
    assert.equal(resizeObservers.length, 1);

    // The page re-mounts the target under another parent.
    w.document.getElementById("t").remove();
    w.document.getElementById("b").innerHTML = "<div id='t'>y</div>";
    w.__ifpThumbSchedule();
    assert.equal(resizeObservers.length, 2);
    assert.equal(resizeObservers[0].disconnected, true,
        "the first ResizeObserver must be disconnected when the match moves");

    w.eval(ce.buildClearJs());
    assert.deepEqual(resizeObservers.map(o => o.disconnected), [true, true]);
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

test("keyword scan: regex with the d or v flag is compiled as a regex", () => {
    // Chromium accepts d (indices) and v (unicodeSets); such an entry must
    // not degrade to the literal substring "/offline/v", which never matches.
    for (const kw of ["/offline/v", "/Offline/di"]) {
        const dom = new JSDOM(
            "<!doctype html><html><body><div id='t'>Stream offline</div></body></html>",
            { runScripts: "outside-only" });
        const w = dom.window;
        w.MutationObserver = class { observe() {} disconnect() {} };
        w.ResizeObserver = class { observe() {} disconnect() {} };
        w.requestAnimationFrame = (cb) => { cb(); return 0; };
        w.cancelAnimationFrame = () => {};
        w.setInterval = () => 0;
        w.clearInterval = () => {};
        const logs = [];
        w.console = { info: (m) => logs.push(String(m)), warn: () => {}, error: () => {} };
        w.eval(`(${ce.buildApplyJs("#t", { keywords: [kw] })})`);
        w.__ifpThumbSchedule();
        const kwLogs = logs.filter(l => l.indexOf("[ifp-keyword]") !== -1);
        assert.deepEqual(kwLogs, ["[ifp-keyword] hit=true"], kw);
    }
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

test("keyword scan: the engine's own miss banner is not scanned", () => {
    // With no match the scan reads <body>; the banner says "selector
    // '.error-box' not found", which must not count as page text.
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>everything fine</div></body></html>",
        { runScripts: "outside-only" });
    const w = dom.window;
    w.MutationObserver = class { observe() {} disconnect() {} };
    w.ResizeObserver = class { observe() {} disconnect() {} };
    w.requestAnimationFrame = (cb) => { cb(); return 0; };
    w.cancelAnimationFrame = () => {};
    w.setInterval = () => 0;
    w.clearInterval = () => {};
    const logs = [];
    w.console = { info: (m) => logs.push(String(m)), warn: () => {}, error: () => {} };
    w.eval(`(${ce.buildApplyJs(".error-box", { keywords: ["not found", "error"] })})`);
    for (let i = 0; i < 12; i++) w.__ifpThumbSchedule();
    assert.ok(w.document.getElementById("ifp-miss-banner"), "banner is shown after a sustained miss");
    const kwLogs = logs.filter(l => l.indexOf("[ifp-keyword]") !== -1);
    assert.deepEqual(kwLogs, ["[ifp-keyword] hit=false"]);
});

test("keyword scan: an empty selector scans the page without cropping it", () => {
    // Full-page thumbnails have no selector but can carry exclude keywords.
    const dom = new JSDOM(
        "<!doctype html><html><body><header>Camera</header><main>Stream offline</main></body></html>",
        { runScripts: "outside-only" });
    const w = dom.window;
    w.MutationObserver = class { observe() {} disconnect() {} };
    w.ResizeObserver = class { observe() {} disconnect() {} };
    w.requestAnimationFrame = (cb) => { cb(); return 0; };
    w.cancelAnimationFrame = () => {};
    w.setInterval = () => 0;
    w.clearInterval = () => {};
    const logs = [];
    w.console = { info: (m) => logs.push(String(m)), warn: () => {}, error: () => {} };
    const result = w.eval(`(${ce.buildApplyJs("", { keywords: ["offline"] })})`);
    assert.equal(result, "observing");
    for (let i = 0; i < 12; i++) w.__ifpThumbSchedule();
    const kwLogs = logs.filter(l => l.indexOf("[ifp-keyword]") !== -1);
    assert.deepEqual(kwLogs, ["[ifp-keyword] hit=true"]);
    const doc = w.document;
    assert.equal(doc.documentElement.getAttribute("data-ifp-isolate"), null);
    assert.equal(doc.getElementById("ifp-miss-banner"), null, "no selector, so nothing was missed");

    // The keyword going away is reported the same way.
    doc.querySelector("main").textContent = "Stream live";
    w.__ifpThumbSchedule();
    assert.equal(logs[logs.length - 1], "[ifp-keyword] hit=false");
});

test("keyword scan: an invalid selector still scans the page", () => {
    // A selector typo must not switch keyword exclusion off: the scan falls
    // back to <body>, and QML still hears 'invalid'.
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='t'>No active streams</div></body></html>",
        { runScripts: "outside-only" });
    const w = dom.window;
    w.MutationObserver = class { observe() {} disconnect() {} };
    w.ResizeObserver = class { observe() {} disconnect() {} };
    w.requestAnimationFrame = (cb) => { cb(); return 0; };
    w.cancelAnimationFrame = () => {};
    let intervalCb = null;
    w.setInterval = (cb) => { intervalCb = cb; return 1; };
    w.clearInterval = () => {};
    const logs = [];
    w.console = { info: (m) => logs.push(String(m)), warn: () => {}, error: () => {} };
    const result = w.eval(`(${ce.buildApplyJs("#t >", { keywords: ["No active streams"] })})`);
    assert.equal(result, "invalid");
    assert.equal(typeof intervalCb, "function", "the poll must be installed");
    intervalCb();
    const kw = () => logs.filter(l => l.indexOf("[ifp-keyword]") !== -1);
    assert.deepEqual(kw(), ["[ifp-keyword] hit=true"]);
    w.document.getElementById("t").textContent = "Streaming now";
    intervalCb();
    assert.deepEqual(kw(), ["[ifp-keyword] hit=true", "[ifp-keyword] hit=false"]);
    assert.equal(w.document.getElementById("ifp-miss-banner"), null);
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

// Starts the picker on a page. jsdom has no layout, so elementFromPoint is
// stubbed: pointAt(el) sets the element under the cursor. Timers are
// captured so a test can run them (and none outlives the test).
function runPicker(html) {
    const dom = new JSDOM(html, { runScripts: "outside-only" });
    const w = dom.window;
    w.MutationObserver = class { observe() {} disconnect() {} };
    w.ResizeObserver = class { observe() {} disconnect() {} };
    w.requestAnimationFrame = (cb) => 0;
    w.cancelAnimationFrame = () => {};
    w.setInterval = () => 0;
    w.clearInterval = () => {};
    const timers = [];
    w.setTimeout = (cb) => { timers.push(cb); return timers.length; };
    w.clearTimeout = () => {};
    w.console = { info: () => {}, warn: () => {}, error: () => {} };
    let under = null;
    w.document.elementFromPoint = () => under;
    w.eval(ce.buildPickerStartJs());
    return {
        w,
        doc: w.document,
        pointAt: (el) => { under = el; },
        fire: (el, type) => el.dispatchEvent(
            new w.MouseEvent(type, { bubbles: true, cancelable: true })),
        runTimers: () => { while (timers.length) timers.shift()(); },
    };
}

test("picker: the outline follows a hovered element that moved", () => {
    const p = runPicker("<!doctype html><html><body><div id='big'>x</div><div id='o'>y</div></body></html>");
    const big = p.doc.getElementById("big");
    let top = 100;
    big.getBoundingClientRect = () => ({ left: 0, top, width: 50, height: 40 });
    const outline = p.doc.getElementById("__ifpPickerOutline");
    p.pointAt(big);
    p.fire(big, "mousemove");
    assert.equal(outline.style.top, "100px");
    // The page re-lays the element out; the pointer stays on it.
    top = -200;
    p.fire(big, "mousemove");
    assert.equal(outline.style.top, "-200px");
    // A scroll under a still pointer sends no mousemove.
    top = 50;
    big.dispatchEvent(new p.w.Event("scroll"));
    assert.equal(outline.style.top, "50px");
    // ...and may bring another element under the pointer.
    const o = p.doc.getElementById("o");
    o.getBoundingClientRect = () => ({ left: 0, top: 7, width: 50, height: 40 });
    p.pointAt(o);
    p.doc.dispatchEvent(new p.w.Event("scroll"));
    assert.equal(outline.style.top, "7px");
});

test("picker: the rest of the picking gesture does not reach the page", () => {
    // The pick is taken on pointerdown; the click of the same gesture must
    // not then activate the picked button or link.
    const p = runPicker("<!doctype html><html><body><button id='go'>go</button></body></html>");
    const button = p.doc.getElementById("go");
    const seen = [];
    for (const type of ["pointerup", "mouseup", "click"]) {
        button.addEventListener(type, () => seen.push(type));
    }
    const gesture = ["pointerdown", "mousedown", "pointerup", "mouseup", "click"];
    p.pointAt(button);
    for (const type of gesture) p.fire(button, type);
    assert.equal(p.w.__ifpPicked, "#go");
    assert.deepEqual(seen, []);

    // The next gesture belongs to the page again.
    for (const type of gesture) p.fire(button, type);
    assert.deepEqual(seen, ["pointerup", "mouseup", "click"]);
});

test("picker: a middle or right picking press does not reach the page either", () => {
    // A middle press ends in auxclick (Chromium opens a link in a new window
    // on it), a right press also fires contextmenu; neither ever fires click.
    const gestures = {
        middle: ["pointerdown", "mousedown", "pointerup", "mouseup", "auxclick"],
        right: ["pointerdown", "mousedown", "contextmenu", "pointerup", "mouseup", "auxclick"],
    };
    for (const [name, gesture] of Object.entries(gestures)) {
        const p = runPicker("<!doctype html><html><body><a id='lnk' href='#x'>go</a></body></html>");
        const link = p.doc.getElementById("lnk");
        const seen = [];
        for (const type of ["pointerup", "mouseup", "auxclick", "contextmenu"]) {
            link.addEventListener(type, () => seen.push(type));
        }
        p.pointAt(link);
        for (const type of gesture) p.fire(link, type);
        assert.equal(p.w.__ifpPicked, "#lnk", name);
        assert.deepEqual(seen, [], name);

        // The swallow ended with the gesture: the next one reaches the page.
        p.fire(link, "auxclick");
        assert.deepEqual(seen, ["auxclick"], name);
    }
});

test("picker: a pick whose click never comes does not eat a later click", () => {
    const p = runPicker("<!doctype html><html><body><button id='go'>go</button></body></html>");
    const button = p.doc.getElementById("go");
    let clicks = 0;
    button.addEventListener("click", () => { clicks++; });
    p.pointAt(button);
    p.fire(button, "pointerdown");      // pressed, then released outside the view
    assert.equal(p.w.__ifpPicked, "#go");
    p.runTimers();
    p.fire(button, "click");            // e.g. keyboard activation, no press first
    assert.equal(clicks, 1);
});

// The crop side uses the first match of the saved selector, so the
// structural fallback (no usable id / test id / class) must match the
// picked element alone.
test("picker: the structural fallback is unique among identical subtrees", () => {
    const card = "<div><div><div><section><p>x</p></section></div></div></div>";
    const p = runPicker(`<!doctype html><html><body>${card}${card}</body></html>`);
    const target = p.doc.querySelectorAll("p")[1];
    p.pointAt(target);
    p.fire(target, "pointerdown");
    const picked = p.w.__ifpPicked;
    assert.equal(p.doc.querySelectorAll(picked).length, 1, picked);
    assert.equal(p.doc.querySelector(picked), target, picked);
});

test("picker: the structural fallback does not anchor on a duplicated id", () => {
    const p = runPicker(
        "<!doctype html><html><body>" +
        "<div id='dup'><span>a</span></div><div id='dup'><span>b</span></div>" +
        "</body></html>");
    const target = p.doc.querySelectorAll("span")[1];
    p.pointAt(target);
    p.fire(target, "pointerdown");
    const picked = p.w.__ifpPicked;
    assert.equal(p.doc.querySelectorAll(picked).length, 1, picked);
    assert.equal(p.doc.querySelector(picked), target, picked);
});

test("picker: the structural fallback anchors on a unique ancestor id", () => {
    const p = runPicker(
        "<!doctype html><html><body><ul><li>x</li></ul>" +
        "<div id='panel'><ul><li>a</li><li>b</li></ul></div></body></html>");
    const target = p.doc.querySelectorAll("#panel li")[1];
    p.pointAt(target);
    p.fire(target, "pointerdown");
    assert.equal(p.w.__ifpPicked, "#panel > ul > li:nth-of-type(2)");
    assert.equal(p.doc.querySelector(p.w.__ifpPicked), target);
});

test("picker: the structural fallback keeps the case of SVG element names", () => {
    // Labels inside <foreignObject> (Mermaid, D3); 'foreignobject' would
    // not match the SVG element.
    const node = "<svg><foreignObject><div><span>a</span></div></foreignObject></svg>";
    const p = runPicker(`<!doctype html><html><body>${node}${node}</body></html>`);
    const target = p.doc.querySelectorAll("span")[1];
    p.pointAt(target);
    p.fire(target, "pointerdown");
    const picked = p.w.__ifpPicked;
    assert.match(picked, /foreignObject/, picked);
    assert.equal(p.doc.querySelectorAll(picked).length, 1, picked);
    assert.equal(p.doc.querySelector(picked), target, picked);
});

test("picker: picking <body> yields 'body', not a cancel", () => {
    const p = runPicker("<!doctype html><html><body><p>x</p></body></html>");
    p.pointAt(p.doc.body);
    p.fire(p.doc.body, "pointerdown");
    assert.equal(p.w.__ifpPicked, "body");
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

test("CROP: the overlay goes away when the canvas disappears", () => {
    // The overlay holds the last frame over the whole viewport; left in
    // place after a miss it shows a frozen chart instead of the page.
    const t = runCanvasApply();
    const doc = t.dom.window.document;
    assert.ok(doc.getElementById("ifp-thumb-display"));
    doc.querySelector(".u-wrap").remove();
    t.tick();
    assert.equal(doc.getElementById("ifp-thumb-display"), null);
    assert.equal(doc.documentElement.getAttribute("data-ifp-thumb"), null);
});

test("CROP: the overlay goes away while the canvas has no frame", () => {
    const t = runCanvasApply();
    const doc = t.dom.window.document;
    t.rect.width = 0;                 // canvas-pending
    t.tick();
    assert.equal(doc.getElementById("ifp-thumb-display"), null);
    t.rect.width = 600;
    t.tick();
    assert.ok(doc.getElementById("ifp-thumb-display"), "a new frame brings it back");
    assert.equal(t.crops().length, 2, t.crops().join(" | "));
});

test("apply: a canvas that is not uPlot's is isolated, not left pending", () => {
    // Chart.js / ECharts / map canvases have no .u-over to blit from; the
    // pixel-blit path can never succeed for them.
    const { dom, result } = runApply(
        "<!doctype html><html><body><div class='card'><canvas id='myChart'></canvas></div><p>rest</p></body></html>",
        "#myChart");
    const doc = dom.window.document;
    assert.equal(result, "matched-and-observing");
    assert.equal(doc.getElementById("myChart").getAttribute("data-ifp-target"), "1");
    assert.equal(doc.querySelector(".card").getAttribute("data-ifp-keep"), "1");
    assert.equal(doc.documentElement.getAttribute("data-ifp-isolate"), "1");
    assert.equal(doc.getElementById("ifp-thumb-display"), null);
});

// One selector (".x") whose match the page swaps between a painted uPlot
// canvas and a plain element. Every uPlot part gets a laid-out rect.
function runSwapApply(html) {
    const dom = new JSDOM(html, { runScripts: "outside-only" });
    const w = dom.window;
    w.HTMLCanvasElement.prototype.getContext = () => ({ drawImage() {} });
    w.Element.prototype.getBoundingClientRect = function () {
        return { left: 0, top: 0, width: 600, height: 300 };
    };
    w.MutationObserver = class { observe() {} disconnect() {} takeRecords() { return []; } };
    w.ResizeObserver = class { observe() {} disconnect() {} };
    w.requestAnimationFrame = (cb) => { cb(); return 0; };
    w.cancelAnimationFrame = () => {};
    w.setInterval = () => 0;
    w.clearInterval = () => {};
    w.console = { info: () => {}, warn: () => {}, error: () => {} };
    w.eval(`(${ce.buildApplyJs(".x")})`);
    return { w, doc: w.document, tick: () => w.__ifpThumbSchedule() };
}
const UPLOT_X = "<div class='u-wrap'><canvas class='x' width='600' height='300'></canvas><div class='u-over'></div></div>";

test("swap: a canvas match replaced by an element drops the canvas overlay", () => {
    const t = runSwapApply(`<!doctype html><html><body><div id='panel'>${UPLOT_X}</div></body></html>`);
    assert.ok(t.doc.getElementById("ifp-thumb-display"));
    assert.equal(t.doc.documentElement.getAttribute("data-ifp-thumb"), "1");
    t.doc.getElementById("panel").innerHTML = "<div class='x'>No data</div>";
    t.tick();
    assert.equal(t.doc.getElementById("ifp-thumb-display"), null, "no frozen frame over the element");
    assert.equal(t.doc.documentElement.getAttribute("data-ifp-thumb"), null);
    assert.equal(t.doc.documentElement.getAttribute("data-ifp-isolate"), "1");
});

test("swap: an element match replaced by a canvas drops the isolation", () => {
    const t = runSwapApply("<!doctype html><html><body><div id='panel'><div class='x'>No data</div></div></body></html>");
    assert.equal(t.doc.documentElement.getAttribute("data-ifp-isolate"), "1");
    t.doc.getElementById("panel").innerHTML = UPLOT_X;
    t.tick();
    // The isolation rules would hide the overlay (a <body> child that is
    // neither kept nor the target) and leave a blank view.
    assert.equal(t.doc.documentElement.getAttribute("data-ifp-isolate"), null);
    assert.equal(t.doc.documentElement.getAttribute("data-ifp-thumb"), "1");
    const disp = t.doc.getElementById("ifp-thumb-display");
    assert.ok(disp);
    assert.notEqual(t.w.getComputedStyle(disp).display, "none");
});

test("swap: a canvas match that moves to <body> drops the canvas overlay", () => {
    // <body> comes first in document order, so the page putting the class
    // on it makes the same selector match the whole page.
    const t = runSwapApply(`<!doctype html><html><body><div id='panel'>${UPLOT_X}</div></body></html>`);
    assert.ok(t.doc.getElementById("ifp-thumb-display"));
    t.doc.body.classList.add("x");
    t.tick();
    assert.equal(t.doc.getElementById("ifp-thumb-display"), null, "no frozen frame over the page");
    assert.equal(t.doc.documentElement.getAttribute("data-ifp-thumb"), null);
    assert.equal(t.w.__ifpLastCropKey, null);
});

test("swap: an element match that moves to <body> drops the isolation", () => {
    for (const scaleMode of ["stretch", "fit", "original"]) {
        const dom = new JSDOM(
            "<!doctype html><html><body><div><div id='t' class='x' style='width:7px'>x</div></div><p>rest</p></body></html>",
            { runScripts: "outside-only" });
        const w = dom.window;
        w.MutationObserver = class { observe() {} disconnect() {} takeRecords() { return []; } };
        w.ResizeObserver = class { observe() {} disconnect() {} };
        w.requestAnimationFrame = (cb) => { cb(); return 0; };
        w.cancelAnimationFrame = () => {};
        w.setInterval = () => 0;
        w.clearInterval = () => {};
        w.console = { info: () => {}, warn: () => {}, error: () => {} };
        // jsdom has no layout; give fit mode a size to scale.
        Object.defineProperty(w.Element.prototype, "scrollWidth", { configurable: true, get: () => 100 });
        Object.defineProperty(w.Element.prototype, "scrollHeight", { configurable: true, get: () => 50 });
        const el = w.document.getElementById("t");

        w.eval(`(${ce.buildApplyJs(".x", { scaleMode })})`);
        assert.equal(w.getComputedStyle(el).position, "fixed", scaleMode);
        if (scaleMode === "fit") assert.match(el.style.transform, /^scale\(/);

        w.document.body.classList.add("x");
        w.__ifpThumbSchedule();
        const doc = w.document;
        assert.equal(doc.documentElement.getAttribute("data-ifp-isolate"), null, scaleMode);
        assert.notEqual(w.getComputedStyle(el).position, "fixed", scaleMode);
        assert.notEqual(w.getComputedStyle(doc.querySelector("p")).display, "none", scaleMode);
        assert.equal(w.__ifpFitTarget || null, null, scaleMode);
        assert.equal(el.style.transform, "", scaleMode);
        assert.equal(el.style.width, "7px", scaleMode);
    }
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
function runKeywordApply(hidden,
                         html = "<div id='t'>No active streams</div>",
                         selector = "#t", keywords = ["No active streams"]) {
    const dom = new JSDOM(
        `<!doctype html><html><body>${html}</body></html>`,
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
    w.eval(`(${ce.buildApplyJs(selector, { keywords })})`);
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

test("hidden page: a re-mounted target is scanned instead of the detached node", () => {
    // An SPA usually ends an "offline" state by replacing the node, not by
    // editing its text; the scan must not keep reading the old one.
    const hidden = { value: true };
    const t = runKeywordApply(hidden);
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true"]);
    t.w.document.body.innerHTML = "<div id='t'>Streaming now</div>";
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true", "[ifp-keyword] hit=false"]);
    assert.equal(t.rafCalls(), 0, "hidden page must not queue animation frames");
});

test("hidden page: a match that moves to a still-connected sibling is scanned", () => {
    // An SPA moves a status class from one node to another; the old node
    // stays in the page, but the selector now picks the sibling.
    const hidden = { value: true };
    const t = runKeywordApply(hidden,
        "<p id='a' class='alert'>OFFLINE</p><div id='b'>fine</div>", ".alert", ["offline"]);
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true"]);
    t.w.document.getElementById("a").classList.remove("alert");
    t.w.document.getElementById("b").classList.add("alert");
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true", "[ifp-keyword] hit=false"]);
    assert.equal(t.rafCalls(), 0, "hidden page must not queue animation frames");
});

test("hidden page: a removed target falls back to scanning the body", () => {
    const hidden = { value: true };
    const t = runKeywordApply(hidden);
    t.tickInterval();
    t.w.document.body.innerHTML = "<p>Streaming now</p>";
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true", "[ifp-keyword] hit=false"]);
});

test("hidden page: a target that comes back is scanned again", () => {
    // One tick without the target must not leave the scan on <body> for
    // good: another panel there may carry the keyword.
    const hidden = { value: true };
    const t = runKeywordApply(hidden);
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true"]);
    t.w.document.body.innerHTML = "<p>No active streams</p>";
    t.tickInterval();
    t.w.document.body.innerHTML = "<div id='t'>Streaming now</div><p>No active streams</p>";
    t.tickInterval();
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true", "[ifp-keyword] hit=false"]);
});

test("hidden page: a pending uPlot canvas scans the body, as apply() does", () => {
    // jsdom lays nothing out, so the canvas is 0x0 and its crop stays
    // pending; apply() then scans <body>, and the hidden tick must too.
    const hidden = { value: true };
    const t = runKeywordApply(hidden,
        "<div class='u-wrap'><canvas id='c'></canvas><div class='u-over'></div></div>" +
        "<p>Datasource error</p>", "#c", ["datasource error"]);
    t.tickInterval();
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true"]);
});

// jsdom has no innerText; Chromium's leaves out what is not rendered, which
// is what makes a stale isolation hide the rest of the page from the scan.
// On an element that is itself not rendered it returns textContent, as
// Blink does, hidden descendants included.
function emulateInnerText(w) {
    const rendered = (n) => {
        if (n.nodeType === 3) return n.data;
        if (n.nodeType !== 1 || w.getComputedStyle(n).display === "none") return "";
        return Array.from(n.childNodes).map(rendered).join("");
    };
    const isRendered = (el) => {
        for (let n = el; n && n.nodeType === 1; n = n.parentElement)
            if (w.getComputedStyle(n).display === "none") return false;
        return true;
    };
    Object.defineProperty(w.HTMLElement.prototype, "innerText", {
        configurable: true,
        get() { return isRendered(this) ? rendered(this) : this.textContent; } });
}

test("hidden page: a selector that stops matching drops the isolation before scanning the body", () => {
    const hidden = { value: true };
    const t = runKeywordApply(hidden,
        "<p id='a' class='alert'>fine</p><div id='b'>OFFLINE</div>", ".alert", ["offline"]);
    emulateInnerText(t.w);
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=false"]);
    // The class goes away while the tab is hidden; nothing matches now.
    t.w.document.getElementById("a").classList.remove("alert");
    t.tickInterval();
    assert.equal(t.w.document.documentElement.getAttribute("data-ifp-isolate"), null);
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=false", "[ifp-keyword] hit=true"]);
    assert.equal(t.rafCalls(), 0, "hidden page must not queue animation frames");
});

test("hidden page: a match that moves to a kept ancestor is isolated before the scan", () => {
    // The old target's isolation would hide the ancestor's other children,
    // so the scan would read only the old target's text.
    const hidden = { value: true };
    const t = runKeywordApply(hidden,
        "<div id='card'><span id='a' class='s'>fine</span><p>OFFLINE</p></div>", ".s", ["offline"]);
    emulateInnerText(t.w);
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=false"]);
    t.w.document.getElementById("a").classList.remove("s");
    t.w.document.getElementById("card").classList.add("s");
    t.tickInterval();
    assert.equal(t.w.document.getElementById("card").getAttribute("data-ifp-target"), "1");
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=false", "[ifp-keyword] hit=true"]);
    assert.equal(t.rafCalls(), 0, "hidden page must not queue animation frames");
});

test("hidden page: a re-mounted target's CSS-hidden text does not match", () => {
    // The stale isolation hides the new node, and innerText on a node that
    // is not rendered reads all of its text, CSS-hidden parts included.
    const hidden = { value: true };
    const t = runKeywordApply(hidden,
        "<div id='root'><div id='t'>Offline</div></div>", "#t", ["offline"]);
    emulateInnerText(t.w);
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true"]);
    t.w.document.getElementById("root").innerHTML =
        "<div id='t'>Online <span style='display:none'>Offline</span></div>";
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true", "[ifp-keyword] hit=false"]);
    assert.equal(t.rafCalls(), 0, "hidden page must not queue animation frames");
});

test("hidden page: a first match that moves into <head> scans the body", () => {
    // As apply(): a <head> element shows nothing, so the whole page counts.
    const hidden = { value: true };
    const t = runKeywordApply(hidden, "<div class='s'>OFFLINE</div>", ".s", ["offline"]);
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true"]);
    const meta = t.w.document.createElement("meta");
    meta.className = "s";
    t.w.document.head.appendChild(meta);
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true"]);
    assert.equal(t.w.document.documentElement.getAttribute("data-ifp-isolate"), null);
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
// Keyword scan: aria-labels follow innerText's visibility rule
// ============================================================

// jsdom has no checkVisibility; Chromium's returns false for a node that
// is display:none itself or sits under one.
function emulateCheckVisibility(w) {
    w.Element.prototype.checkVisibility = function () {
        for (let n = this; n && n.nodeType === 1; n = n.parentElement)
            if (w.getComputedStyle(n).display === "none") return false;
        return true;
    };
}

test("keyword scan: a display:none node's aria-label does not match", () => {
    const hidden = { value: true };
    const t = runKeywordApply(hidden,
        "<div id='t'><p>All systems nominal</p>" +
        "<div style='display:none'><span aria-label='Stream offline'></span></div></div>",
        "#t", ["offline"]);
    emulateCheckVisibility(t.w);
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=false"]);
});

test("keyword scan: a rendered node's aria-label still matches", () => {
    const hidden = { value: true };
    const t = runKeywordApply(hidden,
        "<div id='t'><span aria-label='Stream offline'></span></div>", "#t", ["offline"]);
    emulateCheckVisibility(t.w);
    t.tickInterval();
    assert.deepEqual(t.kw(), ["[ifp-keyword] hit=true"]);
});

// ============================================================
// Fit mode: no self-retriggering (H2)
// ============================================================

// A wrapper MutationObserver stub that records takeRecords() calls, and a
// target whose intrinsic size / viewport are stubbed (jsdom has no layout).
function runFitApply(targetStyle = "") {
    const dom = new JSDOM(
        "<!doctype html><html><body><div id='wrap'>" +
        `<div id='t' style='${targetStyle}'>x</div></div></body></html>`,
        { runScripts: "outside-only" });
    const w = dom.window;
    const size = { cw: 100, ch: 60, vw: 400, vh: 300 };
    const el = w.document.getElementById("t");
    // On the prototype, so an element a test adds later is measurable too.
    Object.defineProperty(w.Element.prototype, "scrollWidth", { configurable: true, get: () => size.cw });
    Object.defineProperty(w.Element.prototype, "scrollHeight", { configurable: true, get: () => size.ch });
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

test("fit: clear puts the page's own inline styles back", () => {
    // A grid item positioned by its own inline transform/width/height must
    // not lose them when the crop is removed.
    const t = runFitApply("width:300px;height:200px;transform:translate(10px, 20px)");
    assert.equal(t.el.style.transform, "scale(4)");
    t.tick();
    t.w.eval(ce.buildClearJs());
    assert.equal(t.el.style.width, "300px");
    assert.equal(t.el.style.height, "200px");
    assert.equal(t.el.style.transform, "translate(10px, 20px)");
    assert.equal(t.el.style.transformOrigin, "");
});

test("fit: inline styles the page rewrites during the crop are what a clear puts back", () => {
    // react-grid-layout moves and resizes its item on a container resize
    // while it is cropped; the first-seen values are stale from then on.
    const t = runFitApply("width:300px;height:200px;transform:translate(10px, 20px)");
    t.tick();
    assert.equal(t.el.style.transform, "scale(4)");
    t.el.style.width = "500px";
    t.el.style.height = "250px";
    t.el.style.transform = "translate(40px, 80px)";
    // The re-apply measures the page's new box, not the old one.
    const measured = [];
    Object.defineProperty(t.el, "scrollWidth", { configurable: true,
        get() { measured.push(this.style.width); return t.size.cw; } });
    t.tick();
    assert.deepEqual(measured, ["500px"]);
    assert.equal(t.el.style.transform, "scale(4)");
    t.w.eval(ce.buildClearJs());
    assert.equal(t.el.style.width, "500px");
    assert.equal(t.el.style.height, "250px");
    assert.equal(t.el.style.transform, "translate(40px, 80px)");
    assert.equal(t.el.style.transformOrigin, "");
});

test("fit: a page rewrite just before a clear is kept too", () => {
    const t = runFitApply("width:300px;height:200px;transform:translate(10px, 20px)");
    t.tick();
    t.el.style.transform = "translate(40px, 80px)";
    t.w.eval(ce.buildClearJs());
    assert.equal(t.el.style.transform, "translate(40px, 80px)");
    // Properties the page left alone get their original values back.
    assert.equal(t.el.style.width, "300px");
    assert.equal(t.el.style.height, "200px");
});

test("fit: a match that moves to another element un-scales the old one", () => {
    const t = runFitApply();
    t.tick();
    assert.equal(t.el.style.transform, "scale(4)");
    // The selector now resolves to a new element; the old one stays in the DOM.
    const doc = t.w.document;
    t.el.removeAttribute("id");
    const next = doc.createElement("div");
    next.id = "t";
    doc.getElementById("wrap").insertBefore(next, t.el);
    t.tick();
    assert.equal(next.style.transform, "scale(4)");
    assert.equal(t.el.style.transform, "");
    assert.equal(t.el.style.width, "");
    assert.equal(t.el.style.height, "");
    // ...and stays un-scaled after a clear.
    t.w.eval(ce.buildClearJs());
    assert.equal(t.el.style.transform, "");
    assert.equal(next.style.transform, "");
});

test("fit: a selector miss un-scales the former target", () => {
    const t = runFitApply();
    t.tick();
    assert.equal(t.el.style.transform, "scale(4)");
    t.el.id = "renamed";          // still in the DOM, no longer matched
    t.tick();
    assert.equal(t.el.style.transform, "");
    assert.equal(t.el.style.width, "");
    assert.equal(t.el.style.height, "");
    t.el.id = "t";
    t.tick();
    assert.equal(t.el.style.transform, "scale(4)");
});
