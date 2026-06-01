/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pins the metadata-vs-structural classifier used by main.qml's
 * onUrlsJsonChanged. A "metadata-only" change is safe to apply in
 * place to root.tabs[] — no Repeater rebuild, no WebEngineView
 * destruction, popup stays alive. A "structural" change (URL added,
 * removed, edited; profile reassigned) needs the rebuild path.
 *
 * The fix-bug is the entire reason this file exists: a metadata-only
 * Apply was rebuilding every WebTab/miniView and blanking the popup.
 * If any case here regresses we'd silently fall back to that.
 */
import QtQuick
import QtTest
import "../../package/contents/ui/UrlUtils.js" as U

TestCase {
    name: "MetadataDiff"

    function _tab(url, more) {
        const row = { url: url, authProfileId: "" };
        if (more) for (const k in more) row[k] = more[k];
        return row;
    }

    // ===== Defensive: bad inputs treated as structural ===============
    function test_bothNull_returnsFalse()      { compare(U.isMetadataOnlyTabsChange(null, null), false); }
    function test_oldNull_returnsFalse()       { compare(U.isMetadataOnlyTabsChange(null, []), false); }
    function test_newNull_returnsFalse()       { compare(U.isMetadataOnlyTabsChange([], null), false); }
    function test_bothUndefined_returnsFalse() { compare(U.isMetadataOnlyTabsChange(undefined, undefined), false); }
    function test_nonArray_returnsFalse()      { compare(U.isMetadataOnlyTabsChange("[]", "[]"), false); }

    // ===== Equal arrays =============================================
    function test_bothEmpty_isMetadataOnly() {
        // Two empty arrays: nothing differs. Conventionally a no-op
        // Apply; the urlsJson Connection skips reassigning anyway, but
        // confirm the classifier doesn't false-flag as structural.
        compare(U.isMetadataOnlyTabsChange([], []), true);
    }
    function test_identicalSingleRow_isMetadataOnly() {
        const tabs = [_tab("https://a/")];
        compare(U.isMetadataOnlyTabsChange(tabs, tabs), true);
    }
    function test_identicalManyRows_isMetadataOnly() {
        const tabs = [
            _tab("https://a/"), _tab("https://b/", { authProfileId: "p1" }),
            _tab("https://c/"), _tab("https://d/"),
        ];
        compare(U.isMetadataOnlyTabsChange(tabs, tabs), true);
    }

    // ===== Length differs → structural ==============================
    function test_oneAdded_isStructural() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/")],
            [_tab("https://a/"), _tab("https://b/")]), false);
    }
    function test_oneRemoved_isStructural() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/"), _tab("https://b/")],
            [_tab("https://a/")]), false);
    }

    // ===== URL changes → structural =================================
    function test_urlEdited_isStructural() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/"), _tab("https://b/")],
            [_tab("https://a/"), _tab("https://c/")]), false);
    }
    function test_urlQueryChanged_isStructural() {
        // Even a query-string tweak — the WebEngineView would have to
        // navigate, so it's not safely an in-place change.
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/?x=1")],
            [_tab("https://a/?x=2")]), false);
    }
    function test_rowsReordered_isStructural() {
        // Swap: row 0 was https://a/, row 1 was https://b/. After swap,
        // delegate at index 0 would need to switch profile/URL — that's
        // a structural change for the Repeater.
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/"), _tab("https://b/")],
            [_tab("https://b/"), _tab("https://a/")]), false);
    }
    function test_urlNullToString_isStructural() {
        // A row with no URL field at all (legacy import) vs same row
        // with a URL set — counted as structural so the rebuild path
        // re-runs parseTabs's safe-URL filter from scratch.
        compare(U.isMetadataOnlyTabsChange(
            [{ authProfileId: "" }],
            [_tab("https://a/")]), false);
    }

    // ===== authProfileId changes → structural =======================
    function test_profileIdEdited_isStructural() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/", { authProfileId: "p1" })],
            [_tab("https://a/", { authProfileId: "p2" })]), false);
    }
    function test_profileAddedToNone_isStructural() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/")],
            [_tab("https://a/", { authProfileId: "p1" })]), false);
    }
    function test_profileClearedToNone_isStructural() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/", { authProfileId: "p1" })],
            [_tab("https://a/")]), false);
    }

    // ===== Metadata-only changes → true =============================
    // These are the cases this whole feature exists to enable: edits
    // that should NOT blank the popup / rebuild thumbnails.
    function test_labelChanged_isMetadataOnly() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/", { label: "Old" })],
            [_tab("https://a/", { label: "New" })]), true);
    }
    function test_thumbModeChanged_isMetadataOnly() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/", { thumbMode: "chartOnly" })],
            [_tab("https://a/", { thumbMode: "custom" })]), true);
    }
    function test_thumbSelectorChanged_isMetadataOnly() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/", { thumbSelector: ".u-wrap" })],
            [_tab("https://a/", { thumbSelector: ".chart-panel" })]), true);
    }
    function test_thumbScaleModeChanged_isMetadataOnly() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/", { thumbScaleMode: "fit" })],
            [_tab("https://a/", { thumbScaleMode: "stretch" })]), true);
    }
    function test_thumbExcludeKeywordsAdded_isMetadataOnly() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/", { thumbExcludeKeywords: [] })],
            [_tab("https://a/", { thumbExcludeKeywords: ["No active streams"] })]), true);
    }
    function test_thumbShowLabelToggled_isMetadataOnly() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/", { thumbShowLabel: false })],
            [_tab("https://a/", { thumbShowLabel: true })]), true);
    }
    function test_popupModeChanged_isMetadataOnly() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/", { popupMode: "fullPanel" })],
            [_tab("https://a/", { popupMode: "custom" })]), true);
    }
    function test_popupSelectorChanged_isMetadataOnly() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/", { popupSelector: ".bg-card" })],
            [_tab("https://a/", { popupSelector: ".dashboard" })]), true);
    }
    function test_multipleMetadataFieldsAtOnce_isMetadataOnly() {
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/", { label: "Old", thumbScaleMode: "fit", thumbShowLabel: false })],
            [_tab("https://a/", { label: "New", thumbScaleMode: "stretch", thumbShowLabel: true })]),
            true);
    }

    // ===== Mixed: one row structural, another metadata-only → struct
    function test_oneRowStructuralAmongMetadata_isStructural() {
        // Row 0 URL changed (structural); row 1 only label changed
        // (metadata-only). Any structural row in the diff forces
        // structural overall.
        compare(U.isMetadataOnlyTabsChange(
            [_tab("https://a/"), _tab("https://b/", { label: "X" })],
            [_tab("https://changed/"), _tab("https://b/", { label: "Y" })]), false);
    }
}
