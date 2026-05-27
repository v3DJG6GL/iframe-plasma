/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/RowSchema.js" as Schema
import "../../package/contents/ui/sanitize.js" as Sanitize

TestCase {
    name: "SerializeAuthProfiles"

    // Deterministic UUID generator for tests.
    property int _uuidSeq: 0
    function _gen() {
        _uuidSeq = _uuidSeq + 1;
        return "uuid-" + _uuidSeq;
    }
    function init() { _uuidSeq = 0; }

    // ===== UUID synthesis ============================================
    function test_missingId_synthesisedAndFlagged() {
        const out = Schema.normaliseAuthProfileRow({ name: "X", authType: "basic" }, _gen);
        compare(out.row.id, "uuid-1");
        verify(out.synthesized);
    }
    function test_presentId_kept_notFlagged() {
        const out = Schema.normaliseAuthProfileRow(
            { id: "existing", name: "X", authType: "basic", preempt: false }, _gen);
        compare(out.row.id, "existing");
        verify(!out.synthesized);
    }
    function test_emptyStringId_synthesised() {
        const out = Schema.normaliseAuthProfileRow({ id: "", authType: "basic", preempt: false }, _gen);
        compare(out.row.id, "uuid-1");
        verify(out.synthesized);
    }

    // ===== preempt defaults per authType ============================
    function test_preemptDefault_basic_false() {
        const out = Schema.normaliseAuthProfileRow({ id: "i", authType: "basic" }, _gen);
        compare(out.row.preempt, false);
        verify(out.synthesized);
    }
    function test_preemptDefault_bearer_true() {
        const out = Schema.normaliseAuthProfileRow({ id: "i", authType: "bearer" }, _gen);
        compare(out.row.preempt, true);
        verify(out.synthesized);
    }
    function test_preemptDefault_raw_true() {
        const out = Schema.normaliseAuthProfileRow({ id: "i", authType: "raw" }, _gen);
        compare(out.row.preempt, true);
        verify(out.synthesized);
    }
    function test_preemptDefault_none_false() {
        const out = Schema.normaliseAuthProfileRow({ id: "i", authType: "none" }, _gen);
        compare(out.row.preempt, false);
        verify(out.synthesized);
    }
    function test_preemptDefault_missingAuthType_basic() {
        // authType defaults to "basic" → preempt defaults to false.
        const out = Schema.normaliseAuthProfileRow({ id: "i" }, _gen);
        compare(out.row.authType, "basic");
        compare(out.row.preempt, false);
    }

    // ===== explicit preempt wins =====================================
    function test_explicitPreemptTrue_kept() {
        const out = Schema.normaliseAuthProfileRow(
            { id: "i", authType: "basic", preempt: true }, _gen);
        compare(out.row.preempt, true);
        verify(!out.synthesized);
    }
    function test_explicitPreemptFalse_keptForBearer() {
        // Operator chose to disable pre-emption for bearer despite the
        // default — respect it (no double-synthesise).
        const out = Schema.normaliseAuthProfileRow(
            { id: "i", authType: "bearer", preempt: false }, _gen);
        compare(out.row.preempt, false);
        verify(!out.synthesized);
    }
    function test_nonBooleanPreempt_treatedAsMissing() {
        const out = Schema.normaliseAuthProfileRow(
            { id: "i", authType: "basic", preempt: "yes" }, _gen);
        compare(out.row.preempt, false);
        verify(out.synthesized);
    }

    // ===== passthrough field defaults ===============================
    function test_nameAndUsernameKept() {
        const out = Schema.normaliseAuthProfileRow(
            { id: "i", name: "Prod", username: "u", authType: "basic", preempt: false }, _gen);
        compare(out.row.name, "Prod");
        compare(out.row.username, "u");
    }
    function test_missingFields_defaultToEmpty() {
        const out = Schema.normaliseAuthProfileRow(
            { id: "i", authType: "basic", preempt: false }, _gen);
        compare(out.row.name, "");
        compare(out.row.username, "");
        compare(out.row.autheliaHost, "");
    }
    function test_unknownAuthType_kept() {
        // Tolerance — the consumer falls back to its first preset if
        // authSpec() doesn't recognise the value.
        const out = Schema.normaliseAuthProfileRow(
            { id: "i", authType: "oauth2", preempt: false }, _gen);
        compare(out.row.authType, "oauth2");
    }

    // ===== UUID generator is called only when needed =================
    function test_uuidGenNotCalledForExistingId() {
        let called = false;
        Schema.normaliseAuthProfileRow(
            { id: "existing", authType: "basic", preempt: false },
            function() { called = true; return "x"; });
        verify(!called);
    }
    function test_uuidGenCalledOnceForMissingId() {
        let calls = 0;
        Schema.normaliseAuthProfileRow(
            { authType: "basic", preempt: false },
            function() { calls = calls + 1; return "x"; });
        compare(calls, 1);
    }

    // ===== sanitize-on-load mutation must trigger re-persist =========
    //
    // Pins the invariant the ConfigAuth.qml repopulate() loop relies on:
    // for an autheliaHost carrying a ZWSP / bidi-format / C0 byte, the
    // sanitize call mutates the value, and that mutation must drive the
    // synthesized branch — otherwise the unsanitized JSON survives on
    // disk while the listModel shows the sanitized form, and the next
    // Apply rewrites the unsanitised value back, silently disabling the
    // WebTab Authelia overlay.
    function test_sanitizeOnLoad_autheliaHostZwsp_mutatesValue() {
        const raw = "auth.example.com​";  // trailing ZWSP
        const out = Schema.normaliseAuthProfileRow(
            { id: "i", authType: "basic", preempt: false, autheliaHost: raw },
            _gen);
        const sanitized = Sanitize.strip(out.row.autheliaHost);
        // The mutation: pre-sanitize value carries the ZWSP, post does not.
        verify(out.row.autheliaHost !== sanitized);
        compare(sanitized, "auth.example.com");
        // RowSchema itself reports non-synthesized for a complete row;
        // it is the sanitize-mutation gate in repopulate() that must
        // upgrade the flag — guard the precondition that gate depends on.
        verify(!out.synthesized);
    }

    function test_sanitizeOnLoad_autheliaHostClean_noMutation() {
        // Symmetric: clean host must not flip the gate.
        const raw = "auth.example.com";
        const out = Schema.normaliseAuthProfileRow(
            { id: "i", authType: "basic", preempt: false, autheliaHost: raw },
            _gen);
        const sanitized = Sanitize.strip(out.row.autheliaHost);
        compare(out.row.autheliaHost, sanitized);
        verify(!out.synthesized);
    }

    // ===== full JSON roundtrip with mix of synthesised + complete rows
    function test_fullJsonRoundtrip_mixedRows() {
        const json = '[{"id":"a","name":"A","authType":"basic","preempt":true},'
                   + '{"name":"NeedsId","authType":"bearer"},'
                   + '{"id":"c","authType":"raw","preempt":false}]';
        const arr = JSON.parse(json);
        let synthesizedAny = false;
        const rows = arr.map(e => {
            const n = Schema.normaliseAuthProfileRow(e, _gen);
            if (n.synthesized) synthesizedAny = true;
            return n.row;
        });
        compare(rows.length, 3);
        compare(rows[0].id, "a");
        verify(rows[1].id !== undefined && rows[1].id.length > 0);
        compare(rows[1].preempt, true);   // bearer default
        compare(rows[2].preempt, false);  // explicit
        verify(synthesizedAny);
    }
}
