/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Decorative overlay — a 1px subtle border + four accent-coloured "L" marks
 * at the corners. Crisp at every DPI (uses plain Rectangles, not Unicode
 * box-drawing chars which de-sync at fractional scaling).
 *
 * Stack inside a Kirigami.AbstractCard or Rectangle to add a terminal-ish
 * frame: just `CornerFrame {}` as a child fills the parent.
 */
import QtQuick

Item {
    id: root
    anchors.fill: parent

    property color borderColor: Theme.fgMute
    property color cornerColor: Theme.accent
    property int   cornerLen:   10
    property int   borderWidth: 1
    property int   radius:      Theme.radius

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: root.borderColor
        border.width: root.borderWidth
        radius: root.radius
    }

    Repeater {
        // 4 corners × 2 arms each = 8 small Rectangles.
        model: [
            { ax: 0,            ay: 0,             dx:  1, dy:  1 },   // top-left
            { ax: root.width,   ay: 0,             dx: -1, dy:  1 },   // top-right
            { ax: 0,            ay: root.height,   dx:  1, dy: -1 },   // bot-left
            { ax: root.width,   ay: root.height,   dx: -1, dy: -1 }    // bot-right
        ]
        delegate: Item {
            x: modelData.ax
            y: modelData.ay
            Rectangle {           // horizontal arm
                x: modelData.dx < 0 ? -root.cornerLen : 0
                y: modelData.dy < 0 ? -1 : 0
                width:  root.cornerLen
                height: 1
                color: root.cornerColor
            }
            Rectangle {           // vertical arm
                x: modelData.dx < 0 ? -1 : 0
                y: modelData.dy < 0 ? -root.cornerLen : 0
                width:  1
                height: root.cornerLen
                color: root.cornerColor
            }
        }
    }
}
