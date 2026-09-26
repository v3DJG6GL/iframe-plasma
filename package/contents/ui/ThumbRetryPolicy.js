/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pure decision core for the panel thumbnail's bounded-backoff retry
 * (thumbRetryTimer in main.qml), so tests/qml/tst_thumbretry.qml can drive
 * the load → crop → retry sequence without a WebEngineView.
 *
 * The budget must only be refilled once a frame is confirmed on screen. It
 * used to be reset on every LoadSucceeded: a thumbnail whose canvas never
 * painted in time then looped load → "canvas-pending" → 3 s retry → load
 * forever (each reload also pinning the view Active, so it never froze).
 */
.pragma library

const BACKOFF_MS = [3000, 10000, 30000];

// Delay for the next retry, or -1 once the schedule is exhausted.
function backoffMs(attempt) {
    return (attempt >= 0 && attempt < BACKOFF_MS.length) ? BACKOFF_MS[attempt] : -1;
}

// Retry counter after a LoadSucceeded. A page that still has to be
// cropped has not proven it renders yet, so its budget is kept; a page
// with no crop step is done and gets a fresh budget.
function attemptAfterLoadSucceeded(attempt, needsCrop) {
    return needsCrop ? attempt : 0;
}

// Whether an applyThumbCrop result downgrades the slot to "blank": the
// canvas matched but had no frame yet, on a still-clean load, and no CROP
// landed while the runJavaScript call was in flight.
function shouldMarkBlank(applyResult, loadStatus, cropEpochUnchanged) {
    return applyResult === "canvas-pending" && loadStatus === "ok" && cropEpochUnchanged;
}

// Whether a blank slot arms a reload retry. Only the thumbnail on screen
// retries: a hidden page does not paint, so reloading it cannot help —
// it reloads on its next landing instead (WebViewLifecycle.priorFailed).
function shouldArmBlankRetry(isCurrent, observable) {
    return isCurrent && observable;
}
