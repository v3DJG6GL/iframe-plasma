/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Source-level regression guard for the canvas crop ordering. CropEngine.js
 * is .pragma library and its IIFE body needs a live DOM to execute, so these
 * tests assert the *shape* of the generated JS rather than running it — enough
 * to lock the "crop first, blank the page only on success" contract that fixed
 * the frozen-blank Grafana thumbnail.
 */
import QtQuick
import QtTest
import "../../package/contents/ui/CropEngine.js" as CropEngine

TestCase {
    name: "CropEngine"

    function test_buildApplyJs_returnsCallableIife() {
        const js = CropEngine.buildApplyJs(".u-wrap > canvas", { scaleMode: "stretch", keywords: [] });
        verify(js.length > 0);
        // The body is an IIFE invoked with the selector + opts appended.
        verify(js.indexOf("(\".u-wrap > canvas\"") !== -1);
    }

    function test_canvasBranch_cropsBeforeBlankingPage() {
        const js = CropEngine.buildApplyJs(".u-wrap > canvas", {});
        const idxCrop = js.indexOf("if (cropAxes(el))");
        const idxBlank = js.indexOf("setAttribute('data-ifp-thumb','1')");
        verify(idxCrop !== -1);   // crop-first guard present
        verify(idxBlank !== -1);  // page-blank still happens...
        // ...but only INSIDE the success branch, i.e. after the cropAxes test.
        verify(idxCrop < idxBlank);
    }

    function test_canvasBranch_reportsCanvasPendingOnNoFrame() {
        const js = CropEngine.buildApplyJs(".u-wrap > canvas", {});
        // The not-yet-painted path un-blanks and returns the distinct status
        // the QML side keys off to show a placeholder + arm a retry.
        verify(js.indexOf("return 'canvas-pending'") !== -1);
        verify(js.indexOf("removeAttribute('data-ifp-thumb')") !== -1);
    }

    function test_cropAxes_returnsBooleanNotBareReturn() {
        const js = CropEngine.buildApplyJs(".u-wrap > canvas", {});
        // cropAxes must signal success/failure so apply() can decide whether
        // to blank the page. A regression to a bare `return;` would silently
        // re-introduce the blank-page-before-frame bug.
        verify(js.indexOf("return false;") !== -1);
        verify(js.indexOf("return true;") !== -1);
    }

    function test_iifeReturn_propagatesCanvasPending() {
        const js = CropEngine.buildApplyJs(".u-wrap > canvas", {});
        // The top-level return distinguishes canvas-pending from the
        // unmatched-selector 'observing' case.
        verify(js.indexOf("first === 'canvas-pending'") !== -1);
    }
}
