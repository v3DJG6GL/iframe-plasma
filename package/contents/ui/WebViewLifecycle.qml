/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Drives one WebEngineView through the Chromium page-lifecycle states so a
 * dashboard nobody is looking at stops burning CPU and — after a longer idle —
 * memory. Pattern follows Qt's official "WebEngine Lifecycle Example": a
 * single debounce Timer whose interval is chosen by the next target state.
 *
 *   desiredActive true  -> Active immediately. If the view sat Frozen at
 *                          least stalenessSec (when > 0) or its last load
 *                          failed, it is reloaded.
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
 * State changes the controller did not make itself (a reload promoting a
 * Discarded view to Active, Chromium lifting a Frozen pin) re-enter the
 * policy while the timer is idle, so such a view is frozen again instead of
 * staying Active and invisible until its tab is next shown.
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
    // instant). The thumbnail wires this to thumbnailReloadAfterSec.
    property int stalenessSec: 0

    // True when the view's last load failed or rendered blank. Forces a
    // reload on the next Frozen->Active promotion regardless of stalenessSec /
    // frozen duration, so a failed thumbnail can't resume showing its stale
    // blank frame. The thumbnail binds this to miniView.loadStatus.
    property bool priorFailed: false

    // Short name for log lines, e.g. "thumb[3]" / "popup[1]".
    property string label: ""

    // Seconds after which a renderer process is recycled: once it is this
    // old, a Frozen unwanted view is discarded right away instead of after
    // discardDelaySec, and reloads fresh on its next appearance. 0 = never.
    // Only a view that leaves the screen regularly (rotating thumbnail) is
    // ever recycled — a visible or wanted view is never discarded.
    property int recycleAfterSec: 0

    // Renderer pid last sampled, and Date.now() ms when that renderer was
    // first seen (0 while there is none). Sampled at every decision point,
    // i.e. each time the view is shown or hidden, so a rotating
    // thumbnail's age is accurate to within one rotation.
    property double _rendererPid: 0
    property double _rendererSinceMs: 0

    function _recycleDue() {
        const now = Date.now();
        const r = Policy.trackRenderer(ctl._rendererPid, ctl._rendererSinceMs,
                                       target ? Number(target.renderProcessPid) : 0, now);
        ctl._rendererPid = r.pid;
        ctl._rendererSinceMs = r.sinceMs;
        return Policy.isRecycleDue(ctl._rendererSinceMs, ctl.recycleAfterSec, now);
    }

    // Date.now() ms when the view entered Frozen; 0 when not frozen.
    property double _frozenAtMs: 0

    // True while _apply() runs, so the lifecycleStateChanged it causes is
    // not mistaken for an external change.
    property bool _applying: false

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
            const from = _stateName(target.lifecycleState);
            if (from !== action.setState) {
                console.debug(Log.lifecycle, "iframe-plasma[lifecycle] " + ctl.label + " "
                    + from + "->" + action.setState
                    + (action.reason ? " (" + action.reason + ")" : "")
                    + (action.reload ? " +reload" : ""));
            }
            ctl._applying = true;
            try {
                target.lifecycleState = _stateEnum(action.setState);
            } finally {
                ctl._applying = false;
            }
        }
        if (action.resetFrozenAtMs) _frozenAtMs = 0;
        if (action.frozenAtMs !== undefined) _frozenAtMs = action.frozenAtMs;
        if (action.reload) {
            try { target.reload(); } catch (e) { /* view gone */ }
        }
        if (action.scheduleMs !== undefined) {
            if (action.reason) {
                console.debug(Log.lifecycle, "iframe-plasma[lifecycle] " + ctl.label + " next step in "
                    + action.scheduleMs + " ms (" + action.reason + ")");
            }
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
            Date.now(),
            priorFailed,
            _recycleDue()));
    }

    onTargetChanged: _reevaluate()
    onDesiredActiveChanged: _reevaluate()
    Component.onCompleted: _reevaluate()

    function _onExternalChange() {
        if (!target) return;
        if (Policy.shouldReevaluateOnExternalChange(
                ctl.desiredActive, _phaseTimer.running, ctl._applying,
                _stateName(target.lifecycleState))) {
            _reevaluate();
        }
    }

    property Connections _targetSignals: Connections {
        target: ctl.target
        function onLifecycleStateChanged() { ctl._onExternalChange(); }
        function onRecommendedStateChanged() { ctl._onExternalChange(); }
    }

    property Timer _phaseTimer: Timer {
        repeat: false
        onTriggered: {
            const t = ctl.target;
            if (!t || ctl.desiredActive) return;
            ctl._apply(Policy.decideOnTimer(
                ctl._stateName(t.lifecycleState),
                ctl._stateName(t.recommendedState),
                ctl.freezeDelaySec,
                Date.now(),
                ctl.discardDelaySec,
                ctl._recycleDue()));
        }
    }
}
