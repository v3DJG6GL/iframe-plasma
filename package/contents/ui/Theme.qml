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

    // Preferred: Hack + IBM Plex Mono. Neither ships by default on every
    // distro, and Qt resolves an unknown family to the default *sans*
    // (QML font.family can't carry a monospace style hint), so a missing
    // font falls back to fontconfig's "monospace" alias explicitly.
    // A family installed from more than one foundry is listed only as
    // "Family [foundry]" entries, so also compare with that suffix stripped;
    // the bare name is still what Qt resolves. `families` is a test seam.
    function monoFamily(preferred, families) {
        const list = families || Qt.fontFamilies();
        return list.some(f => f === preferred || f.replace(/ \[[^\]]*\]$/, "") === preferred)
            ? preferred : "monospace";
    }
    readonly property string fontHeader: monoFamily("Hack")
    readonly property string fontBody:   monoFamily("IBM Plex Mono")

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
