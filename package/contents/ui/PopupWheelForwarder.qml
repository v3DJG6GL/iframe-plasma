/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick

// Wheel forwarder for open ComboBox popups. By default, a wheel landing
// on an expanded dropdown goes to the popup's internal ListView; if the
// option list isn't long enough to scroll, the wheel is eaten and the
// page beneath refuses to move. ConfigUrls instantiates this inside each
// ComboBox's popup contentItem on first open: it lets the popup keep
// scrolling when it actually overflows, but otherwise closes the popup
// and forwards the wheel to `scrollTarget`'s nearest overflowing scroller.
WheelHandler {
    property QtObject combo
    property Item scrollTarget
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: (event) => {
        const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y
                                            : event.angleDelta.y / 8
        const list = parent
        if (list && list.contentHeight !== undefined
                 && list.height !== undefined
                 && list.contentHeight > list.height) {
            // Popup itself is scrollable — scroll its ListView
            // directly. We cannot rely on `event.accepted = false`
            // to propagate to the underlying Flickable: WheelHandler
            // runs at the post-delivery handler layer, so the
            // sibling/parent Flickable does not re-process the
            // event. Move contentY ourselves. Combo rows share one
            // height, so the popup list's origin stays at 0.
            list.contentY = Math.max(0,
                Math.min(list.contentHeight - list.height,
                         list.contentY - dy))
            event.accepted = true
            return
        }
        if (combo && combo.popup) combo.popup.close()
        let p = scrollTarget
        while (p) {
            if (typeof p.returnToBounds === "function"
                && p.contentY !== undefined
                && p.contentHeight !== undefined
                && p.height !== undefined
                && p.contentHeight > p.height) {
                // Origin-relative extent, as in ScrollForwardingWheelHandler:
                // the URL list's mixed-height cards move originY off 0, and
                // a [0, …] clamp made the page jump on a one-notch scroll.
                const o = p.originY !== undefined ? p.originY : 0
                p.contentY = Math.max(o,
                    Math.min(o + p.contentHeight - p.height,
                             p.contentY - dy))
                break
            }
            p = p.parent
        }
        event.accepted = true
    }
}
