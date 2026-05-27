/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pure decision core for WebViewLifecycle.qml. Two functions describe
 * what the controller should do at each decision point — they take only
 * primitive inputs (state-name strings, booleans, numbers) so
 * tests/qml/tst_lifecycle.qml can drive every transition without a
 * WebEngineView (and without the QtWebEngine.LifecycleState enum).
 *
 * Returned action objects use optional fields the caller checks:
 *   setState        : "active"|"frozen"|"discarded" — assign to the view
 *   stopTimer       : bool                          — _phaseTimer.stop()
 *   scheduleMs      : number                        — _phaseTimer interval+restart
 *   reload          : bool                          — call view.reload()
 *   resetFrozenAtMs : bool                          — _frozenAtMs = 0
 *   frozenAtMs      : number                        — _frozenAtMs = <ms>
 *   chainReevaluate : bool                          — caller should _reevaluate()
 *
 * State names are strings rather than enum integers so the policy is
 * QtWebEngine-independent. WebViewLifecycle.qml does the small
 * stateName/stateEnum conversion at the boundary.
 */
.pragma library

// Called from _reevaluate() when desiredActive flips or target changes.
function decideOnChange(currentState, desiredActive, frozenAtMs,
                        freezeDelaySec, discardDelaySec, stalenessSec, now) {
    if (desiredActive) {
        const out = { stopTimer: true };
        if (currentState !== "active") {
            out.setState = "active";
            out.resetFrozenAtMs = true;
            if (currentState === "frozen" && stalenessSec > 0 && frozenAtMs > 0
                && (now - frozenAtMs) > stalenessSec * 1000) {
                out.reload = true;
            }
        }
        return out;
    }
    // desiredActive false: schedule the next downward step.
    if (currentState === "discarded") {
        return { stopTimer: true };   // nothing lower to go to
    }
    const intervalSec = (currentState === "active")
        ? Math.max(1, freezeDelaySec)
        : Math.max(1, discardDelaySec - freezeDelaySec);
    return { scheduleMs: intervalSec * 1000 };
}

// Called from the Timer onTriggered handler. Only invoked when
// desiredActive === false (the caller's timer wouldn't run otherwise).
function decideOnTimer(currentState, recommendedState,
                       freezeDelaySec, now) {
    // A loading or audible view is pinned Active by Chromium —
    // reschedule for the freeze interval, try again then.
    if (recommendedState === "active") {
        return { scheduleMs: Math.max(1, freezeDelaySec) * 1000 };
    }
    if (currentState === "active") {
        return { setState: "frozen", frozenAtMs: now, chainReevaluate: true };
    }
    if (currentState === "frozen" && recommendedState === "discarded") {
        return { setState: "discarded", resetFrozenAtMs: true };
    }
    // recommendedState pins it at Frozen (form input / PDF, etc.) — leave alone.
    return {};
}
