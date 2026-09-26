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
 *   reason          : string                        — short tag for the log line
 *
 * State names are strings rather than enum integers so the policy is
 * QtWebEngine-independent. WebViewLifecycle.qml does the small
 * stateName/stateEnum conversion at the boundary.
 */
.pragma library

// Called from _reevaluate() when desiredActive flips or target changes.
// priorFailed (optional, defaults falsy) is true when the view's last load
// failed or rendered blank — in that case promote-and-reload regardless of how
// long it sat Frozen, since a stale blank frame must never be resumed as-is.
// recycleDue (optional, appended) is true when the view's renderer process
// has outlived its recycle age (isRecycleDue): a Frozen, unwanted view is then
// discarded after 1 s instead of the full discard delay, so it reloads with a
// fresh renderer on its next appearance.
function decideOnChange(currentState, desiredActive, frozenAtMs,
                        freezeDelaySec, discardDelaySec, stalenessSec, now,
                        priorFailed, recycleDue) {
    if (desiredActive) {
        const out = { stopTimer: true };
        if (currentState !== "active") {
            out.setState = "active";
            out.resetFrozenAtMs = true;
            // Reload on resume when the prior attempt failed/blanked (any
            // frozen duration), OR when the view sat Frozen at least as long
            // as stalenessSec. The boundary is inclusive (>=): with the
            // common config where the auto-cycle interval equals the freeze
            // delay, a tab is frozen for exactly stalenessSec between
            // appearances, and a strict > would never refresh it.
            if (currentState === "frozen" && (
                    priorFailed === true
                 || (stalenessSec > 0 && frozenAtMs > 0
                     && (now - frozenAtMs) >= stalenessSec * 1000))) {
                out.reload = true;
            }
        }
        return out;
    }
    // desiredActive false: schedule the next downward step.
    if (currentState === "discarded") {
        return { stopTimer: true };   // nothing lower to go to
    }
    if (currentState === "frozen" && recycleDue === true) {
        return { scheduleMs: 1000, reason: "recycle" };
    }
    const intervalSec = (currentState === "active")
        ? Math.max(1, freezeDelaySec)
        : Math.max(1, discardDelaySec - freezeDelaySec);
    return { scheduleMs: intervalSec * 1000 };
}

// Tracks when the view's current renderer process started, from the pid
// sampled at each decision point: a new non-zero pid restarts the clock,
// pid 0 (no renderer, e.g. Discarded) clears it. Sampling instead of
// renderProcessPidChanged because that signal was not observed to fire on
// Qt 6.10 (tests/e2e/tst_lifecycle_e2e.cpp discard_replacesRenderProcess).
// Returns { pid, sinceMs }.
function trackRenderer(prevPid, prevSinceMs, pid, now) {
    if (pid === prevPid) return { pid: prevPid, sinceMs: prevSinceMs };
    return { pid: pid, sinceMs: pid > 0 ? now : 0 };
}

// Whether a renderer that started at rendererSinceMs (Date.now() ms; 0 =
// unknown / no renderer) has reached recycleAfterSec (0 = never recycle).
// Recycling bounds any per-renderer memory growth regardless of Qt version
// (Qt WebEngine 6.10 GC regression, QTBUG-141377).
function isRecycleDue(rendererSinceMs, recycleAfterSec, now) {
    if (!(recycleAfterSec > 0) || !(rendererSinceMs > 0)) return false;
    return (now - rendererSinceMs) >= recycleAfterSec * 1000;
}

// Called from the Timer onTriggered handler. Only invoked when
// desiredActive === false (the caller's timer wouldn't run otherwise).
//
// discardDelaySec / recycleDue (optional, appended) size the retry when
// Chromium pins a Frozen view at Frozen (form input, PDF, …). Without a
// retry the view would never be discarded: nothing else re-arms the timer
// once it has fired. Old 4-arg callers get a 60 s retry.
function decideOnTimer(currentState, recommendedState,
                       freezeDelaySec, now, discardDelaySec, recycleDue) {
    // A loading or audible view is pinned Active by Chromium —
    // reschedule for the freeze interval, try again then.
    if (recommendedState === "active") {
        return { scheduleMs: Math.max(1, freezeDelaySec) * 1000 };
    }
    if (currentState === "active") {
        return { setState: "frozen", frozenAtMs: now, chainReevaluate: true };
    }
    if (currentState === "frozen" && recommendedState === "discarded") {
        return { setState: "discarded", resetFrozenAtMs: true,
                 reason: recycleDue === true ? "recycle" : "idle" };
    }
    if (currentState === "frozen") {
        // recommendedState pins it at Frozen — retry the discard later.
        const retrySec = (recycleDue === true || discardDelaySec === undefined)
            ? 60
            : Math.max(60, discardDelaySec - freezeDelaySec);
        return { scheduleMs: retrySec * 1000, reason: "pinned-frozen" };
    }
    return {};
}

// Whether a lifecycleState / recommendedState change the controller did not
// cause itself should trigger _reevaluate(). Covers views forced awake
// behind the controller's back (WebTab.reload() / miniView promote a
// Discarded view straight to Active) and a Frozen view whose pin lifted.
// Never restarts a running timer: restarting on every signal would reset
// the countdown before it can fire — the same bug the auto-cycle had.
function shouldReevaluateOnExternalChange(desiredActive, timerRunning,
                                          applying, stateName) {
    if (desiredActive || timerRunning || applying) return false;
    return stateName === "active" || stateName === "frozen";
}
