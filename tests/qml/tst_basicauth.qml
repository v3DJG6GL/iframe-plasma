/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pins the guard main.qml's handleBasicAuth applies before it auto-answers
 * a Basic-auth challenge with stored credentials. Time is passed in, so
 * nothing here waits.
 */
import QtQuick
import QtTest
import "../../package/contents/ui/UrlUtils.js" as U

TestCase {
    name: "BasicAuth"

    // ===== mayAutoAnswerBasicAuth ====================================
    function test_neverAnswered_mayAnswer() {
        verify(U.mayAutoAnswerBasicAuth(undefined, 5000));
        verify(U.mayAutoAnswerBasicAuth(0, 5000));
    }
    function test_challengeStraightBack_notAnswered() {
        // The server rejected the answer and challenged again 50 ms later.
        verify(!U.mayAutoAnswerBasicAuth(5000, 5050));
    }
    function test_sameInstant_notAnswered() {
        verify(!U.mayAutoAnswerBasicAuth(5000, 5000));
    }
    function test_justInsideWindow_notAnswered() {
        verify(!U.mayAutoAnswerBasicAuth(5000, 14999));
    }
    function test_windowElapsed_mayAnswerAgain() {
        verify(U.mayAutoAnswerBasicAuth(5000, 15000));
    }
    function test_clockSteppedBack_mayAnswer() {
        verify(U.mayAutoAnswerBasicAuth(5000, 1000));
    }

    // ===== Sequences =================================================
    // Replays handleBasicAuth's bookkeeping against a server that rejects
    // every answer and re-challenges `gapMs` later. Returns how many of
    // `challenges` were auto-answered.
    function _replayRejectingServer(challenges, gapMs) {
        const answered = {};
        const key = "profile|https://dash.example/d/x|realm";
        let now = 1000;
        let sent = 0;
        for (let i = 0; i < challenges; i++) {
            if (U.mayAutoAnswerBasicAuth(answered[key], now)) {
                answered[key] = now;
                sent++;
            }
            now += gapMs;
        }
        return sent;
    }
    function test_sequence_wrongPasswordLoopIsBounded() {
        // 100 challenges inside 5 s: only the first carries the password.
        compare(_replayRejectingServer(100, 50), 1);
    }
    function test_sequence_otherChallengeStillAnswered() {
        // A second tab on the same host and profile has its own entry.
        const answered = { "profile|https://dash.example/d/x|realm": 1000 };
        verify(U.mayAutoAnswerBasicAuth(answered["profile|https://dash.example/d/y|realm"], 1010));
    }
}
