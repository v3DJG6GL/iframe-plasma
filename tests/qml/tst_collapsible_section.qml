/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui"

// The section header must toggle on Return/Enter and swallow the key.
// AbstractButton reacts to Space only; an unhandled Return travels up to
// Plasma's AppletConfiguration, whose Keys.onReturnPressed runs the
// accept action — saving every page and closing the config dialog.
// `outer` stands in for that ancestor.
Item {
    id: scene
    width: 400
    height: 300

    Item {
        id: outer
        anchors.fill: parent
        property int returns: 0
        property int enters: 0
        Keys.onReturnPressed: outer.returns++
        Keys.onEnterPressed: outer.enters++

        CollapsibleSection {
            id: section
            width: 300
            title: "Thumbnail"
            Item { width: 10; height: 10 }
        }
    }

    TestCase {
        name: "CollapsibleSection"
        when: windowShown

        function init() {
            section.expanded = false;
            outer.returns = 0;
            outer.enters = 0;
            const header = section.children[0];
            header.forceActiveFocus();
            tryCompare(header, "activeFocus", true);
        }

        function test_return_togglesAndIsConsumed() {
            keyClick(Qt.Key_Return);
            compare(section.expanded, true);
            compare(outer.returns, 0);
            keyClick(Qt.Key_Return);
            compare(section.expanded, false);
            compare(outer.returns, 0);
        }

        function test_enter_togglesAndIsConsumed() {
            keyClick(Qt.Key_Enter);
            compare(section.expanded, true);
            compare(outer.enters, 0);
        }

        function test_space_stillToggles() {
            keyClick(Qt.Key_Space);
            compare(section.expanded, true);
        }
    }
}
