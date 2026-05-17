/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Design tokens — Tokyo Night Storm palette + monospace headers/body.
 * Imported via the sibling qmldir as a QML singleton: `Theme.bg`, `Theme.fg`, etc.
 */
pragma Singleton
import QtQuick

QtObject {
    // Tokyo Night Storm palette
    readonly property color bg:          "#24283b"
    readonly property color bgAlt:       "#1f2335"
    readonly property color surface:     "#2a2f43"
    readonly property color surfaceHi:   "#343a52"
    readonly property color fg:          "#c0caf5"
    readonly property color fgDim:       "#7e89ac"
    readonly property color fgMute:      "#545c7e"
    readonly property color accent:      "#7aa2f7"   // blue
    readonly property color success:     "#9ece6a"
    readonly property color warning:     "#e0af68"
    readonly property color error:       "#f7768e"
    readonly property color magenta:     "#bb9af7"

    // Hack + IBM Plex Mono are both verified installed via fc-list on
    // Ubuntu 25.10. On systems without them, Qt's own font matching falls
    // back to the platform default monospace.
    readonly property string fontHeader: "Hack"
    readonly property string fontBody:   "IBM Plex Mono"

    // Spacing scale
    readonly property int s2: 8
    readonly property int s3: 12
    readonly property int s4: 16

    // Component metrics
    readonly property int tabHeight:     30
    readonly property int toolbarHeight: 26
    readonly property int chipHeight:    18
    readonly property int chipPadding:   6
}
