/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Wheel-eater overlay for QQC ComboBox / SpinBox — sits transparent over
 * the control, accepts ONLY wheel events (clicks fall through via
 * acceptedButtons: Qt.NoButton), and marks every wheel event accepted so
 * scrolling never silently changes the control's value. Lets the
 * surrounding ScrollView scroll normally because the wheel is consumed
 * AT the control only; outside its bounds the page still scrolls.
 *
 * Usage:
 *     QQC.ComboBox {
 *         ...
 *         NoWheel {}
 *     }
 */
import QtQuick

MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: (wheel) => { wheel.accepted = true }
    // Above the control's own content so wheels are intercepted first.
    z: 9999
}
