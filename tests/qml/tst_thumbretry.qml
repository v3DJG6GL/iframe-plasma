/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/ThumbRetryPolicy.js" as R

TestCase {
    name: "ThumbRetry"

    // ============================================================
    //  backoffMs
    // ============================================================
    function test_backoff_schedule() {
        compare(R.backoffMs(0), 3000);
        compare(R.backoffMs(1), 10000);
        compare(R.backoffMs(2), 30000);
    }
    function test_backoff_exhausted() {
        compare(R.backoffMs(3), -1);
        compare(R.backoffMs(99), -1);
    }
    function test_backoff_negativeAttempt() {
        compare(R.backoffMs(-1), -1);
    }

    // ============================================================
    //  slowRetryMs / shouldFireSlowRetry
    // ============================================================
    function test_slowRetry_onlyFailedSlot() {
        compare(R.slowRetryMs("err"), 300000);
        compare(R.slowRetryMs("blank"), -1);
        compare(R.slowRetryMs("ok"), -1);
        compare(R.slowRetryMs("loading"), -1);
    }
    function test_slowRetry_firesOnlyOnScreen() {
        verify(R.shouldFireSlowRetry("err", true, true));
        verify(!R.shouldFireSlowRetry("err", false, true));
        verify(!R.shouldFireSlowRetry("err", true, false));
        verify(!R.shouldFireSlowRetry("ok", true, true));
        verify(!R.shouldFireSlowRetry("loading", true, true));
    }
    function test_sequence_failedSlotWithoutLandings_keepsRetrying() {
        // Replays main.qml with a single tab (no landings) whose host comes
        // back after the schedule ran out: every load fails until load 6.
        let attempt = 0;
        let slow = false;
        let reloads = 0;
        let healed = false;
        for (let load = 0; load < 10 && !healed; load++) {
            if (load >= 6) { healed = true; break; }
            // LoadFailed → arm()
            const ms = R.backoffMs(attempt);
            if (ms >= 0) { attempt++; slow = false; }
            else if (R.slowRetryMs("err") > 0) slow = true;
            else break;                  // nothing armed: stuck on "err"
            // Timer fires.
            if (slow ? R.shouldFireSlowRetry("err", true, true)
                     : R.shouldFireRetry("err", true, true)) reloads++;
            else break;
        }
        verify(healed);
        compare(attempt, 3);             // the slow retry does not grow it
        compare(reloads, 6);
    }

    // ============================================================
    //  attemptAfterLoadSucceeded
    // ============================================================
    function test_loadSucceeded_cropPending_keepsBudget() {
        compare(R.attemptAfterLoadSucceeded(2, true), 2);
    }
    function test_loadSucceeded_noCropStep_refills() {
        compare(R.attemptAfterLoadSucceeded(2, false), 0);
    }

    // ============================================================
    //  shouldFireRetry
    // ============================================================
    function test_fireRetry_failedOrBlankSlot() {
        verify(R.shouldFireRetry("err", true, true));
        verify(R.shouldFireRetry("blank", true, true));
    }
    function test_fireRetry_blankNoLongerOnScreen_skipped() {
        // Armed while on screen, due after the slot rotated away or the
        // screen locked: the reload would wake a frozen view for nothing.
        verify(!R.shouldFireRetry("blank", false, true));
        verify(!R.shouldFireRetry("blank", true, false));
    }
    function test_fireRetry_failedSlotOffScreen_stillFires() {
        verify(R.shouldFireRetry("err", false, false));
    }
    function test_fireRetry_loadInFlight_skipped() {
        // Landing on a failed tab reloads it at once; the retry armed on
        // the same landing must not abort that load 3 s later.
        verify(!R.shouldFireRetry("loading"));
    }
    function test_fireRetry_recoveredSlot_skipped() {
        verify(!R.shouldFireRetry("ok"));
    }

    // ============================================================
    //  isFrameConfirmed
    // ============================================================
    function test_frameConfirmed_engineMatchResult() {
        // The only "matched" string CropEngine.buildApplyJs returns.
        verify(R.isFrameConfirmed("matched-and-observing"));
    }
    function test_frameConfirmed_otherEngineResults_notConfirmed() {
        verify(!R.isFrameConfirmed("observing"));
        verify(!R.isFrameConfirmed("canvas-pending"));
        verify(!R.isFrameConfirmed("invalid"));
        verify(!R.isFrameConfirmed(undefined));
    }

    // ============================================================
    //  shouldMarkBlank / shouldArmBlankRetry
    // ============================================================
    function test_markBlank_canvasPendingCleanLoad() {
        verify(R.shouldMarkBlank("canvas-pending", "ok", true));
    }
    function test_markBlank_staleCallbackAfterCrop_ignored() {
        // A CROP landed while runJavaScript was in flight.
        verify(!R.shouldMarkBlank("canvas-pending", "ok", false));
    }
    function test_markBlank_matched_ignored() {
        verify(!R.shouldMarkBlank("matched-and-observing", "ok", true));
    }
    function test_markBlank_alreadyFailed_ignored() {
        verify(!R.shouldMarkBlank("canvas-pending", "err", true));
    }
    function test_healBlank_matchOnBlankSlot() {
        // Blank from a canvas selector, then a non-canvas selector saved
        // in place matches: no CROP line will ever heal it.
        verify(R.shouldHealBlank("matched-and-observing", "blank"));
    }
    function test_healBlank_onlyBlankSlots() {
        verify(!R.shouldHealBlank("matched-and-observing", "ok"));
        verify(!R.shouldHealBlank("matched-and-observing", "loading"));
        verify(!R.shouldHealBlank("matched-and-observing", "err"));
    }
    function test_healBlank_unconfirmedResult_staysBlank() {
        verify(!R.shouldHealBlank("canvas-pending", "blank"));
        verify(!R.shouldHealBlank("observing", "blank"));
    }
    function test_healBlank_selectorClearedInPlace() {
        // Custom selector cleared without a mode change: the re-apply
        // returns "observing", which never heals, and nothing reloads.
        verify(R.shouldHealBlankOnSelectorCleared("", "blank"));
        verify(R.shouldHealBlankOnSelectorCleared(undefined, "blank"));
    }
    function test_healBlank_selectorClearedInPlace_onlyBlankSlots() {
        verify(!R.shouldHealBlankOnSelectorCleared(".u-wrap > canvas", "blank"));
        verify(!R.shouldHealBlankOnSelectorCleared("", "ok"));
        verify(!R.shouldHealBlankOnSelectorCleared("", "err"));
        verify(!R.shouldHealBlankOnSelectorCleared("", "loading"));
    }
    function test_armBlank_onlyCurrentAndObservable() {
        verify(R.shouldArmBlankRetry(true, true));
        verify(!R.shouldArmBlankRetry(false, true));   // hidden: reload on landing
        verify(!R.shouldArmBlankRetry(true, false));   // panel off-screen / locked
    }
    function test_rearmOnObservable_skippedBlankRetry() {
        // The retry fell due while hidden and was skipped; nothing else
        // re-arms a slot that stayed current.
        verify(R.shouldRearmOnObservable("blank", true, true, false));
    }
    function test_rearmOnObservable_notWhenPendingHiddenOrHealthy() {
        verify(!R.shouldRearmOnObservable("blank", true, true, true));    // retry still pending
        verify(!R.shouldRearmOnObservable("blank", true, false, false));  // still not observable
        verify(!R.shouldRearmOnObservable("blank", false, true, false));  // not on screen: landing re-arms
        verify(!R.shouldRearmOnObservable("ok", true, true, false));
        verify(!R.shouldRearmOnObservable("loading", true, true, false));
        verify(!R.shouldRearmOnObservable("err", true, true, false));     // fires regardless of observability
    }
    function test_sequence_hiddenWhenRetryDue_resumesOnShow() {
        // Replays main.qml: blank slot arms, the retry falls due while the
        // screen is locked (skipped), then the panel shows again.
        let attempt = 0;
        let reloads = 0;
        let pending = R.shouldArmBlankRetry(true, true) && R.backoffMs(attempt) >= 0;
        if (pending) attempt++;
        // Timer fires while hidden.
        pending = false;
        if (R.shouldFireRetry("blank", true, false)) reloads++;
        compare(reloads, 0);
        // Observable again.
        if (R.shouldRearmOnObservable("blank", true, true, pending) && R.backoffMs(attempt) >= 0) {
            attempt++;
            pending = true;
        }
        verify(pending);
        if (R.shouldFireRetry("blank", true, true)) reloads++;
        compare(reloads, 1);
    }

    // ============================================================
    //  Sequences
    // ============================================================
    // Replays main.qml's loop: load succeeds → crop reports
    // "canvas-pending" → arm → retry reload → load succeeds → …
    // Returns how many retries were armed before the budget ran out.
    function _replayCanvasNeverPaints(loads) {
        let attempt = 0;
        let armed = 0;
        for (let i = 0; i < loads; i++) {
            attempt = R.attemptAfterLoadSucceeded(attempt, true);
            if (!R.shouldMarkBlank("canvas-pending", "ok", true)) continue;
            if (!R.shouldArmBlankRetry(true, true)) continue;
            const ms = R.backoffMs(attempt);
            if (ms < 0) break;          // "backoff exhausted"
            attempt++;
            armed++;
        }
        return armed;
    }
    function test_sequence_blankLoopIsBounded() {
        // Before the fix LoadSucceeded reset the counter, so this armed a
        // 3 s reload on every one of the 10 loads, forever.
        compare(_replayCanvasNeverPaints(10), 3);
    }
    function test_sequence_frameConfirmedRefillsBudget() {
        let attempt = 3;                 // exhausted
        compare(R.backoffMs(attempt), -1);
        // A non-canvas selector logs no CROP: the apply result is the
        // only confirmation it gets.
        if (R.isFrameConfirmed("matched-and-observing")) attempt = 0;
        compare(R.backoffMs(attempt), 3000);
    }
    function test_sequence_hiddenThumbnailNeverArms() {
        let armed = 0;
        for (let i = 0; i < 10; i++) {
            if (R.shouldMarkBlank("canvas-pending", "ok", true)
                    && R.shouldArmBlankRetry(false, true)) {
                armed++;
            }
        }
        compare(armed, 0);
    }
}
