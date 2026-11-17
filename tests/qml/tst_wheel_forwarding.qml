/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui"

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

    TestCase {
        name: "WheelForwarding"
        when: windowShown

        // One notch up (angleDelta 120 → 15 px) / down.
        function wheelUp(item)   { mouseWheel(item, 10, 10, 0, 120); }
        function wheelDown(item) { mouseWheel(item, 10, 10, 0, -120); }

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
    }
}
