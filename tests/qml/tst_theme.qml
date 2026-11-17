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

    // ----- a family listed only under foundry suffixes still matches --
    // Two installs of one family from different foundries make Qt list it
    // only as "Family [foundry]"; the bare name must still be kept.
    function test_monoFamily_foundrySuffixedOnly_keepsPreferred() {
        compare(Theme.monoFamily("ZZZ Dup Mono", ["Sans", "ZZZ Dup Mono [urw]", "ZZZ Dup Mono [UKWN]"]),
                "ZZZ Dup Mono");
    }

    function test_monoFamily_foundrySuffix_isNotAPrefixMatch() {
        compare(Theme.monoFamily("ZZZ Dup", ["ZZZ Dup Mono [urw]"]), "monospace");
    }

    function test_monoFamily_hostFoundrySuffixedFamily_keepsPreferred() {
        const bracketed = Qt.fontFamilies().find(f => / \[[^\]]*\]$/.test(f));
        if (bracketed === undefined)
            skip("no foundry-suffixed family installed on this host");
        const bare = bracketed.replace(/ \[[^\]]*\]$/, "");
        compare(Theme.monoFamily(bare), bare);
    }

    // ----- the resolved tokens are always a real family or the alias --
    function test_fontTokens_resolveToInstalledFamilyOrAlias() {
        const bare = Qt.fontFamilies().map(f => f.replace(/ \[[^\]]*\]$/, ""));
        verify(Theme.fontHeader === "monospace" || bare.indexOf(Theme.fontHeader) >= 0);
        verify(Theme.fontBody === "monospace" || bare.indexOf(Theme.fontBody) >= 0);
    }
}
