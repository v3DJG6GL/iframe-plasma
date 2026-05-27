/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Drives one WebEngineView through the Chromium page-lifecycle states so a
 * dashboard nobody is looking at stops burning CPU and — after a longer idle —
 * memory. Pattern follows Qt's official "WebEngine Lifecycle Example": a
 * single debounce Timer whose interval is chosen by the next target state.
 *
 *   desiredActive true  -> Active immediately. If the view sat Frozen longer
 *                          than stalenessSec it is reloaded, so a rotating
 *                          thumbnail never resumes showing stale data.
 *   desiredActive false -> Frozen   after freezeDelaySec  (JS/timers suspended,
 *                                                          instant no-reload
 *                                                          resume, memory kept)
 *                          Discarded after discardDelaySec (renderer subprocess
 *                                                          killed, memory ~0,
 *                                                          reloads on return).
 *
 * Hard rules QtWebEngine enforces and this respects: a visible or still-
 * loading view is pinned Active (recommendedState reports it); a Discarded
 * view can only return to Active. The caller MUST make the view invisible
 * (bind its `visible`) for any non-Active state to be reachable at all —
 * the controller only changes lifecycleState, never visibility.
 *
 * The pure decision core lives in LifecyclePolicy.js so
 * tests/qml/tst_lifecycle.qml can drive every transition without spinning
 * up a real WebEngineView; this file does the enum↔string conversion and
 * carries out the policy's action object.
 */
import QtQuick
import QtWebEngine
import "./LifecyclePolicy.js" as Policy

QtObject {
    id: ctl

    // The WebEngineView this controller governs.
    property var target: null

    // True while the view should be live; false when it is not observable.
    property bool desiredActive: true

    // Hybrid timing (seconds): freeze quickly, discard only after a long idle.
    property int freezeDelaySec: 30
    property int discardDelaySec: 600

    // On resume, if the view was Frozen longer than this, reload it so stale
    // content is refreshed. 0 disables the reload (Frozen->Active stays
    // instant). The thumbnail wires this to the auto-cycle interval.
    property int stalenessSec: 0

    // Date.now() ms when the view entered Frozen; 0 when not frozen.
    property double _frozenAtMs: 0

    function _stateName(s) {
        if (s === WebEngineView.LifecycleState.Frozen)    return "frozen";
        if (s === WebEngineView.LifecycleState.Discarded) return "discarded";
        return "active";
    }
    function _stateEnum(name) {
        if (name === "frozen")    return WebEngineView.LifecycleState.Frozen;
        if (name === "discarded") return WebEngineView.LifecycleState.Discarded;
        return WebEngineView.LifecycleState.Active;
    }

    function _apply(action) {
        if (!target) return;
        if (action.stopTimer) _phaseTimer.stop();
        if (action.setState !== undefined) {
            target.lifecycleState = _stateEnum(action.setState);
        }
        if (action.resetFrozenAtMs) _frozenAtMs = 0;
        if (action.frozenAtMs !== undefined) _frozenAtMs = action.frozenAtMs;
        if (action.reload) {
            try { target.reload(); } catch (e) { /* view gone */ }
        }
        if (action.scheduleMs !== undefined) {
            _phaseTimer.interval = action.scheduleMs;
            _phaseTimer.restart();
        }
        if (action.chainReevaluate) _reevaluate();
    }

    function _reevaluate() {
        if (!target) return;
        _apply(Policy.decideOnChange(
            _stateName(target.lifecycleState),
            desiredActive,
            _frozenAtMs,
            freezeDelaySec,
            discardDelaySec,
            stalenessSec,
            Date.now()));
    }

    onTargetChanged: _reevaluate()
    onDesiredActiveChanged: _reevaluate()
    Component.onCompleted: _reevaluate()

    property Timer _phaseTimer: Timer {
        repeat: false
        onTriggered: {
            const t = ctl.target;
            if (!t || ctl.desiredActive) return;
            ctl._apply(Policy.decideOnTimer(
                ctl._stateName(t.lifecycleState),
                ctl._stateName(t.recommendedState),
                ctl.freezeDelaySec,
                Date.now()));
        }
    }
}
