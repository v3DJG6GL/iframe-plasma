// SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for package/contents/ui/PageScripts.js. Loads the library the same
// way as cropengine.test.mjs, then runs the generated user-script source in
// a fake "page" sandbox with controllable timers and an optional `gc`.

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const LIB_PATH = path.join(__dirname, "..", "..", "package", "contents", "ui", "PageScripts.js");

function loadPageScripts() {
    const raw = fs.readFileSync(LIB_PATH, "utf8");
    const stripped = raw.replace(/^\.pragma library/m, "");
    const sandbox = { module: { exports: {} } };
    vm.runInNewContext(stripped + "\nmodule.exports = { gcWorkaroundSource, refreshControlSource };",
                       sandbox, { filename: "PageScripts.js" });
    return sandbox.module.exports;
}

const ps = loadPageScripts();

// A page context: window === global, manual timers, fixed Math.random,
// and `gc` only when withGc. Returns helpers to run scripts and fire timers.
function makePage({ withGc, random = 0.5 }) {
    const timeouts = [];
    const intervals = [];
    const page = {
        gcCalls: 0,
        setTimeout: (fn, ms) => { timeouts.push({ fn, ms }); return timeouts.length; },
        setInterval: (fn, ms) => { intervals.push({ fn, ms }); return intervals.length; },
        Math: Object.create(Math, { random: { value: () => random } }),
    };
    page.window = page;
    if (withGc) page.gc = () => { page.gcCalls++; };
    const ctx = vm.createContext(page);
    return {
        page, timeouts, intervals,
        run: (src) => vm.runInContext(src, ctx),
    };
}

test("gcWorkaroundSource: interval <= 0 disables the script", () => {
    assert.equal(ps.gcWorkaroundSource(0), "");
    assert.equal(ps.gcWorkaroundSource(-5), "");
    assert.equal(ps.gcWorkaroundSource(undefined), "");
});

test("gcWorkaroundSource: embeds the interval in milliseconds", () => {
    assert.match(ps.gcWorkaroundSource(20), /var ms = 20000;/);
});

test("with gc: first call after a random offset, then every interval", () => {
    const p = makePage({ withGc: true, random: 0.25 });
    p.run(ps.gcWorkaroundSource(20));
    assert.equal(p.page.__ifpGcArmed, true);
    assert.equal(p.timeouts.length, 1);
    assert.equal(p.timeouts[0].ms, 5000);          // 0.25 * 20000
    assert.equal(p.page.gcCalls, 0);

    p.timeouts[0].fn();
    assert.equal(p.page.gcCalls, 1);
    assert.equal(p.intervals.length, 1);
    assert.equal(p.intervals[0].ms, 20000);

    p.intervals[0].fn();
    p.intervals[0].fn();
    assert.equal(p.page.gcCalls, 3);
});

test("without gc (flag not set): no timers, no marker, no throw", () => {
    const p = makePage({ withGc: false });
    p.run(ps.gcWorkaroundSource(20));
    assert.equal(p.timeouts.length, 0);
    assert.equal(p.intervals.length, 0);
    assert.equal(p.page.__ifpGcArmed, undefined);
});

test("second injection into the same document is a no-op", () => {
    const p = makePage({ withGc: true });
    const src = ps.gcWorkaroundSource(20);
    p.run(src);
    p.run(src);
    assert.equal(p.timeouts.length, 1);
});

test("a page reassigning window.gc later cannot hijack the captured gc", () => {
    const p = makePage({ withGc: true, random: 0 });
    p.run(ps.gcWorkaroundSource(20));
    let hijacked = 0;
    p.page.gc = () => { hijacked++; };
    p.timeouts[0].fn();
    p.intervals[0].fn();
    assert.equal(hijacked, 0);
    assert.equal(p.page.gcCalls, 2);
});

test("an exception thrown by gc does not stop the interval", () => {
    const p = makePage({ withGc: true });
    p.page.gc = () => { p.page.gcCalls++; throw new Error("boom"); };
    // Re-arm with the throwing gc captured at injection time.
    p.run(ps.gcWorkaroundSource(20));
    assert.doesNotThrow(() => p.timeouts[0].fn());
    assert.doesNotThrow(() => p.intervals[0].fn());
    assert.equal(p.page.gcCalls, 2);
});

// A fresh document for the refresh-control script: `history` records the
// URL each pushState / replaceState call is handed.
function makeHistoryPage() {
    const urls = [];
    const page = {
        history: {
            replaceState(state, title, url) { urls.push(url); },
            pushState(state, title, url) { urls.push(url); },
        },
    };
    page.window = page;
    const ctx = vm.createContext(page);
    return { page, urls, run: (src) => vm.runInContext(src, ctx) };
}

test("refresh control, Off: a fresh document strips refresh= from history URLs", () => {
    // The document setRefreshInterval("off") navigates to starts with no
    // page-side flag; the choice has to arrive with the script itself.
    const p = makeHistoryPage();
    p.run(ps.refreshControlSource(true));
    p.page.history.replaceState(null, "", "/d/abc?orgId=1&refresh=5s");
    p.page.history.pushState(null, "", "/d/abc?refresh=5s&orgId=1");
    p.page.history.replaceState(null, "", "/d/abc?refresh=5s");
    assert.deepEqual(p.urls, ["/d/abc?orgId=1", "/d/abc?orgId=1", "/d/abc"]);
});

test("refresh control, not Off: history URLs pass through untouched", () => {
    const p = makeHistoryPage();
    p.run(ps.refreshControlSource(false));
    p.page.history.replaceState(null, "", "/d/abc?orgId=1&refresh=5s");
    assert.deepEqual(p.urls, ["/d/abc?orgId=1&refresh=5s"]);
});

test("refresh control: a later copy of the script sets the choice without re-patching", () => {
    const p = makeHistoryPage();
    p.run(ps.refreshControlSource(false));
    const patched = p.page.history.replaceState;
    p.run(ps.refreshControlSource(true));
    assert.equal(p.page.history.replaceState, patched);
    p.page.history.replaceState(null, "", "/d/abc?refresh=5s");
    assert.deepEqual(p.urls, ["/d/abc"]);
});
