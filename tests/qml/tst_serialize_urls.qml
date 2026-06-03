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
            label: "", url: "", enabled: true, authProfileId: "",
            thumbMode: "chartOnly", thumbSelector: "",
            thumbText: "", thumbIconName: "", thumbTimeRange: "",
            thumbScaleMode: "fit", thumbExcludeKeywords: [],
            thumbShowLabel: false,
            popupMode: "fullPanel", popupSelector: "",
        };
    }

    // ===== enabled: default-ON boolean ===============================
    // Mirror image of thumbShowLabel (default-OFF). A missing or non-false
    // value normalises to true so legacy rows / pre-field backups stay
    // visible; an explicit false is preserved both directions.
    function test_enabled_missingDefaultsTrue() {
        compare(Schema.normaliseTabRow({}).enabled, true);
    }
    function test_enabled_explicitFalseKept() {
        compare(Schema.normaliseTabRow({ enabled: false }).enabled, false);
    }
    function test_enabled_explicitTrueKept() {
        compare(Schema.normaliseTabRow({ enabled: true }).enabled, true);
    }
    function test_enabled_nonBoolNonFalseDefaultsTrue() {
        // Anything that isn't strictly `false` (e.g. a corrupt string)
        // normalises to enabled — only a real false hides the row.
        compare(Schema.normaliseTabRow({ enabled: "nope" }).enabled, true);
    }
    function test_enabled_serialiseFalseKept() {
        compare(Schema.serialiseTabRow({ enabled: false }).enabled, false);
    }
    function test_enabled_serialiseMissingDefaultsTrue() {
        compare(Schema.serialiseTabRow({}).enabled, true);
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

    // ===== thumbMode defaults ========================================
    function test_thumbMode_missingDefaultsChartOnly() {
        compare(Schema.normaliseTabRow({}).thumbMode, "chartOnly");
    }
    function test_thumbMode_selectorWithoutMode_defaultsChartOnly() {
        // A stray selector no longer promotes the row to "custom" — the
        // mode defaults to chartOnly while the selector is preserved.
        const out = Schema.normaliseTabRow({ thumbSelector: ".u-wrap" });
        compare(out.thumbMode, "chartOnly");
        compare(out.thumbSelector, ".u-wrap");
    }
    function test_thumbMode_explicitModeKept() {
        const out = Schema.normaliseTabRow({
            thumbMode: "custom", thumbSelector: ".u-wrap",
        });
        compare(out.thumbMode, "custom");
        compare(out.thumbSelector, ".u-wrap");
    }

    // ===== popupMode enumeration =====================================
    function test_popupMode_fullPanel() {
        compare(Schema.normaliseTabRow({ popupMode: "fullPanel" }).popupMode, "fullPanel");
    }
    function test_popupMode_custom() {
        compare(Schema.normaliseTabRow({ popupMode: "custom" }).popupMode, "custom");
    }
    function test_popupMode_missingDefaultsFullPanel() {
        compare(Schema.normaliseTabRow({}).popupMode, "fullPanel");
    }
    function test_popupMode_selectorWithoutMode_defaultsFullPanel() {
        const out = Schema.normaliseTabRow({ popupSelector: "section.app" });
        compare(out.popupMode, "fullPanel");
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

    // ===== canonical row is unchanged by normalisation ==============
    function test_canonicalRow_modesUnchanged() {
        const entry = {
            url: "https://x",
            thumbMode: "chartOnly", thumbSelector: "",
            popupMode: "fullPanel", popupSelector: "",
        };
        const row = Schema.normaliseTabRow(entry);
        compare(entry.thumbMode, row.thumbMode);
        compare(entry.popupMode, row.popupMode);
    }

    // ===== thumbIconName allow-list ==================================
    //
    // BackupBridge.importFromFile does not introspect urlsJson contents,
    // so an attacker-crafted backup can land arbitrary strings in this
    // field. Kirigami.Icon { source: "http://..." } actually issues an
    // outbound HTTP fetch via QQmlEngine::networkAccessManager — a
    // persistent beacon on every panel paint. normaliseTabRow MUST drop
    // anything that is not (empty | theme name | bundled:<safe> | file:///<path>).
    function test_iconName_emptyKept() {
        compare(Schema.normaliseTabRow({ thumbIconName: "" }).thumbIconName, "");
    }
    function test_iconName_themeNameKept() {
        compare(Schema.normaliseTabRow({ thumbIconName: "applications-internet" }).thumbIconName,
                "applications-internet");
    }
    function test_iconName_themeNameWithDotsKept() {
        compare(Schema.normaliseTabRow({ thumbIconName: "org.kde.plasma.foo" }).thumbIconName,
                "org.kde.plasma.foo");
    }
    function test_iconName_bundledKept() {
        compare(Schema.normaliseTabRow({ thumbIconName: "bundled:bell-ringing" }).thumbIconName,
                "bundled:bell-ringing");
    }
    function test_iconName_fileUrlKept() {
        compare(Schema.normaliseTabRow({ thumbIconName: "file:///home/op/icons/x.svg" }).thumbIconName,
                "file:///home/op/icons/x.svg");
    }
    function test_iconName_httpRejected() {
        compare(Schema.normaliseTabRow({ thumbIconName: "http://attacker.example/beacon.png" }).thumbIconName,
                "");
    }
    function test_iconName_httpsRejected() {
        compare(Schema.normaliseTabRow({ thumbIconName: "https://attacker.example/p?h=KIOSK" }).thumbIconName,
                "");
    }
    function test_iconName_dataUrlRejected() {
        compare(Schema.normaliseTabRow({ thumbIconName: "data:image/svg+xml;base64,PHN2Zy8+" }).thumbIconName,
                "");
    }
    function test_iconName_bundledTraversalRejected() {
        compare(Schema.normaliseTabRow({ thumbIconName: "bundled:../../../etc/passwd" }).thumbIconName,
                "");
    }
    function test_iconName_bundledSlashRejected() {
        compare(Schema.normaliseTabRow({ thumbIconName: "bundled:a/b" }).thumbIconName, "");
    }
    function test_iconName_fileUrlWithControlByteRejected() {
        compare(Schema.normaliseTabRow({ thumbIconName: "file:///tmp/a\nb.svg" }).thumbIconName, "");
    }
    function test_iconName_leadingDotRejected() {
        // FreeDesktop spec disallows; also blocks a stray "://" slipping past.
        compare(Schema.normaliseTabRow({ thumbIconName: ".hidden" }).thumbIconName, "");
    }

    // ===== thumbScaleMode enumeration + default =====================
    function test_scaleMode_default_isFit() {
        compare(Schema.normaliseTabRow({}).thumbScaleMode, "fit");
    }
    function test_scaleMode_fitKept() {
        compare(Schema.normaliseTabRow({ thumbScaleMode: "fit" }).thumbScaleMode, "fit");
    }
    function test_scaleMode_originalKept() {
        compare(Schema.normaliseTabRow({ thumbScaleMode: "original" }).thumbScaleMode, "original");
    }
    function test_scaleMode_stretchKept() {
        compare(Schema.normaliseTabRow({ thumbScaleMode: "stretch" }).thumbScaleMode, "stretch");
    }
    function test_scaleMode_unknownNormalisedToFit() {
        compare(Schema.normaliseTabRow({ thumbScaleMode: "junk" }).thumbScaleMode, "fit");
    }
    function test_scaleMode_nullNormalisedToFit() {
        compare(Schema.normaliseTabRow({ thumbScaleMode: null }).thumbScaleMode, "fit");
    }

    // ===== thumbExcludeKeywords normalisation ========================
    function test_keywords_default_isEmptyArray() {
        compare(Schema.normaliseTabRow({}).thumbExcludeKeywords, []);
    }
    function test_keywords_arrayKept() {
        compare(Schema.normaliseTabRow({ thumbExcludeKeywords: ["No data", "/Err/"] }).thumbExcludeKeywords,
                ["No data", "/Err/"]);
    }
    function test_keywords_nonArrayRejectedToEmpty() {
        // Only a real Array is accepted; a bare string (or any non-array)
        // normalises to [] rather than being wrapped into a single-element
        // list. ConfigUrls only ever stores a plain Array on disk.
        compare(Schema.normaliseTabRow({ thumbExcludeKeywords: "lone" }).thumbExcludeKeywords,
                []);
    }
    function test_keywords_emptyStringsFiltered() {
        compare(Schema.normaliseTabRow({ thumbExcludeKeywords: ["", "ok", "", null] }).thumbExcludeKeywords,
                ["ok"]);
    }
    function test_keywords_nonStringFiltered() {
        compare(Schema.normaliseTabRow({ thumbExcludeKeywords: [42, "ok", true] }).thumbExcludeKeywords,
                ["ok"]);
    }
    function test_keywords_null_isEmptyArray() {
        compare(Schema.normaliseTabRow({ thumbExcludeKeywords: null }).thumbExcludeKeywords, []);
    }

    // ===== thumbShowLabel ===========================================
    function test_showLabel_default_isFalse() {
        compare(Schema.normaliseTabRow({}).thumbShowLabel, false);
    }
    function test_showLabel_trueKept() {
        compare(Schema.normaliseTabRow({ thumbShowLabel: true }).thumbShowLabel, true);
    }
    function test_showLabel_falseKept() {
        compare(Schema.normaliseTabRow({ thumbShowLabel: false }).thumbShowLabel, false);
    }
    function test_showLabel_truthyNonBoolDropped() {
        // Defence: anything that isn't strictly === true normalises to
        // false so a malformed import can't smuggle a "1" string through.
        compare(Schema.normaliseTabRow({ thumbShowLabel: 1 }).thumbShowLabel, false);
        compare(Schema.normaliseTabRow({ thumbShowLabel: "true" }).thumbShowLabel, false);
        compare(Schema.normaliseTabRow({ thumbShowLabel: null }).thumbShowLabel, false);
    }
    function test_legacyHideLabelField_isStripped() {
        // The schema doesn't expose thumbHideLabel — a row that still
        // carries it (e.g. from a hand-edited or stale config) should
        // normalise to a row without the legacy key.
        const row = Schema.normaliseTabRow({ thumbHideLabel: true });
        verify(!("thumbHideLabel" in row),
               "thumbHideLabel should not survive normalisation");
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
        compare(rows[1].thumbMode, "chartOnly");   // default; selector kept
        compare(rows[1].thumbSelector, ".u-wrap");
    }

    // ===== serialise ↔ normalise parity (anti-drift guard) ==========
    //
    // ConfigUrls.serialize() delegates to Schema.serialiseTabRow so the
    // write path can never silently drop a field the read path produces
    // (the f831b02 class: three thumb* fields added to normaliseTabRow but
    // missing from serialize() for two commits → data loss on every save).
    // These pin all three to the same field set.
    function test_serialise_keySetMatchesNormalise() {
        const sKeys = Object.keys(Schema.serialiseTabRow({})).sort();
        const nKeys = Object.keys(Schema.normaliseTabRow({})).sort();
        compare(sKeys, nKeys);
    }
    function test_serialise_keySetMatchesTabFields() {
        const sKeys = Object.keys(Schema.serialiseTabRow({})).sort();
        compare(sKeys, Schema.TAB_FIELDS.slice().sort());
    }
    function test_serialise_normalise_roundTripIdempotent_data() {
        return [
            { tag: "empty",        x: {} },
            { tag: "fullyPopulated", x: {
                label: "L", url: "https://x", enabled: false, authProfileId: "uuid-1",
                thumbMode: "custom", thumbSelector: ".u-wrap",
                thumbText: "TXT", thumbIconName: "bundled:cpu",
                thumbTimeRange: "7d", thumbScaleMode: "original",
                thumbExcludeKeywords: ["a", "b"], thumbShowLabel: true,
                popupMode: "custom", popupSelector: "section.app",
            } },
            { tag: "disabledRow",  x: { enabled: false } },
            { tag: "junkScaleMode", x: { thumbScaleMode: "junk" } },
            { tag: "httpIcon",      x: { thumbIconName: "http://attacker/p?h=KIOSK" } },
            { tag: "dirtyKeywords", x: { thumbExcludeKeywords: ["", "ok", 42, null] } },
            { tag: "truthyShowLabel", x: { thumbShowLabel: 1 } },
        ];
    }
    function test_serialise_normalise_roundTripIdempotent(d) {
        // serialiseTabRow of an already-normalised row must equal that
        // normalised row — both funnel through the same sanitisers, so the
        // on-disk shape a save writes is exactly what a load would produce.
        const normalised = Schema.normaliseTabRow(d.x);
        compare(Schema.serialiseTabRow(normalised), normalised);
    }

    // ===== serialise re-applies the sanitisers (closed asymmetries) ==
    // The old hand-rolled serialize() passed thumbIconName/thumbScaleMode
    // through raw; delegating to serialiseTabRow re-runs the allow-lists on
    // write, matching normalise. These assert that hardening directly.
    function test_serialise_dropsBeaconIcon() {
        compare(Schema.serialiseTabRow({ thumbIconName: "http://attacker/x" }).thumbIconName, "");
    }
    function test_serialise_coercesJunkScaleMode() {
        compare(Schema.serialiseTabRow({ thumbScaleMode: "junk" }).thumbScaleMode, "fit");
    }
    function test_serialise_filtersKeywords() {
        compare(Schema.serialiseTabRow({ thumbExcludeKeywords: ["", "ok", 42] }).thumbExcludeKeywords,
                ["ok"]);
    }
    function test_serialise_strictBooleanShowLabel() {
        compare(Schema.serialiseTabRow({ thumbShowLabel: 1 }).thumbShowLabel, false);
        compare(Schema.serialiseTabRow({ thumbShowLabel: true }).thumbShowLabel, true);
    }
}
