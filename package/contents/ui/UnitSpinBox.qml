/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * QQC.SpinBox wrapper that makes typing multi-digit suffixed values work.
 *
 * The default org.kde.desktop QQC2 SpinBox style commits value-from-text on
 * EVERY keystroke (see /usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/desktop/
 * SpinBox.qml lines 70-73: `onTextEdited: controlRoot.value = ...`). With
 * a `textFromValue` that appends a suffix, every keystroke re-runs
 * textFromValue("30") → "30 seconds", overwriting the TextField buffer and
 * parking the cursor past the suffix. The user cannot type "300".
 *
 * Additionally the default TextField inside SpinBox does not consume Return,
 * so Enter bubbles to the parent KCM Dialog and triggers OK → close.
 *
 * Fix: override `contentItem` with our own TextField that
 *   1. does NOT write back to value on every keystroke — only on
 *      editingFinished (focus loss, Enter), arrow-button click, or wheel
 *   2. consumes Enter/Return after committing, so it doesn't close the
 *      hosting KCM dialog
 *   3. re-syncs the displayed text from value when value changes (e.g. via
 *      up/down arrows), but leaves the buffer alone while the user is typing
 *
 * Two ways to configure the display:
 *
 *   suffix: " s"                         // simple "<value> s" rendering
 *   textFormatter: (v) => i18np("%1 second", "%1 seconds", v)
 *                                        // overrides suffix; full control,
 *                                        // useful for i18np plurals or a
 *                                        // sentinel like "disabled" at v=0.
 *
 * If both are set, textFormatter wins.
 *
 * Usage:
 *   UnitSpinBox { from: 1; to: 3600; value: 30; suffix: " s" }
 *
 *   UnitSpinBox {
 *       from: 0; to: 65535; value: 0
 *       textFormatter: (v) => v === 0 ? i18n("disabled") : String(v)
 *   }
 */
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Templates as T

QQC.SpinBox {
    id: root

    property string suffix: ""
    property var textFormatter: null

    editable: true
    // IntValidator on raw integers; our TextField shows "<n><suffix>" but the
    // validator never sees the buffer (we route through valueFromText on
    // commit). Keep ImhDigitsOnly so soft keyboards offer a numpad.
    inputMethodHints: Qt.ImhDigitsOnly

    textFromValue: (v, _locale) => {
        if (textFormatter) return textFormatter(v);
        return String(v) + suffix;
    }

    valueFromText: (text, _locale) => {
        const n = parseInt(String(text).replace(/[^0-9-]/g, ""), 10);
        if (isNaN(n)) return value;
        return Math.max(from, Math.min(to, n));
    }

    contentItem: T.TextField {
        id: edit
        // One-shot init + re-sync on programmatic value changes (arrow
        // buttons, wheel, external binding). We deliberately do NOT bind
        // `text:` to displayText — that would clobber the buffer on every
        // keystroke once the style's onTextEdited fires.
        text: root.textFromValue(root.value, root.locale)
        Connections {
            target: root
            function onValueChanged() {
                if (!edit.activeFocus) {
                    edit.text = root.textFromValue(root.value, root.locale);
                }
            }
        }

        font: root.font
        color: palette.text
        selectionColor: palette.highlight
        selectedTextColor: palette.highlightedText
        horizontalAlignment: Qt.AlignHCenter
        verticalAlignment: Qt.AlignVCenter
        selectByMouse: true
        hoverEnabled: false
        readOnly: !root.editable
        // No `validator:` — we accept any keystroke and sanitize at commit.
        inputMethodHints: root.inputMethodHints

        // Commit on focus loss. When focus returns to a clean state, re-render
        // the canonical formatted text (so "30abc" → "30 seconds").
        onEditingFinished: {
            root.value = root.valueFromText(edit.text, root.locale);
            root.valueModified();
            edit.text = root.textFromValue(root.value, root.locale);
        }

        // Consume Enter/Return so the parent KCM Dialog's default OK button
        // does NOT fire. We commit explicitly, then accept the event.
        Keys.onReturnPressed: (event) => { commitAndAccept(event); }
        Keys.onEnterPressed:  (event) => { commitAndAccept(event); }

        function commitAndAccept(event) {
            root.value = root.valueFromText(edit.text, root.locale);
            root.valueModified();
            edit.text = root.textFromValue(root.value, root.locale);
            event.accepted = true;
        }
    }

    NoWheel {}
}
