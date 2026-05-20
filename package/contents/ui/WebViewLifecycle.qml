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
 */
import QtQuick
import QtWebEngine

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

    function _reevaluate() {
        if (!target)
            return;
        if (desiredActive) {
            _phaseTimer.stop();
            if (target.lifecycleState !== WebEngineView.LifecycleState.Active) {
                const stale = target.lifecycleState === WebEngineView.LifecycleState.Frozen
                    && stalenessSec > 0 && _frozenAtMs > 0
                    && (Date.now() - _frozenAtMs) > stalenessSec * 1000;
                // Discarded->Active reloads on its own; this covers Frozen.
                target.lifecycleState = WebEngineView.LifecycleState.Active;
                _frozenAtMs = 0;
                if (stale) {
                    try { target.reload(); } catch (e) { /* view gone */ }
                }
            }
            return;
        }
        // desiredActive false: schedule the next downward step.
        if (target.lifecycleState === WebEngineView.LifecycleState.Discarded) {
            _phaseTimer.stop();   // nothing lower to go to
            return;
        }
        _phaseTimer.interval = (target.lifecycleState === WebEngineView.LifecycleState.Active
            ? Math.max(1, freezeDelaySec)
            : Math.max(1, discardDelaySec - freezeDelaySec)) * 1000;
        _phaseTimer.restart();
    }

    onTargetChanged: _reevaluate()
    onDesiredActiveChanged: _reevaluate()
    Component.onCompleted: _reevaluate()

    property Timer _phaseTimer: Timer {
        repeat: false
        onTriggered: {
            const t = ctl.target;
            if (!t || ctl.desiredActive)
                return;
            // A loading or audible view is pinned Active by the engine
            // (recommendedState === Active) — don't fight it, retry later.
            if (t.recommendedState === WebEngineView.LifecycleState.Active) {
                interval = Math.max(1, ctl.freezeDelaySec) * 1000;
                restart();
                return;
            }
            if (t.lifecycleState === WebEngineView.LifecycleState.Active) {
                t.lifecycleState = WebEngineView.LifecycleState.Frozen;
                ctl._frozenAtMs = Date.now();
                ctl._reevaluate();           // chain into the discard phase
            } else if (t.lifecycleState === WebEngineView.LifecycleState.Frozen
                       && t.recommendedState === WebEngineView.LifecycleState.Discarded) {
                t.lifecycleState = WebEngineView.LifecycleState.Discarded;
                ctl._frozenAtMs = 0;
            }
            // else: recommendedState pins it at Frozen (form input / PDF) —
            // leave it frozen, no discard.
        }
    }
}
