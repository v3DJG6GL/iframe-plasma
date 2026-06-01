/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/UrlUtils.js" as U

TestCase {
    name: "AutoCycle"

    function _ok(label)      { return { label: label }; }
    function _excluded(label){ return { label: label, thumbMode: "excluded" }; }

    // ===== Empty / sentinel cases ====================================
    function test_emptyArray_returnsMinus1() {
        compare(U.nextCycleTabIndex(0, []), -1);
    }
    function test_nullTabs_returnsMinus1() {
        compare(U.nextCycleTabIndex(0, null), -1);
    }
    function test_undefinedTabs_returnsMinus1() {
        compare(U.nextCycleTabIndex(0, undefined), -1);
    }
    function test_singleTab_returnsMinus1() {
        compare(U.nextCycleTabIndex(0, [_ok("only")]), -1);
    }

    // ===== Two-tab simple case ======================================
    function test_twoTabs_fromZero_returnsOne() {
        compare(U.nextCycleTabIndex(0, [_ok("a"), _ok("b")]), 1);
    }
    function test_twoTabs_fromOne_returnsZero() {
        compare(U.nextCycleTabIndex(1, [_ok("a"), _ok("b")]), 0);
    }

    // ===== Many-tab modulo wrap-around ==============================
    function test_modulo_wrapsFromLastToFirst() {
        const tabs = [_ok("a"), _ok("b"), _ok("c")];
        compare(U.nextCycleTabIndex(2, tabs), 0);
    }
    function test_middle_steppingForward() {
        const tabs = [_ok("a"), _ok("b"), _ok("c"), _ok("d")];
        compare(U.nextCycleTabIndex(1, tabs), 2);
    }

    // ===== Excluded-tab skipping ====================================
    function test_skipsExcluded_picksNextAfter() {
        // [a, excluded, c] from 0 → skip 1 → land on 2.
        const tabs = [_ok("a"), _excluded("b"), _ok("c")];
        compare(U.nextCycleTabIndex(0, tabs), 2);
    }
    function test_skipsMultipleExcluded() {
        // [a, excluded, excluded, d] from 0 → land on 3.
        const tabs = [_ok("a"), _excluded("b"), _excluded("c"), _ok("d")];
        compare(U.nextCycleTabIndex(0, tabs), 3);
    }
    function test_skipsExcludedWithWrap() {
        // [excluded, b, excluded, d] from 1 → 3.
        const tabs = [_excluded("a"), _ok("b"), _excluded("c"), _ok("d")];
        compare(U.nextCycleTabIndex(1, tabs), 3);
    }

    // ===== "All excluded" → -1 ======================================
    function test_allOtherTabsExcluded_returnsMinus1() {
        const tabs = [_ok("current"), _excluded("b"), _excluded("c")];
        compare(U.nextCycleTabIndex(0, tabs), -1);
    }
    function test_allTabsExcluded_returnsMinus1() {
        const tabs = [_excluded("a"), _excluded("b")];
        compare(U.nextCycleTabIndex(0, tabs), -1);
    }

    // ===== Null / undefined tab entries =============================
    function test_nullEntriesSkipped() {
        // [null, b, null, d] from 0 → 1.
        const tabs = [null, _ok("b"), null, _ok("d")];
        compare(U.nextCycleTabIndex(0, tabs), 1);
    }

    // ===== Stale currentIndex (e.g. after tab deletion) =============
    function test_staleCurrentIndexBeyondLength_wrapsViaModulo() {
        const tabs = [_ok("a"), _ok("b"), _ok("c")];
        // currentIndex=5 normalises to 2; next is 0.
        compare(U.nextCycleTabIndex(5, tabs), 0);
    }
    function test_negativeCurrentIndex_normalisedPositive() {
        const tabs = [_ok("a"), _ok("b"), _ok("c")];
        // -1 normalises to 2; next is 0.
        compare(U.nextCycleTabIndex(-1, tabs), 0);
    }

    // ===== Runtime exclusion (live keyword hits) ====================
    function test_runtimeExcluded_objectShape_skipsLiveExcluded() {
        // {idx: true} object form — what main.qml uses for
        // _runtimeExcluded so QML bindings detect mutations.
        const tabs = [_ok("a"), _ok("b"), _ok("c")];
        const live = { 1: true };  // tab 1 currently shows a keyword
        compare(U.nextCycleTabIndex(0, tabs, live), 2);
    }
    function test_runtimeExcluded_timestampValue_skipsLiveExcluded() {
        // main.qml stores the exclusion time as the map value
        // ({idx: Date.now()}) so cycleTimer can expire stale entries;
        // nextCycleTabIndex only tests truthiness, so a millisecond
        // timestamp must read as "excluded" exactly like `true`.
        const tabs = [_ok("a"), _ok("b"), _ok("c")];
        const live = { 1: 1717200000000 };  // ms timestamp, truthy
        compare(U.nextCycleTabIndex(0, tabs, live), 2);
    }
    function test_runtimeExcluded_setShape_skipsLiveExcluded() {
        // Set form — duck-typed via `.has`.
        const tabs = [_ok("a"), _ok("b"), _ok("c")];
        const live = new Set([1]);
        compare(U.nextCycleTabIndex(0, tabs, live), 2);
    }
    function test_runtimeExcluded_combinedWithStaticExcluded() {
        // Tab 1 marked thumbMode=excluded, tab 2 is runtime-excluded
        // → wrap to 3.
        const tabs = [_ok("a"), _excluded("b"), _ok("c"), _ok("d")];
        const live = { 2: true };
        compare(U.nextCycleTabIndex(0, tabs, live), 3);
    }
    function test_runtimeExcluded_allOthersExcluded_returnsMinus1() {
        const tabs = [_ok("a"), _ok("b"), _ok("c")];
        const live = { 1: true, 2: true };
        compare(U.nextCycleTabIndex(0, tabs, live), -1);
    }
    function test_runtimeExcluded_nullParam_treatedAsNoLiveCheck() {
        // Back-compat: existing callers that pass no third arg keep
        // working unchanged.
        const tabs = [_ok("a"), _ok("b"), _ok("c")];
        compare(U.nextCycleTabIndex(0, tabs, null), 1);
        compare(U.nextCycleTabIndex(0, tabs, undefined), 1);
        compare(U.nextCycleTabIndex(0, tabs), 1);
    }
    function test_runtimeExcluded_emptySetFallsThroughUntouched() {
        const tabs = [_ok("a"), _ok("b"), _ok("c")];
        compare(U.nextCycleTabIndex(0, tabs, new Set()), 1);
        compare(U.nextCycleTabIndex(0, tabs, {}), 1);
    }
}
