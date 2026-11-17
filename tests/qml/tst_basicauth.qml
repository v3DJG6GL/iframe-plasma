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

    // ===== claimBasicAuthAnswer =======================================
    // The thumbnail's retry schedule (ThumbRetryPolicy: +3 s, +10 s, +30 s,
    // then every 300 s) re-challenges after the 10 s window has passed.
    function _replayRetryingView(offsetsMs) {
        const answered = {};
        const key = "thumb:0|p|https://dash.example/d/x|realm";
        let sent = 0;
        for (const t of offsetsMs) {
            if (U.claimBasicAuthAnswer(answered, key, 1000 + t))
                sent++;
        }
        return sent;
    }
    function test_claim_rejectionIsStickyAcrossRetries() {
        // Answer at 0 rejected (challenge straight back at 50 ms): the
        // retries at 3 s, 13 s, 43 s and 343 s must not resend it.
        compare(_replayRetryingView([0, 50, 3050, 13050, 43050, 343050]), 1);
    }
    function test_claim_reChallengeAfterWindowWithoutRejection_answered() {
        // A session that expires later is not a rejection: answer again.
        compare(_replayRetryingView([0, 60000, 120000]), 3);
    }
    function test_claim_resetMapRetriesOnce() {
        // primeAuthProfiles empties the map after a secret change.
        const key = "popup:0|p|https://dash.example/d/x|realm";
        let answered = {};
        verify(U.claimBasicAuthAnswer(answered, key, 1000));
        verify(!U.claimBasicAuthAnswer(answered, key, 1050));
        answered = {};
        verify(U.claimBasicAuthAnswer(answered, key, 90000));
    }
    function test_claim_otherChallengeUnaffectedByRejection() {
        const answered = {};
        const a = "thumb:0|p|https://dash.example/d/x|realm";
        const b = "thumb:1|p|https://dash.example/d/y|realm";
        verify(U.claimBasicAuthAnswer(answered, a, 1000));
        verify(!U.claimBasicAuthAnswer(answered, a, 1050));
        verify(U.claimBasicAuthAnswer(answered, b, 1060));
    }

    // ===== basicAuthChallengeKey =====================================
    function test_challengeKey_popupAndThumbOfSameTabDiffer() {
        // Same profile, URL and realm: only the asking view tells them apart.
        verify(U.basicAuthChallengeKey("popup:0", "p", "https://dash.example/d/x", "realm")
               !== U.basicAuthChallengeKey("thumb:0", "p", "https://dash.example/d/x", "realm"));
    }
    function test_challengeKey_sameViewSameChallengeMatches() {
        // The wrong-password loop guard still catches one view's re-challenge.
        compare(U.basicAuthChallengeKey("popup:0", "p", "https://dash.example/d/x", "realm"),
                U.basicAuthChallengeKey("popup:0", "p", "https://dash.example/d/x", "realm"));
    }
    function test_challengeKey_missingRealmMatchesEmpty() {
        compare(U.basicAuthChallengeKey("thumb:1", "p", "https://dash.example/", undefined),
                U.basicAuthChallengeKey("thumb:1", "p", "https://dash.example/", ""));
    }
    function test_sequence_popupAndThumbChallengedTogetherBothAnswered() {
        // Both views of one tab reload together (password changed in the
        // KCM) and are challenged 5 ms apart: each carries the password.
        const answered = {};
        let sent = 0;
        let now = 1000;
        for (const view of ["thumb:0", "popup:0"]) {
            const key = U.basicAuthChallengeKey(view, "p", "https://dash.example/d/x", "realm");
            if (U.mayAutoAnswerBasicAuth(answered[key], now)) {
                answered[key] = now;
                sent++;
            }
            now += 5;
        }
        compare(sent, 2);
    }
}
