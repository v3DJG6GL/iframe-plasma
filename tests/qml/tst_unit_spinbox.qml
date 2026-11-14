/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui"

// UnitSpinBox keeps its own text buffer and writes it to `value` on commit
// only. A step made while the editor has focus (arrow key, arrow button)
// must start from what was typed and must end up in the buffer: a stale
// buffer is committed back over the stepped value on focus loss.
Item {
    id: scene
    width: 400
    height: 200

    Column {
        UnitSpinBox { id: spin; from: 1; to: 3600; value: 30; suffix: " s" }
        UnitSpinBox {
            id: sentinel
            from: 0; to: 10; value: 0
            textFormatter: (v) => v === 0 ? "never" : v + " min"
        }
        TextInput { id: elsewhere; width: 100; height: 20 }
    }

    TestCase {
        name: "UnitSpinBox"
        when: windowShown

        function init() {
            elsewhere.forceActiveFocus();
            // A programmatic change while unfocused, as a config load makes
            // one: from here on the editor text is a plain buffer.
            spin.value = 31;
            spin.value = 30;
            sentinel.value = 1;
            sentinel.value = 0;
            compare(spin.contentItem.text, "30 s");
            compare(sentinel.contentItem.text, "never");
        }

        // Replace the editor's text by typing `keys` (Qt.Key_* codes).
        function typeOver(box, keys) {
            box.contentItem.selectAll();
            for (const k of keys) keyClick(k);
        }

        function test_arrowKeysWhileFocused_stepIsKept() {
            spin.contentItem.forceActiveFocus();
            tryCompare(spin.contentItem, "activeFocus", true);
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Up);
            compare(spin.value, 32);
            compare(spin.contentItem.text, "32 s");
            elsewhere.forceActiveFocus();
            compare(spin.value, 32);
            compare(spin.contentItem.text, "32 s");
        }

        function test_arrowKeyAfterTyping_stepsFromTypedValue() {
            spin.contentItem.forceActiveFocus();
            tryCompare(spin.contentItem, "activeFocus", true);
            typeOver(spin, [Qt.Key_5, Qt.Key_0]);
            keyClick(Qt.Key_Down);
            compare(spin.value, 49);
            compare(spin.contentItem.text, "49 s");
            elsewhere.forceActiveFocus();
            compare(spin.value, 49);
        }

        function test_arrowButtonAfterTyping_stepsFromTypedValue() {
            spin.contentItem.forceActiveFocus();
            tryCompare(spin.contentItem, "activeFocus", true);
            typeOver(spin, [Qt.Key_5, Qt.Key_0]);
            mouseClick(spin.up.indicator);
            compare(spin.value, 51);
            compare(spin.contentItem.text, "51 s");
            elsewhere.forceActiveFocus();
            compare(spin.value, 51);
        }

        function test_arrowKeyAtLimit_typedValueIsClampedNotLost() {
            spin.contentItem.forceActiveFocus();
            tryCompare(spin.contentItem, "activeFocus", true);
            typeOver(spin, [Qt.Key_9, Qt.Key_9, Qt.Key_9, Qt.Key_9]);
            keyClick(Qt.Key_Up);
            compare(spin.value, 3600);
            elsewhere.forceActiveFocus();
            compare(spin.value, 3600);
            compare(spin.contentItem.text, "3600 s");
        }

        function test_arrowKeysOnSentinelText() {
            sentinel.contentItem.forceActiveFocus();
            tryCompare(sentinel.contentItem, "activeFocus", true);
            keyClick(Qt.Key_Up);
            compare(sentinel.value, 1);
            compare(sentinel.contentItem.text, "1 min");
            keyClick(Qt.Key_Down);
            compare(sentinel.value, 0);
            compare(sentinel.contentItem.text, "never");
        }

        // The reason the editor is not bound to displayText: typing must not
        // write `value` (and re-render the buffer) per keystroke.
        function test_typing_commitsOnlyOnReturn() {
            spin.contentItem.forceActiveFocus();
            tryCompare(spin.contentItem, "activeFocus", true);
            typeOver(spin, [Qt.Key_3, Qt.Key_0, Qt.Key_0]);
            compare(spin.value, 30);
            compare(spin.contentItem.text, "300");
            keyClick(Qt.Key_Return);
            compare(spin.value, 300);
            compare(spin.contentItem.text, "300 s");
        }
    }
}
