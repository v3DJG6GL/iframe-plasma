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

    // A first import changed urlsJson and was not applied; a second file
    // without urlsJson matches the persisted values. The page still differs
    // from disk (Apply stays enabled), so the banner must not say "nothing
    // to apply" — OK would then persist the first file's values unseen.
    function test_earlierUnappliedImport_stillChanged() {
        const persisted = { urlsJson: "[A]", zoomFactor: 100 };
        const out = B.importOutcome(persisted, { zoomFactor: 100 },
                                    { urlsJson: "[B]", zoomFactor: 100 });
        compare(out.changed, true);
        compare(out.adjusted, []);
    }

    function test_emptyImport_nothingChanged() {
        const out = B.importOutcome({ zoomFactor: 100 }, {}, { zoomFactor: 100 });
        compare(out.changed, false);
        compare(out.adjusted, []);
    }

    // ===== importBanner ==============================================
    // A flat or all-wrong-typed file: importFromFile skips every entry and
    // hands back an empty config. Nothing was read, so the banner must not
    // claim the file matches, and must not be a green success.
    function test_importBanner_everythingSkipped_unusableWarning() {
        const result = { ok: true, config: {}, skipped: ["urlsJson", "zoomFactor"],
                         error: "", warning: "" };
        const out = B.importBanner(result, B.importOutcome({ zoomFactor: 100 }, {},
                                                           { zoomFactor: 100 }));
        compare(out.headline, "unusable");
        compare(out.warning, true);
    }

    // A valid file that carries no settings at all ({"config":{}} or empty
    // groups): nothing skipped, nothing used. It matched nothing either.
    function test_importBanner_noSettings_unusableWarning() {
        const result = { ok: true, config: {}, skipped: [], error: "", warning: "" };
        const out = B.importBanner(result, B.importOutcome({ zoomFactor: 100 }, {},
                                                           { zoomFactor: 100 }));
        compare(out.headline, "unusable");
        compare(out.warning, true);
    }

    function test_importBanner_partlySkipped_warning() {
        const result = { ok: true, config: { zoomFactor: 150 }, skipped: ["futureKey"],
                         error: "", warning: "" };
        const out = B.importBanner(result, { changed: true, adjusted: [] });
        compare(out.headline, "changed");
        compare(out.warning, true);
    }

    function test_importBanner_cleanMatch_positive() {
        const result = { ok: true, config: { zoomFactor: 100 }, skipped: [],
                         error: "", warning: "" };
        const out = B.importBanner(result, { changed: false, adjusted: [] });
        compare(out.headline, "matches");
        compare(out.warning, false);
    }

    // An out-of-range value clamped back to the persisted one: nothing
    // changed and nothing was skipped, but the file's value was replaced,
    // so the banner must not be a green success.
    function test_importBanner_clampedToPersisted_warning() {
        const result = { ok: true, config: { zoomFactor: 9999 }, skipped: [],
                         error: "", warning: "" };
        const out = B.importBanner(result, B.importOutcome({ zoomFactor: 500 },
                                                           { zoomFactor: 9999 },
                                                           { zoomFactor: 500 }));
        compare(out.warning, true);
    }

    function test_importBanner_snapshotCaveat_warning() {
        const result = { ok: true, config: { zoomFactor: 150 }, skipped: [],
                         error: "", warning: "perms" };
        const out = B.importBanner(result, { changed: true, adjusted: [] });
        compare(out.headline, "changed");
        compare(out.warning, true);
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
