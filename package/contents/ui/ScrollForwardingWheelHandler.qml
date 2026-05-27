/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick

// Forward a wheel event landing on this handler's parent up to the nearest
// ancestor that exposes Flickable-like properties (returnToBounds + contentY
// + contentHeight). Used in KCM forms where a tall ScrollView wraps a
// ListView whose contentHeight has been collapsed to match its visible
// height — wheel over a card / a gap / the empty tail must scroll the
// outer wrapper Flickable, not the inner ListView (whose contentH==h).
//
// Centralises what was previously inlined in ConfigUrls and ConfigAuth.
WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: (event) => {
        const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y
                 : event.angleDelta.y / 8
        let p = parent
        while (p) {
            if (typeof p.returnToBounds === "function"
                && p.contentY !== undefined
                && p.contentHeight !== undefined
                && p.height !== undefined
                && p.contentHeight > p.height) {
                p.contentY = Math.max(0,
                    Math.min(p.contentHeight - p.height,
                             p.contentY - dy))
                break
            }
            p = p.parent
        }
        event.accepted = true
    }
}
