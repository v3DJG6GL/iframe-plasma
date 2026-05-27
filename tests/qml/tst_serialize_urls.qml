/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/RowSchema.js" as Schema

TestCase {
    name: "SerializeUrls"

    function _defaults() {
        return {
            label: "", url: "", authProfileId: "",
            thumbMode: "chartOnly", thumbSelector: "",
            thumbText: "", thumbIconName: "", thumbTimeRange: "",
            popupMode: "fullPanel", popupSelector: "",
        };
    }

    // ===== empty input -> default row ================================
    function test_emptyEntry_yieldsDefaultRow() {
        compare(Schema.normaliseTabRow({}), _defaults());
    }
    function test_nullEntry_yieldsDefaultRow() {
        compare(Schema.normaliseTabRow(null), _defaults());
    }
    function test_undefinedEntry_yieldsDefaultRow() {
        compare(Schema.normaliseTabRow(undefined), _defaults());
    }

    // ===== individual field round-trip ==============================
    function test_labelKept() {
        compare(Schema.normaliseTabRow({ label: "KDE" }).label, "KDE");
    }
    function test_urlKept() {
        compare(Schema.normaliseTabRow({ url: "https://x" }).url, "https://x");
    }
    function test_authProfileIdKept() {
        compare(Schema.normaliseTabRow({ authProfileId: "uuid-1" }).authProfileId, "uuid-1");
    }
    function test_thumbTextKept() {
        compare(Schema.normaliseTabRow({ thumbText: "TXT" }).thumbText, "TXT");
    }
    function test_thumbIconNameKept() {
        compare(Schema.normaliseTabRow({ thumbIconName: "bundled:cpu" }).thumbIconName,
                "bundled:cpu");
    }
    function test_thumbTimeRangeKept() {
        compare(Schema.normaliseTabRow({ thumbTimeRange: "7d" }).thumbTimeRange, "7d");
    }

    // ===== thumbMode enumeration =====================================
    function test_thumbMode_chartOnly()      { compare(Schema.normaliseTabRow({ thumbMode: "chartOnly" }).thumbMode, "chartOnly"); }
    function test_thumbMode_chartWithAxes()  { compare(Schema.normaliseTabRow({ thumbMode: "chartWithAxes" }).thumbMode, "chartWithAxes"); }
    function test_thumbMode_fullPanel()      { compare(Schema.normaliseTabRow({ thumbMode: "fullPanel" }).thumbMode, "fullPanel"); }
    function test_thumbMode_custom()         { compare(Schema.normaliseTabRow({ thumbMode: "custom" }).thumbMode, "custom"); }
    function test_thumbMode_text()           { compare(Schema.normaliseTabRow({ thumbMode: "text" }).thumbMode, "text"); }
    function test_thumbMode_icon()           { compare(Schema.normaliseTabRow({ thumbMode: "icon" }).thumbMode, "icon"); }
    function test_thumbMode_excluded()       { compare(Schema.normaliseTabRow({ thumbMode: "excluded" }).thumbMode, "excluded"); }

    // ===== thumbMode legacy inference ================================
    function test_thumbMode_missingSelectorEmpty_inferChartOnly() {
        compare(Schema.normaliseTabRow({}).thumbMode, "chartOnly");
    }
    function test_thumbMode_missingSelectorPresent_inferCustom() {
        const out = Schema.normaliseTabRow({ thumbSelector: ".u-wrap" });
        compare(out.thumbMode, "custom");
        compare(out.thumbSelector, ".u-wrap");
    }
    function test_thumbMode_modePresent_overridesSelectorInference() {
        // If both fields are set, the explicit mode wins.
        const out = Schema.normaliseTabRow({
            thumbMode: "chartOnly", thumbSelector: ".u-wrap",
        });
        compare(out.thumbMode, "chartOnly");
        compare(out.thumbSelector, ".u-wrap");
    }

    // ===== popupMode enumeration + legacy ============================
    function test_popupMode_fullPanel() {
        compare(Schema.normaliseTabRow({ popupMode: "fullPanel" }).popupMode, "fullPanel");
    }
    function test_popupMode_custom() {
        compare(Schema.normaliseTabRow({ popupMode: "custom" }).popupMode, "custom");
    }
    function test_popupMode_missingSelectorEmpty_inferFullPanel() {
        compare(Schema.normaliseTabRow({}).popupMode, "fullPanel");
    }
    function test_popupMode_missingSelectorPresent_inferCustom() {
        const out = Schema.normaliseTabRow({ popupSelector: "section.app" });
        compare(out.popupMode, "custom");
        compare(out.popupSelector, "section.app");
    }

    // ===== idempotence ==============================================
    function test_idempotent_doubleNormaliseUnchanged() {
        const once = Schema.normaliseTabRow({
            label: "L", url: "https://x", thumbMode: "custom",
            thumbSelector: ".u-wrap", popupMode: "fullPanel",
        });
        const twice = Schema.normaliseTabRow(once);
        compare(once, twice);
    }

    // ===== unknown fields ignored ===================================
    function test_unknownFieldsIgnored() {
        const out = Schema.normaliseTabRow({
            label: "L", garbage: 99, anotherUnknown: "x"
        });
        verify(!("garbage" in out));
        verify(!("anotherUnknown" in out));
        compare(out.label, "L");
    }

    // ===== load-time legacy-inference mutation must trigger re-persist
    //
    // Pins the invariant ConfigUrls.repopulate() relies on: when
    // normaliseTabRow infers thumbMode/popupMode from selector presence,
    // the rendered row's mode differs from the on-disk entry's missing
    // field. Without the re-persist gate, KCM displays "custom" but the
    // widget runtime falls back to chartOnly/fullPanel because
    // main.qml:520 / :2076 read `tab.thumbMode || ...` directly.
    function test_legacyInference_thumbMode_changesShape() {
        const entry = { url: "https://x", thumbSelector: ".u-wrap" };
        const row = Schema.normaliseTabRow(entry);
        compare(row.thumbMode, "custom");
        verify((entry.thumbMode || "") !== row.thumbMode);
    }
    function test_legacyInference_popupMode_changesShape() {
        const entry = { url: "https://x", popupSelector: "section.app" };
        const row = Schema.normaliseTabRow(entry);
        compare(row.popupMode, "custom");
        verify((entry.popupMode || "") !== row.popupMode);
    }
    function test_legacyInference_cleanRow_unchanged() {
        // Negative case — the repopulate gate must NOT fire on a row
        // whose modes are already canonical (else every load thrashes).
        const entry = {
            url: "https://x",
            thumbMode: "chartOnly", thumbSelector: "",
            popupMode: "fullPanel", popupSelector: "",
        };
        const row = Schema.normaliseTabRow(entry);
        compare((entry.thumbMode || ""), row.thumbMode);
        compare((entry.popupMode || ""), row.popupMode);
    }

    // ===== full round-trip JSON →→ array →→ ListModel-shape =========
    function test_fullJsonRoundtrip() {
        const json = '[{"label":"k","url":"https://k","thumbMode":"icon","thumbIconName":"cpu"},'
                   + '{"label":"x","url":"https://x","thumbSelector":".u-wrap"}]';
        const arr = JSON.parse(json);
        const rows = arr.map(Schema.normaliseTabRow);
        compare(rows.length, 2);
        compare(rows[0].thumbMode, "icon");
        compare(rows[0].thumbIconName, "cpu");
        compare(rows[1].thumbMode, "custom");      // inferred
        compare(rows[1].thumbSelector, ".u-wrap");
    }
}
