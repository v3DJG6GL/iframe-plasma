/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/QueryUtils.js" as Q

TestCase {
    name: "QueryHelpers"

    // ===== applyRefreshChoice: override kept on a URL re-push =========
    function test_applyRefreshChoice_noChoice_keepsUrl() {
        compare(Q.applyRefreshChoice("https://g/d/x?refresh=30s&a=1", ""),
                "https://g/d/x?refresh=30s&a=1");
    }
    function test_applyRefreshChoice_off_stripsRefresh() {
        compare(Q.applyRefreshChoice("https://g/d/x?theme=dark&refresh=30s", "off"),
                "https://g/d/x?theme=dark");
    }
    function test_applyRefreshChoice_interval_replacesRefresh() {
        compare(Q.applyRefreshChoice("https://g/d/x?refresh=30s#v", "5m"),
                "https://g/d/x?refresh=5m#v");
    }
    function test_applyRefreshChoice_interval_addsRefresh() {
        compare(Q.applyRefreshChoice("https://g/d/x", "1m"), "https://g/d/x?refresh=1m");
    }

    // ===== editQuery: insertions =====================================
    function test_editQuery_addToEmptyQuery() {
        compare(Q.editQuery("https://x", { a: "1" }), "https://x?a=1");
    }
    function test_editQuery_addSecond() {
        compare(Q.editQuery("https://x?a=1", { b: "2" }), "https://x?a=1&b=2");
    }
    function test_editQuery_addPreservesOrder() {
        compare(Q.editQuery("https://x?a=1&b=2", { c: "3" }),
                "https://x?a=1&b=2&c=3");
    }

    // ===== editQuery: replacements ===================================
    function test_editQuery_replaceFirst() {
        compare(Q.editQuery("https://x?a=1&b=2", { a: "9" }),
                "https://x?a=9&b=2");
    }
    function test_editQuery_replaceMiddle() {
        compare(Q.editQuery("https://x?a=1&b=2&c=3", { b: "9" }),
                "https://x?a=1&b=9&c=3");
    }
    function test_editQuery_replaceMultipleKeysAtOnce() {
        const out = Q.editQuery("https://x?a=1&b=2", { a: "9", b: "8" });
        compare(out, "https://x?a=9&b=8");
    }
    function test_editQuery_firstOccurrenceWins_dupesDropped() {
        // Duplicate `a` keys: first kept (with new value), second dropped.
        const out = Q.editQuery("https://x?a=1&a=2", { a: "9" });
        compare(out, "https://x?a=9");
    }

    // ===== editQuery: removals =======================================
    function test_editQuery_removeWithNull() {
        compare(Q.editQuery("https://x?a=1&b=2", { a: null }),
                "https://x?b=2");
    }
    function test_editQuery_removeWithUndefined() {
        compare(Q.editQuery("https://x?a=1&b=2", { a: undefined }),
                "https://x?b=2");
    }
    function test_editQuery_removeOnly_dropsLeadingQ() {
        compare(Q.editQuery("https://x?a=1", { a: null }), "https://x");
    }
    function test_editQuery_removeAbsent_isNoOp() {
        compare(Q.editQuery("https://x?a=1", { b: null }), "https://x?a=1");
    }

    // ===== editQuery: fragment / flag-style params ===================
    function test_editQuery_preservesFragment() {
        compare(Q.editQuery("https://x?a=1#anchor", { a: "9" }),
                "https://x?a=9#anchor");
    }
    function test_editQuery_appendKeepsFragment() {
        compare(Q.editQuery("https://x?a=1#h", { b: "2" }),
                "https://x?a=1&b=2#h");
    }
    function test_editQuery_flagStyleParamSurvives() {
        // `&kiosk` (no value) is unrelated; should not be touched when we
        // edit `a`.
        compare(Q.editQuery("https://x?a=1&kiosk", { a: "9" }),
                "https://x?a=9&kiosk");
    }
    function test_editQuery_urlEncodesValue() {
        compare(Q.editQuery("https://x", { from: "now-1h" }),
                "https://x?from=now-1h");
        compare(Q.editQuery("https://x", { q: "a b" }),
                "https://x?q=a%20b");
        compare(Q.editQuery("https://x", { q: "a&b" }),
                "https://x?q=a%26b");
    }

    // ===== readQuery =================================================
    function test_readQuery_present() {
        compare(Q.readQuery("https://x?a=1&b=2", "a"), "1");
        compare(Q.readQuery("https://x?a=1&b=2", "b"), "2");
    }
    function test_readQuery_absent_returnsEmpty() {
        compare(Q.readQuery("https://x?a=1", "missing"), "");
    }
    function test_readQuery_noQuery_returnsEmpty() {
        compare(Q.readQuery("https://x", "any"), "");
    }
    function test_readQuery_decodesValue() {
        compare(Q.readQuery("https://x?q=a%20b", "q"), "a b");
        compare(Q.readQuery("https://x?q=%E2%9C%94", "q"), "✔");
    }
    function test_readQuery_flagStyleParam_returnsEmpty() {
        compare(Q.readQuery("https://x?kiosk", "kiosk"), "");
    }
    function test_readQuery_ignoresFragment() {
        compare(Q.readQuery("https://x?a=1#anchor", "a"), "1");
        compare(Q.readQuery("https://x?a=1#b=2", "b"), "");
    }
    function test_readQuery_firstOccurrence() {
        compare(Q.readQuery("https://x?a=1&a=2", "a"), "1");
    }

    // ===== canonicalUrlKey ===========================================
    // The configured URL as typed must key equal to Chromium's form of it,
    // or WebTab's SPA-login return check never fires.
    function test_canonicalUrlKey_bareOrigin_getsSlash() {
        compare(Q.canonicalUrlKey("https://app.example.com"),
                Q.canonicalUrlKey("https://app.example.com/"));
        compare(Q.canonicalUrlKey("https://app.example.com"), "https://app.example.com/");
    }
    function test_canonicalUrlKey_emptyPathWithQuery_getsSlash() {
        compare(Q.canonicalUrlKey("https://app.example.com?x=1"), "https://app.example.com/?x=1");
    }
    function test_canonicalUrlKey_defaultPortDropped() {
        compare(Q.canonicalUrlKey("https://app.example.com:443/x"), "https://app.example.com/x");
        compare(Q.canonicalUrlKey("http://app.example.com:80/x"), "http://app.example.com/x");
    }
    function test_canonicalUrlKey_nonDefaultPortKept() {
        compare(Q.canonicalUrlKey("https://app.example.com:80/x"), "https://app.example.com:80/x");
        compare(Q.canonicalUrlKey("http://app.example.com:443/x"), "http://app.example.com:443/x");
        compare(Q.canonicalUrlKey("https://app.example.com:4430/x"), "https://app.example.com:4430/x");
        compare(Q.canonicalUrlKey("https://[::443]/x"), "https://[::443]/x");
    }
    function test_canonicalUrlKey_schemeAndHostLowercased_pathKept() {
        compare(Q.canonicalUrlKey("HTTPS://App.Example.COM/Dash?Q=A"), "https://app.example.com/Dash?Q=A");
    }
    function test_canonicalUrlKey_hashStripped() {
        compare(Q.canonicalUrlKey("https://app.example.com/d#panel"), "https://app.example.com/d");
        compare(Q.canonicalUrlKey("https://app.example.com#x"), "https://app.example.com/");
    }
    function test_canonicalUrlKey_differentPagesStayDifferent() {
        verify(Q.canonicalUrlKey("https://app.example.com/login")
               !== Q.canonicalUrlKey("https://app.example.com/"));
    }
    function test_canonicalUrlKey_nonUrl_passesThrough() {
        compare(Q.canonicalUrlKey(""), "");
        compare(Q.canonicalUrlKey("about:blank"), "about:blank");
    }

    // ===== matchTimeRangePreset ======================================
    function test_matchPreset_24h() { compare(Q.matchTimeRangePreset("now-24h", "now"), "24h"); }
    function test_matchPreset_5m()  { compare(Q.matchTimeRangePreset("now-5m",  "now"), "5m"); }
    function test_matchPreset_90d() { compare(Q.matchTimeRangePreset("now-90d", "now"), "90d"); }
    function test_matchPreset_emptyBoth() {
        compare(Q.matchTimeRangePreset("", ""), "");
    }
    function test_matchPreset_customAbsoluteDates() {
        compare(Q.matchTimeRangePreset("2024-01-01", "2024-02-01"), "custom");
    }
    function test_matchPreset_fromOnly_isCustom() {
        compare(Q.matchTimeRangePreset("now-24h", ""), "custom");
    }
    function test_matchPreset_nonStandardToValue_isCustom() {
        compare(Q.matchTimeRangePreset("now-24h", "now-1h"), "custom");
    }
    function test_matchPreset_compoundFrom_isCustom() {
        // "now-2h-30m" doesn't match the simple preset pattern.
        compare(Q.matchTimeRangePreset("now-2h-30m", "now"), "custom");
    }
}
