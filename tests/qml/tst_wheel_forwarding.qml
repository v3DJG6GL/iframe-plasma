/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui"
import "../../package/contents/ui/WheelScroll.js" as WheelScroll

// ScrollForwardingWheelHandler, NoWheel and PopupWheelForwarder scroll the
// nearest overflowing
// Flickable themselves. A ListView with mixed-height delegates moves its
// originY away from 0, and its valid contentY range becomes
// [originY, originY + contentHeight - height]; clamping to [0, …] left the
// first or last cards unreachable by wheel (and made the popup forwarder
// jump the page). The targets here are duck-typed Flickables
// (returnToBounds + contentY/contentHeight/originY), the same shape the
// helpers detect, so originY can be set directly.
Item {
    id: scene
    width: 400
    height: 400

    Item {
        id: handlerTarget
        width: 200; height: 100
        property real contentY: 0
        property real contentHeight: 1000
        property real originY: 0
        property real topMargin: 0
        property real bottomMargin: 0
        function returnToBounds() {}
        Rectangle {
            id: handlerChild
            anchors.fill: parent
            ScrollForwardingWheelHandler {}
        }
    }

    Item {
        id: noWheelTarget
        y: 200
        width: 200; height: 100
        property real contentY: 0
        property real contentHeight: 1000
        property real originY: 0
        property real topMargin: 0
        property real bottomMargin: 0
        function returnToBounds() {}
        Rectangle {
            id: noWheelChild
            anchors.fill: parent
            NoWheel {}
        }
    }

    // A combo whose popup list does not overflow: the forwarder closes the
    // popup and scrolls `scrollTarget` (the URL list in ConfigUrls).
    QtObject {
        id: fakeCombo
        property QtObject popup: QtObject {
            property int closeCount: 0
            function close() { closeCount++; }
        }
    }

    Item {
        id: popupTarget
        x: 210; y: 0
        width: 150; height: 100
        property real contentY: 0
        property real contentHeight: 1000
        property real originY: 0
        property real topMargin: 0
        property real bottomMargin: 0
        function returnToBounds() {}
    }

    Rectangle {
        id: popupList
        x: 210; y: 200
        width: 150; height: 100
        PopupWheelForwarder {
            combo: fakeCombo
            scrollTarget: popupTarget
        }
    }

    // The KCM row-list shape: SimpleKCM's page Flickable around a ListView
    // expanded to its full content height, so only the page scrolls.
    ListModel { id: rowModel }
    Flickable {
        id: pageFlick
        y: 300
        width: 400; height: 100
        contentHeight: rowList.height
        ListView {
            id: rowList
            width: parent.width
            height: contentHeight
            interactive: false
            model: rowModel
            delegate: Rectangle { width: 100; height: 60 }
        }
    }

    TestCase {
        name: "WheelForwarding"
        when: windowShown

        // One notch up (angleDelta 120 → 15 px) / down.
        function wheelUp(item)   { mouseWheel(item, 10, 10, 0, 120); }
        function wheelDown(item) { mouseWheel(item, 10, 10, 0, -120); }

        // The margin tests below change margins / contentHeight; every
        // other test assumes the zero-margin, 1000-px defaults (and sets
        // its own originY; the margin tests rely on 0).
        function init() {
            for (const t of [handlerTarget, noWheelTarget, popupTarget]) {
                t.originY = 0;
                t.topMargin = 0;
                t.bottomMargin = 0;
                t.contentHeight = 1000;
            }
        }

        // ===== top/bottomMargin: Flickable's real range ==============
        // KCM.SimpleKCM / ScrollablePage put the page padding in the
        // flickable's bottomMargin (and take it out of contentHeight), so
        // the real range is [originY - topMargin,
        // originY + contentHeight + bottomMargin - height]. A forwarded
        // wheel down at the real bottom (1000 + 6 - 100 = 906) moved the
        // page UP to 900.
        function test_handler_wheelDownAtRealBottomStaysPut() {
            handlerTarget.bottomMargin = 6;
            handlerTarget.contentY = 906;
            wheelDown(handlerChild);
            compare(handlerTarget.contentY, 906);
        }
        function test_handler_reachesBottomMargin() {
            handlerTarget.bottomMargin = 6;
            handlerTarget.contentY = 895;
            wheelDown(handlerChild);
            compare(handlerTarget.contentY, 906);
        }
        function test_handler_reachesTopMargin() {
            handlerTarget.topMargin = 6;
            handlerTarget.contentY = 5;
            wheelUp(handlerChild);
            compare(handlerTarget.contentY, -6);
        }
        function test_noWheel_wheelDownAtRealBottomStaysPut() {
            noWheelTarget.bottomMargin = 6;
            noWheelTarget.contentY = 906;
            wheelDown(noWheelChild);
            compare(noWheelTarget.contentY, 906);
        }
        function test_noWheel_reachesTopMargin() {
            noWheelTarget.topMargin = 6;
            noWheelTarget.contentY = 5;
            wheelUp(noWheelChild);
            compare(noWheelTarget.contentY, -6);
        }
        function test_noWheel_overflowByMarginOnlyScrolls() {
            // contentHeight == height: only the margins make it scrollable
            // (as SimpleKCM's own __flickableOverflows counts them).
            noWheelTarget.contentHeight = 100;
            noWheelTarget.bottomMargin = 6;
            noWheelTarget.contentY = 0;
            wheelDown(noWheelChild);
            compare(noWheelTarget.contentY, 6);
        }
        function test_popupForwarder_wheelDownAtRealBottomStaysPut() {
            popupTarget.bottomMargin = 6;
            popupTarget.contentY = 906;
            wheelDown(popupList);
            compare(popupTarget.contentY, 906);
        }

        function test_handler_scrollsAboveZeroWhenOriginNegative() {
            handlerTarget.originY = -500;
            handlerTarget.contentY = -200;
            wheelUp(handlerChild);
            compare(handlerTarget.contentY, -215);
        }
        function test_handler_stopsAtOriginTop() {
            handlerTarget.originY = -500;
            handlerTarget.contentY = -490;
            wheelUp(handlerChild);
            compare(handlerTarget.contentY, -500);
        }
        function test_handler_reachesBottomWithPositiveOrigin() {
            // Bottom extent = originY + contentHeight - height = 1200.
            handlerTarget.originY = 300;
            handlerTarget.contentY = 1190;
            wheelDown(handlerChild);
            compare(handlerTarget.contentY, 1200);
        }
        function test_handler_zeroOriginUnchanged() {
            handlerTarget.originY = 0;
            handlerTarget.contentY = 5;
            wheelUp(handlerChild);
            compare(handlerTarget.contentY, 0);
        }

        function test_noWheel_scrollsAboveZeroWhenOriginNegative() {
            noWheelTarget.originY = -500;
            noWheelTarget.contentY = -200;
            wheelUp(noWheelChild);
            compare(noWheelTarget.contentY, -215);
        }
        function test_noWheel_reachesBottomWithPositiveOrigin() {
            noWheelTarget.originY = 300;
            noWheelTarget.contentY = 1190;
            wheelDown(noWheelChild);
            compare(noWheelTarget.contentY, 1200);
        }
        function test_noWheel_doesNotOverscrollPastOriginExtent() {
            // Bottom extent with a negative origin = -500 + 1000 - 100 = 400.
            noWheelTarget.originY = -500;
            noWheelTarget.contentY = 395;
            wheelDown(noWheelChild);
            compare(noWheelTarget.contentY, 400);
        }

        function test_popupForwarder_keepsNegativeOrigin() {
            popupTarget.originY = -500;
            popupTarget.contentY = -200;
            wheelUp(popupList);
            compare(popupTarget.contentY, -215);
            verify(fakeCombo.popup.closeCount > 0);
        }
        function test_popupForwarder_reachesBottomWithPositiveOrigin() {
            popupTarget.originY = 300;
            popupTarget.contentY = 1190;
            wheelDown(popupList);
            compare(popupTarget.contentY, 1200);
        }

        // ===== ensureVisible: reveal a newly added KCM row ===========
        // "Add URL" / "Add profile" set ListView.currentIndex, which
        // cannot scroll a list the page expanded to full height: the new
        // card stayed below the fold. ensureVisible moves the page.
        function _rows(n) {
            rowModel.clear();
            for (let i = 0; i < n; i++) rowModel.append({});
            rowList.forceLayout();
            pageFlick.contentY = 0;
        }
        function test_ensureVisible_scrollsPageToAppendedRow() {
            _rows(4);
            rowModel.append({});
            rowList.forceLayout();
            tryCompare(pageFlick, "contentHeight", 300);
            WheelScroll.ensureVisible(rowList.itemAtIndex(4));
            // Row 4 spans 240..300 in a 100-px viewport.
            compare(pageFlick.contentY, 200);
        }
        function test_ensureVisible_visibleRowStaysPut() {
            _rows(5);
            pageFlick.contentY = 30;
            WheelScroll.ensureVisible(rowList.itemAtIndex(1));
            compare(pageFlick.contentY, 30);
        }
        function test_ensureVisible_rowAboveScrollsUp() {
            _rows(5);
            pageFlick.contentY = 200;
            WheelScroll.ensureVisible(rowList.itemAtIndex(1));
            compare(pageFlick.contentY, 60);
        }
        function test_ensureVisible_nullItemIgnored() {
            _rows(5);
            pageFlick.contentY = 40;
            WheelScroll.ensureVisible(null);
            compare(pageFlick.contentY, 40);
        }
    }
}
