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
    p.contentY = _clamp(p, p.contentY - dy);
}

function _clamp(p, y) {
    const o = p.originY !== undefined ? p.originY : 0;
    const lo = o - (p.topMargin || 0);
    const hi = o + p.contentHeight + (p.bottomMargin || 0) - p.height;
    return Math.max(lo, Math.min(hi, y));
}

// Scroll the nearest overflowing ancestor of `item` the least distance
// that brings `item` fully into view (its top, when taller than the
// viewport). In the KCM pages the row ListView sits in a ScrollView that
// SimpleKCM expands to full content height, so ListView.currentIndex
// cannot scroll it: only the page Flickable around it moves.
function ensureVisible(item) {
    const p = item ? findOverflowing(item.parent) : null;
    if (!p || !p.contentItem) return;
    const top = item.mapToItem(p.contentItem, 0, 0).y;
    let y = p.contentY;
    if (top + item.height > y + p.height) y = top + item.height - p.height;
    if (top < y) y = top;
    p.contentY = _clamp(p, y);
}
