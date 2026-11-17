/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Shared scroll maths for the wheel forwarders (NoWheel,
 * ScrollForwardingWheelHandler, PopupWheelForwarder), which move a
 * Flickable's contentY themselves.
 *
 * The range is Flickable's own: [originY - topMargin,
 * originY + contentHeight + bottomMargin - height]. A ListView with
 * mixed-height delegates moves originY off 0, and KCM.SimpleKCM /
 * Kirigami.ScrollablePage put the page padding in top/bottomMargin (and
 * take it out of contentHeight); dropping either made a forwarded wheel
 * miss the ends, or jump the page back from its real bottom.
 */
.pragma library

// Duck-typed Flickable (public returnToBounds()) that actually overflows,
// margins included (as SimpleKCM's __flickableOverflows). The overflow
// test skips ListViews a surrounding ScrollView expanded to full height.
function overflows(p) {
    return !!p && typeof p.returnToBounds === "function"
        && p.contentY !== undefined
        && p.contentHeight !== undefined
        && p.height !== undefined
        && p.contentHeight + (p.topMargin || 0) + (p.bottomMargin || 0) > p.height;
}

// First overflowing Flickable from `item` up the parent chain, or null.
function findOverflowing(item) {
    let p = item;
    while (p) {
        if (overflows(p)) return p;
        p = p.parent;
    }
    return null;
}

// Scroll `p` by a wheel delta `dy` (positive = up), clamped to its range.
function scrollBy(p, dy) {
    const o = p.originY !== undefined ? p.originY : 0;
    const lo = o - (p.topMargin || 0);
    const hi = o + p.contentHeight + (p.bottomMargin || 0) - p.height;
    p.contentY = Math.max(lo, Math.min(hi, p.contentY - dy));
}
