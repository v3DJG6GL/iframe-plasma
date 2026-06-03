/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/LifecyclePolicy.js" as P

TestCase {
    name: "Lifecycle"

    // ============================================================
    //  decideOnChange — desiredActive = TRUE branch
    // ============================================================
    function test_active_desiredActive_isNoOp() {
        const a = P.decideOnChange("active", true, 0, 30, 600, 0, 1000);
        compare(a.stopTimer, true);
        verify(a.setState === undefined);
        verify(!a.reload);
    }
    function test_frozen_desiredActive_returnsToActive() {
        const a = P.decideOnChange("frozen", true, 1000, 30, 600, 0, 2000);
        compare(a.setState, "active");
        compare(a.resetFrozenAtMs, true);
        verify(!a.reload);    // stalenessSec = 0 → no reload
    }
    function test_discarded_desiredActive_returnsToActive() {
        const a = P.decideOnChange("discarded", true, 0, 30, 600, 0, 1000);
        compare(a.setState, "active");
        verify(!a.reload);
    }
    function test_frozen_reloadOnlyWhenStaleExceeded() {
        // stalenessSec=10, frozen for 11s → reload.
        const a = P.decideOnChange("frozen", true, 1000, 30, 600, 10, 12001);
        compare(a.setState, "active");
        compare(a.reload, true);
    }
    function test_frozen_noReloadWhenBelowStaleness() {
        // stalenessSec=10, frozen for 5s → no reload.
        const a = P.decideOnChange("frozen", true, 1000, 30, 600, 10, 6000);
        verify(!a.reload);
    }
    function test_frozen_boundaryAtStaleness_reloads() {
        // Inclusive `>=` boundary: exactly stalenessSec elapsed → reload.
        // (When the auto-cycle interval equals the freeze delay, a tab is
        // frozen for exactly stalenessSec between appearances; a strict `>`
        // would never refresh it — the original frozen-blank-thumbnail bug.)
        const a = P.decideOnChange("frozen", true, 1000, 30, 600, 10, 11000);
        compare(a.reload, true);
    }
    function test_frozen_boundaryJustBelowStaleness_noReload() {
        const a = P.decideOnChange("frozen", true, 1000, 30, 600, 10, 10999);
        verify(!a.reload);
    }
    function test_frozen_boundaryJustAboveStaleness_reloads() {
        const a = P.decideOnChange("frozen", true, 1000, 30, 600, 10, 11001);
        compare(a.reload, true);
    }

    // ============================================================
    //  decideOnChange — priorFailed (8th arg) forces reload on resume
    // ============================================================
    function test_frozen_priorFailed_reloadsRegardlessOfTiming() {
        // Frozen well within stalenessSec (would normally NOT reload), but the
        // prior load failed/blanked → must reload so the stale blank frame is
        // never resumed.
        const a = P.decideOnChange("frozen", true, 1000, 30, 600, 10, 2000, true);
        compare(a.setState, "active");
        compare(a.reload, true);
    }
    function test_frozen_priorFailed_reloadsEvenWithFrozenAtMsZero() {
        // frozenAtMs=0 normally guards out the timing reload; priorFailed
        // still forces it.
        const a = P.decideOnChange("frozen", true, 0, 30, 600, 10, 1000, true);
        compare(a.reload, true);
    }
    function test_frozen_priorFailedUndefined_backwardCompat() {
        // 7-arg callers (priorFailed undefined) behave as the timing rule
        // alone — below staleness → no reload.
        const a = P.decideOnChange("frozen", true, 1000, 30, 600, 10, 2000);
        verify(!a.reload);
    }
    function test_active_priorFailed_noReload() {
        // priorFailed only matters on the Frozen->Active promotion, never on
        // an already-active view.
        const a = P.decideOnChange("active", true, 0, 30, 600, 10, 1000, true);
        verify(a.setState === undefined);
        verify(!a.reload);
    }
    function test_discarded_priorFailed_noPolicyReload() {
        // Discarded->Active auto-reloads in QtWebEngine; the policy must not
        // add its own reload even when priorFailed.
        const a = P.decideOnChange("discarded", true, 0, 30, 600, 10, 1000, true);
        compare(a.setState, "active");
        verify(!a.reload);
    }
    function test_discarded_doesNotTriggerReload() {
        // Discarded->Active auto-reloads in QtWebEngine; the policy must
        // not also fire an explicit reload.
        const a = P.decideOnChange("discarded", true, 999999999, 30, 600, 10, 1e10);
        verify(!a.reload);
    }
    function test_frozenAtMsZero_skipsReload() {
        // _frozenAtMs=0 means "not currently frozen" — guard prevents
        // a stale 0 timestamp from triggering bogus reloads.
        const a = P.decideOnChange("frozen", true, 0, 30, 600, 10, 1000000);
        verify(!a.reload);
    }

    // ============================================================
    //  decideOnChange — desiredActive = FALSE branch
    // ============================================================
    function test_inactive_fromActive_schedulesFreezeTimer() {
        const a = P.decideOnChange("active", false, 0, 30, 600, 0, 1000);
        compare(a.scheduleMs, 30000);
    }
    function test_inactive_fromFrozen_schedulesDiscardTimer() {
        // discardDelaySec - freezeDelaySec = 600 - 30 = 570 → 570000 ms.
        const a = P.decideOnChange("frozen", false, 0, 30, 600, 0, 1000);
        compare(a.scheduleMs, 570000);
    }
    function test_inactive_fromDiscarded_stopsTimer() {
        const a = P.decideOnChange("discarded", false, 0, 30, 600, 0, 1000);
        compare(a.stopTimer, true);
        verify(a.scheduleMs === undefined);
    }
    function test_freezeDelay_clampedToMin1() {
        // freezeDelaySec=0 → clamp to 1s → 1000ms.
        const a = P.decideOnChange("active", false, 0, 0, 600, 0, 1000);
        compare(a.scheduleMs, 1000);
    }
    function test_negativeFreezeDelay_clampedToMin1() {
        const a = P.decideOnChange("active", false, 0, -5, 600, 0, 1000);
        compare(a.scheduleMs, 1000);
    }
    function test_discardSmallerThanFreeze_clampedToMin1() {
        // (discardDelaySec - freezeDelaySec) = negative → clamp to 1s.
        const a = P.decideOnChange("frozen", false, 0, 60, 30, 0, 1000);
        compare(a.scheduleMs, 1000);
    }

    // ============================================================
    //  decideOnTimer — second decision point
    // ============================================================
    function test_onTimer_recommendedActive_reschedules() {
        // View is still loading or audible → reschedule for next try.
        const a = P.decideOnTimer("active", "active", 30, 1000);
        compare(a.scheduleMs, 30000);
        verify(a.setState === undefined);
    }
    function test_onTimer_recommendedActive_clampsFreezeDelay() {
        const a = P.decideOnTimer("active", "active", 0, 1000);
        compare(a.scheduleMs, 1000);
    }
    function test_onTimer_active_andRecommendedFrozen_promotesToFrozen() {
        const a = P.decideOnTimer("active", "frozen", 30, 5000);
        compare(a.setState, "frozen");
        compare(a.frozenAtMs, 5000);
        compare(a.chainReevaluate, true);
    }
    function test_onTimer_active_andRecommendedDiscarded_promotesToFrozen() {
        // From Active we always go via Frozen first — never Active→Discarded.
        const a = P.decideOnTimer("active", "discarded", 30, 5000);
        compare(a.setState, "frozen");
    }
    function test_onTimer_frozen_andRecommendedDiscarded_promotesToDiscarded() {
        const a = P.decideOnTimer("frozen", "discarded", 30, 5000);
        compare(a.setState, "discarded");
        compare(a.resetFrozenAtMs, true);
    }
    function test_onTimer_frozen_andRecommendedFrozen_isNoOp() {
        // Form-input or PDF pin keeps it at Frozen — don't try to discard.
        const a = P.decideOnTimer("frozen", "frozen", 30, 5000);
        verify(a.setState === undefined);
        verify(!a.scheduleMs);
    }
    function test_onTimer_discarded_isNoOp() {
        const a = P.decideOnTimer("discarded", "discarded", 30, 5000);
        verify(a.setState === undefined);
    }

    // ============================================================
    //  Round-trip transitions (sequencing the two functions)
    // ============================================================
    function test_sequence_activeToFrozen() {
        // User looks away → schedule freeze → timer fires → state=frozen.
        const change = P.decideOnChange("active", false, 0, 30, 600, 0, 1000);
        compare(change.scheduleMs, 30000);
        // 30 s later the timer fires:
        const timer = P.decideOnTimer("active", "frozen", 30, 31000);
        compare(timer.setState, "frozen");
        compare(timer.frozenAtMs, 31000);
    }
    function test_sequence_frozenToDiscarded() {
        // Already frozen at t=31000; chainReevaluate fires decideOnChange
        // again with currentState now = "frozen".
        const change = P.decideOnChange("frozen", false, 31000, 30, 600, 0, 31000);
        compare(change.scheduleMs, 570000);   // (600-30)*1000
        // Timer fires at t=601000:
        const timer = P.decideOnTimer("frozen", "discarded", 30, 601000);
        compare(timer.setState, "discarded");
    }
    function test_sequence_discardedReturnsToActiveOnDemand() {
        const change = P.decideOnChange("discarded", true, 0, 30, 600, 0, 1e6);
        compare(change.setState, "active");
        compare(change.stopTimer, true);
    }
    function test_sequence_resumeWithinStalenessNoReload() {
        // Frozen at t=1000, resume at t=5000, staleness=10s → no reload.
        const change = P.decideOnChange("frozen", true, 1000, 30, 600, 10, 5000);
        verify(!change.reload);
    }
    function test_sequence_resumeAfterStalenessReloads() {
        // Frozen at t=1000, resume at t=12000, staleness=10s → reload.
        const change = P.decideOnChange("frozen", true, 1000, 30, 600, 10, 12000);
        compare(change.reload, true);
    }
}
