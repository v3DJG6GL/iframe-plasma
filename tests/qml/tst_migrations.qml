/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/Migrations.js" as M

TestCase {
    name: "Migrations"

    // Deterministic UUID generator for legacy-auth tests.
    property int _uuidSeq: 0
    function _gen() { _uuidSeq = _uuidSeq + 1; return "uuid-" + _uuidSeq; }
    function init() { _uuidSeq = 0; }

    // =============================================================
    //  1. preemptMigration
    // =============================================================
    function test_preempt_emptyProfiles_noChange() {
        const out = M.preemptMigration("[]", false);
        compare(out.mutated, false);
        compare(out.error, null);
        compare(out.json, "[]");
    }

    function test_preempt_malformedJson_returnsError() {
        const out = M.preemptMigration("{not json", false);
        verify(out.error !== null);
        compare(out.mutated, false);
    }

    function test_preempt_nonArrayJson_treatedAsEmpty() {
        const out = M.preemptMigration('{"id":"x"}', false);
        compare(out.mutated, false);
    }

    function test_preempt_basic_globalOff_assignsFalse() {
        const out = M.preemptMigration('[{"id":"a","authType":"basic"}]', false);
        const profiles = JSON.parse(out.json);
        compare(out.mutated, true);
        compare(profiles[0].preempt, false);
    }

    function test_preempt_basic_globalOn_assignsTrue() {
        const out = M.preemptMigration('[{"id":"a","authType":"basic"}]', true);
        const profiles = JSON.parse(out.json);
        compare(profiles[0].preempt, true);
    }

    function test_preempt_bearer_alwaysTrue_evenIfGlobalOff() {
        const out = M.preemptMigration('[{"id":"b","authType":"bearer"}]', false);
        const profiles = JSON.parse(out.json);
        compare(profiles[0].preempt, true);
    }

    function test_preempt_raw_alwaysTrue() {
        const out = M.preemptMigration('[{"id":"r","authType":"raw"}]', false);
        const profiles = JSON.parse(out.json);
        compare(profiles[0].preempt, true);
    }

    function test_preempt_none_alwaysFalse() {
        const out = M.preemptMigration('[{"id":"n","authType":"none"}]', true);
        const profiles = JSON.parse(out.json);
        compare(profiles[0].preempt, false);
    }

    function test_preempt_unknownType_assignsFalse() {
        const out = M.preemptMigration('[{"id":"x","authType":"oauth"}]', true);
        const profiles = JSON.parse(out.json);
        compare(profiles[0].preempt, false);
    }

    function test_preempt_explicitFieldPreserved() {
        const out = M.preemptMigration('[{"id":"a","authType":"basic","preempt":true}]', false);
        compare(out.mutated, false);
        const profiles = JSON.parse(out.json);
        compare(profiles[0].preempt, true);
    }

    function test_preempt_idempotent_secondRunNoMutation() {
        const first = M.preemptMigration(
            '[{"id":"a","authType":"basic"},{"id":"b","authType":"bearer"}]', true);
        compare(first.mutated, true);
        const second = M.preemptMigration(first.json, true);
        compare(second.mutated, false);
        compare(second.json, first.json);
    }

    function test_preempt_mixedProfiles_persistedExactlyOnce() {
        const out = M.preemptMigration(
            '[{"id":"a","authType":"basic"},{"id":"b","authType":"bearer"},'
          + '{"id":"c","authType":"raw","preempt":false}]', true);
        compare(out.mutated, true);
        const ps = JSON.parse(out.json);
        compare(ps[0].preempt, true);    // basic+globalOn → true
        compare(ps[1].preempt, true);    // bearer → always true
        compare(ps[2].preempt, false);   // raw explicit false respected
    }

    // =============================================================
    //  2. compactPreviewMigration
    // =============================================================
    function test_compact_autoMode_noOp() {
        const out = M.compactPreviewMigration("[]", "auto", 0);
        compare(out.skipped, true);
        compare(out.mutated, false);
        compare(out.json, null);
    }

    function test_compact_undefinedMode_treatedAsAuto() {
        const out = M.compactPreviewMigration("[]", undefined, 0);
        compare(out.skipped, true);
    }

    function test_compact_emptyTabs_outOfRangeSkipped() {
        const out = M.compactPreviewMigration("[]", "fixed", 0);
        compare(out.skipped, true);
        compare(out.mutated, false);
        verify(out.reason.indexOf("out-of-range") >= 0);
    }

    function test_compact_negativePinned_skipped() {
        const out = M.compactPreviewMigration(
            '[{"url":"https://a"},{"url":"https://b"}]', "fixed", -1);
        compare(out.skipped, true);
    }

    function test_compact_pinnedBeyondLength_skipped() {
        const out = M.compactPreviewMigration(
            '[{"url":"https://a"}]', "fixed", 5);
        compare(out.skipped, true);
    }

    function test_compact_nonIntegerPinned_skipped() {
        const out = M.compactPreviewMigration(
            '[{"url":"https://a"}]', "fixed", 0.5);
        compare(out.skipped, true);
    }

    function test_compact_singleTabPinned_isNoOp() {
        // With only the pinned tab present, nothing is marked excluded.
        const out = M.compactPreviewMigration(
            '[{"url":"https://a"}]', "fixed", 0);
        compare(out.skipped, false);
        compare(out.mutated, false);
    }

    function test_compact_fixedMode_marksAllOthersExcluded() {
        const out = M.compactPreviewMigration(
            '[{"url":"https://a"},{"url":"https://b"},{"url":"https://c"},{"url":"https://d"}]',
            "fixed", 2);
        compare(out.skipped, false);
        compare(out.mutated, true);
        const tabs = JSON.parse(out.json);
        compare(tabs[0].thumbMode, "excluded");
        compare(tabs[1].thumbMode, "excluded");
        verify(tabs[2].thumbMode !== "excluded");
        compare(tabs[3].thumbMode, "excluded");
    }

    function test_compact_skipsAlreadyExcluded() {
        // Tabs already marked excluded don't get re-flagged (mutated still
        // true because the OTHER non-excluded ones get flipped).
        const out = M.compactPreviewMigration(
            '[{"thumbMode":"excluded","url":"https://a"},{"url":"https://b"},{"url":"https://c"}]',
            "fixed", 1);
        compare(out.mutated, true);
        const tabs = JSON.parse(out.json);
        compare(tabs[0].thumbMode, "excluded");
        verify(tabs[1].thumbMode !== "excluded");
        compare(tabs[2].thumbMode, "excluded");
    }

    function test_compact_idempotent() {
        const first = M.compactPreviewMigration(
            '[{"url":"https://a"},{"url":"https://b"}]', "fixed", 1);
        compare(first.mutated, true);
        const second = M.compactPreviewMigration(first.json, "fixed", 1);
        compare(second.mutated, false);
    }

    function test_compact_malformedUrlsJson_skipped() {
        const out = M.compactPreviewMigration("{not json", "fixed", 0);
        compare(out.skipped, true);
        verify(out.reason.indexOf("parse error") >= 0);
    }

    // =============================================================
    //  3. legacyAuthMigration
    // =============================================================
    function test_legacy_emptyTabs_noChange() {
        const out = M.legacyAuthMigration("[]", "[]", "", null, _gen);
        compare(out.mutated, false);
        compare(out.walletWrites.length, 0);
    }

    function test_legacy_tabAlreadyMigrated_skipped() {
        const out = M.legacyAuthMigration(
            '[{"url":"https://a","authProfileId":"existing"}]',
            '[{"id":"existing","authType":"basic"}]',
            "", null, _gen);
        compare(out.mutated, false);
        compare(out.walletWrites.length, 0);
    }

    function test_legacy_basicUserPlaintext_createsProfileAndWalletWrite() {
        const out = M.legacyAuthMigration(
            '[{"url":"https://a.example.com/","basicAuthUser":"alice","basicAuthPasswordPlaintext":"p"}]',
            "[]", "auth.example.com", null, _gen);
        compare(out.mutated, true);
        const tabs = JSON.parse(out.urlsJson);
        compare(tabs[0].authProfileId, "uuid-1");
        verify(!("basicAuthUser" in tabs[0]));
        verify(!("basicAuthPasswordPlaintext" in tabs[0]));
        const profiles = JSON.parse(out.profilesJson);
        compare(profiles[0].id, "uuid-1");
        compare(profiles[0].authType, "basic");
        compare(profiles[0].username, "alice");
        compare(profiles[0].autheliaHost, "auth.example.com");
        compare(out.walletWrites.length, 1);
        compare(out.walletWrites[0].key, "profile:uuid-1");
        compare(out.walletWrites[0].map.password, "p");
    }

    function test_legacy_rawAuthHeader_createsRawProfile() {
        const out = M.legacyAuthMigration(
            '[{"url":"https://x","rawAuthHeader":"Bearer eyJ0"}]',
            "[]", "", null, _gen);
        compare(out.mutated, true);
        const profiles = JSON.parse(out.profilesJson);
        compare(profiles[0].authType, "raw");
        compare(out.walletWrites[0].map.rawHeader, "Bearer eyJ0");
        verify(!("password" in out.walletWrites[0].map));
    }

    function test_legacy_dedupesByHostAndUser() {
        // Two tabs same host+user → one profile created.
        const out = M.legacyAuthMigration(
            '[{"url":"https://a.com/p1","basicAuthUser":"u","basicAuthPasswordPlaintext":"p"},'
          + ' {"url":"https://a.com/p2","basicAuthUser":"u","basicAuthPasswordPlaintext":"p"}]',
            "[]", "", null, _gen);
        const profiles = JSON.parse(out.profilesJson);
        compare(profiles.length, 1);
        compare(out.walletWrites.length, 1);
        const tabs = JSON.parse(out.urlsJson);
        compare(tabs[0].authProfileId, tabs[1].authProfileId);
    }

    function test_legacy_differentUsers_createTwoProfiles() {
        const out = M.legacyAuthMigration(
            '[{"url":"https://a.com/","basicAuthUser":"u1","basicAuthPasswordPlaintext":"p"},'
          + ' {"url":"https://a.com/","basicAuthUser":"u2","basicAuthPasswordPlaintext":"q"}]',
            "[]", "", null, _gen);
        const profiles = JSON.parse(out.profilesJson);
        compare(profiles.length, 2);
        compare(out.walletWrites.length, 2);
    }

    function test_legacy_walletReaderProvidesPassword() {
        // basicAuthUser present but plaintext password absent — fall back to
        // the legacy kwallet entry that pre-0.4.0 wrote under "basic:<host>".
        let reads = 0;
        const reader = function(key) {
            reads++;
            return key === "basic:a.example.com" ? "kwalletpw" : "";
        };
        const out = M.legacyAuthMigration(
            '[{"url":"https://a.example.com/","basicAuthUser":"alice"}]',
            "[]", "", reader, _gen);
        compare(out.mutated, true);
        compare(out.walletWrites.length, 1);
        compare(out.walletWrites[0].map.password, "kwalletpw");
        verify(reads >= 1);
    }

    function test_legacy_noSecret_noWalletWrite() {
        // basicAuthUser set but neither plaintext nor wallet has a password.
        // Profile is still created (otherwise the tab is broken), but no
        // wallet entry written.
        const out = M.legacyAuthMigration(
            '[{"url":"https://a.example.com/","basicAuthUser":"alice"}]',
            "[]", "", function() { return ""; }, _gen);
        compare(out.mutated, true);
        compare(JSON.parse(out.profilesJson).length, 1);
        compare(out.walletWrites.length, 0);
    }

    function test_legacy_existingProfileNotReusedDueToSignatureMismatch() {
        // Documented quirk of the production migration: the existing-profile
        // signature is `basic:<user>` but the new-tab signature is
        // `basic:<host>:<user>`. They never collide, so an existing profile
        // with matching username is NOT reused — a new one is created.
        // In practice the early `if (t.authProfileId) continue` skip means
        // tabs already migrated aren't re-touched, so the bug only surfaces
        // when an operator hand-adds a profile that *happens* to match a
        // legacy field's username. Documented here as the canonical contract.
        const out = M.legacyAuthMigration(
            '[{"url":"https://a.example.com/","basicAuthUser":"alice","basicAuthPasswordPlaintext":"p"}]',
            '[{"id":"pre-existing","authType":"basic","username":"alice"}]',
            "", null, _gen);
        compare(out.mutated, true);
        const tabs = JSON.parse(out.urlsJson);
        verify(tabs[0].authProfileId !== "pre-existing");
        const profiles = JSON.parse(out.profilesJson);
        compare(profiles.length, 2);   // pre-existing + newly created
    }

    function test_legacy_idempotent() {
        const first = M.legacyAuthMigration(
            '[{"url":"https://a.com/","basicAuthUser":"u","basicAuthPasswordPlaintext":"p"}]',
            "[]", "", null, _gen);
        compare(first.mutated, true);
        const second = M.legacyAuthMigration(
            first.urlsJson, first.profilesJson, "", null, _gen);
        compare(second.mutated, false);
        compare(second.walletWrites.length, 0);
    }

    function test_legacy_malformedUrlsJson_returnsVerbatim() {
        const out = M.legacyAuthMigration("{not", "[]", "", null, _gen);
        compare(out.mutated, false);
        compare(out.urlsJson, "{not");
    }

    function test_legacy_mixedLegacyAndModern() {
        // Three tabs: legacy with secret, modern (already has authProfileId),
        // legacy without secret. Only the first triggers a wallet write.
        const out = M.legacyAuthMigration(
            '[{"url":"https://a.com/","basicAuthUser":"u","basicAuthPasswordPlaintext":"p"},'
          + ' {"url":"https://b.com/","authProfileId":"existing"},'
          + ' {"url":"https://c.com/","basicAuthUser":"v"}]',
            "[]", "", function() { return ""; }, _gen);
        compare(out.mutated, true);
        const tabs = JSON.parse(out.urlsJson);
        verify(tabs[0].authProfileId.length > 0);
        compare(tabs[1].authProfileId, "existing");
        verify(tabs[2].authProfileId.length > 0);
        compare(out.walletWrites.length, 1);
    }
}
