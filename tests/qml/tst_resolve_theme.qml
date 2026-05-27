/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/UrlUtils.js" as U

TestCase {
    name: "ResolveTheme"

    function _bg(r, g, b) { return { r: r, g: g, b: b }; }

    // ----- pickThemeForBackground: explicit modes win ----------------
    function test_explicitLight_ignoresBg() {
        compare(U.pickThemeForBackground("light", _bg(0, 0, 0)), "light");
    }
    function test_explicitDark_ignoresBg() {
        compare(U.pickThemeForBackground("dark", _bg(1, 1, 1)), "dark");
    }

    // ----- auto: luminance threshold at 0.5 --------------------------
    function test_auto_blackBg_picksDark() {
        compare(U.pickThemeForBackground("auto", _bg(0, 0, 0)), "dark");
    }
    function test_auto_whiteBg_picksLight() {
        compare(U.pickThemeForBackground("auto", _bg(1, 1, 1)), "light");
    }
    function test_auto_midGreyBg_picksLight() {
        // Rec. 601 luminance at (0.5, 0.5, 0.5) == 0.5 → branch is `< 0.5` so
        // exactly 0.5 falls to "light".
        compare(U.pickThemeForBackground("auto", _bg(0.5, 0.5, 0.5)), "light");
    }
    function test_auto_belowMidGrey_picksDark() {
        compare(U.pickThemeForBackground("auto", _bg(0.49, 0.49, 0.49)), "dark");
    }
    function test_auto_pureRed_picksDark() {
        // 0.2126 * 1 = 0.2126 < 0.5 → dark.
        compare(U.pickThemeForBackground("auto", _bg(1, 0, 0)), "dark");
    }
    function test_auto_pureGreen_picksLight() {
        // 0.7152 * 1 = 0.7152 >= 0.5 → light.
        compare(U.pickThemeForBackground("auto", _bg(0, 1, 0)), "light");
    }
    function test_auto_pureBlue_picksDark() {
        // 0.0722 * 1 = 0.0722 < 0.5 → dark.
        compare(U.pickThemeForBackground("auto", _bg(0, 0, 1)), "dark");
    }

    // ----- unknown mode falls through to auto path -------------------
    function test_unknownMode_treatedAsAuto() {
        compare(U.pickThemeForBackground("solarized", _bg(0, 0, 0)), "dark");
        compare(U.pickThemeForBackground("solarized", _bg(1, 1, 1)), "light");
    }

    // ----- nullish guards --------------------------------------------
    function test_nullBgColor_picksDark() {
        // Defensive default — pickThemeForBackground returns "dark" when bg
        // is unusable rather than NaN-comparison weirdness.
        compare(U.pickThemeForBackground("auto", null), "dark");
        compare(U.pickThemeForBackground("auto", undefined), "dark");
    }
    function test_partialBgColor_treatedAsZero() {
        // Missing channels coerce to 0; effectively a dark colour.
        compare(U.pickThemeForBackground("auto", {}), "dark");
        compare(U.pickThemeForBackground("auto", { r: 1 }), "dark");
    }

    // ----- substituteTheme: dollar placeholder -----------------------
    function test_substituteTheme_singleOccurrence() {
        compare(U.substituteTheme("https://g/?theme=${theme}", "dark"),
                "https://g/?theme=dark");
    }
    function test_substituteTheme_multipleOccurrences() {
        compare(U.substituteTheme("${theme}-${theme}-${theme}", "light"),
                "light-light-light");
    }
    function test_substituteTheme_noPlaceholder_unchanged() {
        compare(U.substituteTheme("https://g/?a=b", "dark"),
                "https://g/?a=b");
    }
    function test_substituteTheme_inFragment() {
        compare(U.substituteTheme("https://g/#theme=${theme}", "dark"),
                "https://g/#theme=dark");
    }
    function test_substituteTheme_inHostname() {
        // User error, but documented: only the placeholder is substituted.
        compare(U.substituteTheme("https://${theme}.example.com", "light"),
                "https://light.example.com");
    }
    function test_substituteTheme_emptyTheme() {
        compare(U.substituteTheme("https://g/?theme=${theme}", ""),
                "https://g/?theme=");
    }
    function test_substituteTheme_coercesNonString() {
        // String() coercion in substituteTheme — ensures null doesn't throw.
        compare(U.substituteTheme(null, "x"), "null");
    }
    function test_substituteTheme_doesNotMatchSimilarTokens() {
        // ${theme2} and $theme (no braces) must not be touched.
        compare(U.substituteTheme("a=${theme2}&b=$theme", "X"),
                "a=${theme2}&b=$theme");
    }
}
