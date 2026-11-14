/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/BackupPage.js" as B

TestCase {
    name: "BackupPage"

    // ===== importOutcome =============================================
    function test_identicalImport_nothingChanged() {
        const live = { zoomFactor: 100, urlsJson: "[]", showTabBar: true };
        const out = B.importOutcome(live, { zoomFactor: 100, urlsJson: "[]", showTabBar: true }, live);
        compare(out.changed, false);
        compare(out.adjusted, []);
    }

    function test_plainChange_changedNotAdjusted() {
        const out = B.importOutcome({ zoomFactor: 100 }, { zoomFactor: 150 }, { zoomFactor: 150 });
        compare(out.changed, true);
        compare(out.adjusted, []);
    }

    // The zoom SpinBox tops out at 500. Importing 9999 over a live 500
    // stores 500 again: the page is not dirty, so the banner must not send
    // the user to a disabled Apply button, and the clamp must be reported.
    function test_clampedOntoLiveValue_adjustedButUnchanged() {
        const out = B.importOutcome({ zoomFactor: 500 }, { zoomFactor: 9999 }, { zoomFactor: 500 });
        compare(out.changed, false);
        compare(out.adjusted, ["zoomFactor"]);
    }

    function test_clampedToNewValue_adjustedAndChanged() {
        const out = B.importOutcome({ zoomFactor: 100 }, { zoomFactor: 3 }, { zoomFactor: 25 });
        compare(out.changed, true);
        compare(out.adjusted, ["zoomFactor"]);
    }

    function test_mixedKeys_eachJudgedOnItsOwn() {
        const before = { zoomFactor: 500, gcIntervalSec: 30, themeMode: "auto" };
        const wanted = { zoomFactor: 9999, gcIntervalSec: 900, themeMode: "auto" };
        const after  = { zoomFactor: 500, gcIntervalSec: 300, themeMode: "auto" };
        const out = B.importOutcome(before, wanted, after);
        compare(out.changed, true);
        compare(out.adjusted.slice().sort(), ["gcIntervalSec", "zoomFactor"]);
    }

    function test_keyNotHeldByPage_ignored() {
        const out = B.importOutcome({ zoomFactor: 100 }, { zoomFactor: 100, futureKey: 1 },
                                    { zoomFactor: 100 });
        compare(out.changed, false);
        compare(out.adjusted, []);
    }

    function test_emptyImport_nothingChanged() {
        const out = B.importOutcome({ zoomFactor: 100 }, {}, { zoomFactor: 100 });
        compare(out.changed, false);
        compare(out.adjusted, []);
    }

    // ===== exportFileUrl =============================================
    function test_exportFileUrl_nameIsThePathNotTheHost() {
        const name = "iframe-plasma-config-2026-05-27.json";
        const u = B.exportFileUrl("file:///home/u/Documents", name);
        compare(u, "file:///home/u/Documents/" + name);
        const parsed = new URL(u);
        compare(parsed.hostname, "");
        compare(parsed.pathname, "/home/u/Documents/" + name);
    }
    function test_exportFileUrl_data() {
        return [
            { tag: "trailingSlash", folder: "file:///home/u/Documents/", name: "a.json",
              want: "file:///home/u/Documents/a.json" },
            { tag: "rootFolder",    folder: "file:///",                  name: "a.json",
              want: "file:///a.json" },
            { tag: "nameEncoded",   folder: "file:///home/u",            name: "a b#1.json",
              want: "file:///home/u/a%20b%231.json" },
            { tag: "noFolder",      folder: "",                          name: "a.json",
              want: "" },
            { tag: "nullFolder",    folder: null,                        name: "a.json",
              want: "" },
        ];
    }
    function test_exportFileUrl(d) {
        compare(B.exportFileUrl(d.folder, d.name), d.want);
    }
}
