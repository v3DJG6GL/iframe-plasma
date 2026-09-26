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
    //  attemptAfterLoadSucceeded
    // ============================================================
    function test_loadSucceeded_cropPending_keepsBudget() {
        compare(R.attemptAfterLoadSucceeded(2, true), 2);
    }
    function test_loadSucceeded_noCropStep_refills() {
        compare(R.attemptAfterLoadSucceeded(2, false), 0);
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
        verify(!R.shouldMarkBlank("matched", "ok", true));
    }
    function test_markBlank_alreadyFailed_ignored() {
        verify(!R.shouldMarkBlank("canvas-pending", "err", true));
    }
    function test_armBlank_onlyCurrentAndObservable() {
        verify(R.shouldArmBlankRetry(true, true));
        verify(!R.shouldArmBlankRetry(false, true));   // hidden: reload on landing
        verify(!R.shouldArmBlankRetry(true, false));   // panel off-screen / locked
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
        attempt = 0;                     // CROP seen / "matched" → reset
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
