/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui"

TestCase {
    name: "Theme"

    // ----- monoFamily: missing preferred font → monospace alias -------
    function test_monoFamily_missingFont_fallsBackToMonospaceAlias() {
        compare(Theme.monoFamily("ZZZ Nonexistent Mono Font"), "monospace");
    }

    function test_monoFamily_installedFont_keepsPreferred() {
        const installed = Qt.fontFamilies()[0];
        verify(installed !== undefined);
        compare(Theme.monoFamily(installed), installed);
    }

    // ----- the resolved tokens are always a real family or the alias --
    function test_fontTokens_resolveToInstalledFamilyOrAlias() {
        const families = Qt.fontFamilies();
        verify(Theme.fontHeader === "monospace" || families.indexOf(Theme.fontHeader) >= 0);
        verify(Theme.fontBody === "monospace" || families.indexOf(Theme.fontBody) >= 0);
    }
}
