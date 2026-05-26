/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Wheel-eater overlay for QQC ComboBox / SpinBox — sits transparent over
 * the control, accepts ONLY wheel events (clicks fall through via
 * acceptedButtons: Qt.NoButton), and marks every wheel event accepted so
 * scrolling never silently changes the control's value.
 *
 * The wheel is then forwarded to the surrounding scroller so list pages
 * can still be scrolled when the cursor sits on top of a wheel-blocked
 * control — a plain `wheel.accepted = true` is a propagation dead-end in
 * QML.
 *
 * We walk the parent chain and pick the first Flickable that is actually
 * overflowing (contentHeight > height). Inside a QQC.ScrollView wrapping
 * a ListView, the ListView itself is expanded to its full content height
 * (so contentH == height == "fit everything") and the OUTER Flickable
 * that the ScrollView creates is what scrolls — picking by overflow gets
 * us to that wrapper without having to name it.
 *
 * Usage:
 *     QQC.ComboBox {
 *         ...
 *         NoWheel {}
 *     }
 *
 * Set `scrollTarget` only when the walk would otherwise pick a wrong
 * Flickable; pass the actually-scrolling Flickable (not a fixed-height
 * inner ListView).
 */
import QtQuick

MouseArea {
    id: root
    property Item scrollTarget: null

    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: (wheel) => {
        // Touchpads send pixelDelta; mice send angleDelta (120 units/notch).
        // /8 ≈ 15 px per notch — matches the QQC2 ScrollBar default step.
        const dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y
                 : wheel.angleDelta.y / 8
        const t = root.scrollTarget || root._findOverflowingFlickable(root.parent)
        if (t) {
            t.contentY = Math.max(0, Math.min(t.contentHeight - t.height,
                                              t.contentY - dy))
        }
        wheel.accepted = true
    }
    // Duck-type Flickable via `returnToBounds()` (public Flickable method) and
    // require actual overflow so we skip ListViews that the surrounding
    // ScrollView expanded to fit their full content.
    function _findOverflowingFlickable(item) {
        let p = item
        while (p) {
            if (typeof p.returnToBounds === "function"
                && p.contentY !== undefined
                && p.contentHeight !== undefined
                && p.height !== undefined
                && p.contentHeight > p.height) {
                return p
            }
            p = p.parent
        }
        return null
    }
    // Above the control's own content so wheels are intercepted first.
    z: 9999
}
