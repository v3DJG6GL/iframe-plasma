/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/GrafanaUrl.js" as G

TestCase {
    name: "GrafanaUrlRewrite"

    // Convenience: full pipeline with all toggles off.
    function _off() {
        return { convertDSolo: false, timeRange: "",
                 kiosk: false, theme: false,
                 refresh: false, refreshSeconds: 0,
                 hideLogo: false, hidePanelMenu: false };
    }

    // ===== Reject path =================================================
    function test_emptyInput_returnsEmpty() { compare(G.transform("", _off()), ""); }
    function test_whitespaceOnly_returnsEmpty() { compare(G.transform("   ", _off()), ""); }
    function test_nullInput_returnsEmpty() { compare(G.transform(null, _off()), ""); }
    function test_undefinedInput_returnsEmpty() { compare(G.transform(undefined, _off()), ""); }
    function test_CR_rejected() {
        // Trailing \r is stripped by trim(); the reject guard catches
        // CR/LF mid-string — that's the actual injection vector the
        // guard exists to defend.
        compare(G.transform("https://g/d/abc\rslug?viewPanel=panel-1", _off()), "");
    }
    function test_LF_rejected() {
        compare(G.transform("https://g/d/abc\nslug?viewPanel=panel-1", _off()), "");
    }
    function test_NUL_rejected() {
        compare(G.transform("https://g/d/abc/slug\0", _off()), "");
    }
    function test_passthroughTrimsWhitespace() {
        compare(G.transform("  https://x  ", _off()), "https://x");
    }

    // ===== /d/ → /d-solo/ rewrite =====================================
    function test_dSolo_rewriteHappy() {
        const opts = _off(); opts.convertDSolo = true;
        const out = G.transform("https://g/d/abc/slug?viewPanel=panel-7", opts);
        compare(out, "https://g/d-solo/abc/slug?panelId=7");
    }
    function test_dSolo_clonePanelSuffix() {
        const opts = _off(); opts.convertDSolo = true;
        const out = G.transform("https://g/d/abc/slug?viewPanel=panel-7-clone2", opts);
        // -clone2 suffix dropped; only base panel ID kept.
        compare(out, "https://g/d-solo/abc/slug?panelId=7");
    }
    function test_dSolo_noViewPanel_isNoOp() {
        const opts = _off(); opts.convertDSolo = true;
        compare(G.transform("https://g/d/abc/slug", opts),
                "https://g/d/abc/slug");
    }
    function test_dSolo_alreadyDsolo_isNoOp() {
        const opts = _off(); opts.convertDSolo = true;
        compare(G.transform("https://g/d-solo/abc/slug?panelId=2", opts),
                "https://g/d-solo/abc/slug?panelId=2");
    }
    function test_dSolo_gotoLink_noRewrite() {
        // /goto/<id> short links don't have /d/ to rewrite; helper just
        // preserves them (a UI warning in the KCM is shown separately).
        const opts = _off(); opts.convertDSolo = true;
        compare(G.transform("https://g/goto/abc", opts),
                "https://g/goto/abc");
    }
    function test_dSolo_disabledByOpt() {
        const opts = _off(); // convertDSolo: false
        compare(G.transform("https://g/d/abc/slug?viewPanel=panel-7", opts),
                "https://g/d/abc/slug?viewPanel=panel-7");
    }
    function test_dSolo_preservesOtherParams() {
        const opts = _off(); opts.convertDSolo = true;
        const out = G.transform("https://g/d/abc/slug?orgId=1&viewPanel=panel-7&extra=keep", opts);
        compare(out, "https://g/d-solo/abc/slug?orgId=1&extra=keep&panelId=7");
    }
    function test_dSolo_viewPanel_fragmentPreserved_noOrphan() {
        // Fragment after viewPanel — strip regex's terminator must accept
        // "#" so the orphan viewPanel doesn't survive alongside the
        // appended panelId.
        const opts = _off(); opts.convertDSolo = true;
        const out = G.transform("https://g/d/abc/slug?viewPanel=panel-7#anchor", opts);
        compare(out, "https://g/d-solo/abc/slug?panelId=7#anchor");
    }
    function test_dSolo_viewPanel_fragmentPreserved_withClone() {
        const opts = _off(); opts.convertDSolo = true;
        const out = G.transform("https://g/d/abc/slug?viewPanel=panel-7-clone2#anchor", opts);
        compare(out, "https://g/d-solo/abc/slug?panelId=7#anchor");
    }
    function test_dSolo_viewPanel_fragmentPreserved_otherParamsBefore() {
        const opts = _off(); opts.convertDSolo = true;
        const out = G.transform("https://g/d/abc/slug?orgId=1&viewPanel=panel-7#anchor", opts);
        compare(out, "https://g/d-solo/abc/slug?orgId=1&panelId=7#anchor");
    }

    // ===== Time-range presets =========================================
    function test_timeRange_addsFromTo() {
        const opts = _off(); opts.timeRange = "24h";
        const out = G.transform("https://g/d-solo/x/y", opts);
        compare(out, "https://g/d-solo/x/y?from=now-24h&to=now");
    }
    function test_timeRange_stripsExistingFromTo() {
        const opts = _off(); opts.timeRange = "1h";
        const out = G.transform("https://g/d-solo/x/y?from=2024-01-01&to=2024-02-01", opts);
        compare(out, "https://g/d-solo/x/y?from=now-1h&to=now");
    }
    function test_timeRange_emptyPreset_isNoOp() {
        const opts = _off(); opts.timeRange = "";
        compare(G.transform("https://g/d-solo/x/y", opts),
                "https://g/d-solo/x/y");
    }
    // All eleven preset suffixes the KCM exposes.
    function test_timeRange_5m()   { const o=_off(); o.timeRange="5m";   compare(G.transform("https://x", o), "https://x?from=now-5m&to=now"); }
    function test_timeRange_15m()  { const o=_off(); o.timeRange="15m";  compare(G.transform("https://x", o), "https://x?from=now-15m&to=now"); }
    function test_timeRange_30m()  { const o=_off(); o.timeRange="30m";  compare(G.transform("https://x", o), "https://x?from=now-30m&to=now"); }
    function test_timeRange_1h()   { const o=_off(); o.timeRange="1h";   compare(G.transform("https://x", o), "https://x?from=now-1h&to=now"); }
    function test_timeRange_6h()   { const o=_off(); o.timeRange="6h";   compare(G.transform("https://x", o), "https://x?from=now-6h&to=now"); }
    function test_timeRange_12h()  { const o=_off(); o.timeRange="12h";  compare(G.transform("https://x", o), "https://x?from=now-12h&to=now"); }
    function test_timeRange_24h()  { const o=_off(); o.timeRange="24h";  compare(G.transform("https://x", o), "https://x?from=now-24h&to=now"); }
    function test_timeRange_7d()   { const o=_off(); o.timeRange="7d";   compare(G.transform("https://x", o), "https://x?from=now-7d&to=now"); }
    function test_timeRange_30d()  { const o=_off(); o.timeRange="30d";  compare(G.transform("https://x", o), "https://x?from=now-30d&to=now"); }
    function test_timeRange_90d()  { const o=_off(); o.timeRange="90d";  compare(G.transform("https://x", o), "https://x?from=now-90d&to=now"); }

    // ===== Kiosk ======================================================
    function test_kiosk_added() {
        const opts = _off(); opts.kiosk = true;
        compare(G.transform("https://g/d-solo/x/y", opts),
                "https://g/d-solo/x/y?kiosk");
    }
    function test_kiosk_appendsWithExistingQuery() {
        const opts = _off(); opts.kiosk = true;
        compare(G.transform("https://g/d-solo/x/y?orgId=1", opts),
                "https://g/d-solo/x/y?orgId=1&kiosk");
    }
    function test_kiosk_alreadyPresentValueless_noDuplicate() {
        const opts = _off(); opts.kiosk = true;
        compare(G.transform("https://g/d-solo/x/y?kiosk", opts),
                "https://g/d-solo/x/y?kiosk");
    }
    function test_kiosk_alreadyPresentWithValue_noDuplicate() {
        const opts = _off(); opts.kiosk = true;
        compare(G.transform("https://g/d-solo/x/y?kiosk=1", opts),
                "https://g/d-solo/x/y?kiosk=1");
    }
    function test_kiosk_hostnameNoFalsePositive() {
        // kiosk.example.com host must not match the param-anchored regex.
        const opts = _off(); opts.kiosk = true;
        compare(G.transform("https://kiosk.example.com/d-solo/x", opts),
                "https://kiosk.example.com/d-solo/x?kiosk");
    }
    function test_kiosk_paramPrefixNoFalsePositive() {
        // kioskMode=1 must not match.
        const opts = _off(); opts.kiosk = true;
        compare(G.transform("https://g/x?kioskMode=1", opts),
                "https://g/x?kioskMode=1&kiosk");
    }
    function test_kiosk_fragmentPreserved() {
        const opts = _off(); opts.kiosk = true;
        compare(G.transform("https://g/x#anchor", opts),
                "https://g/x?kiosk#anchor");
    }

    // ===== Theme placeholder ==========================================
    function test_theme_addsPlaceholder() {
        const opts = _off(); opts.theme = true;
        compare(G.transform("https://g/d-solo/x", opts),
                "https://g/d-solo/x?theme=${theme}");
    }
    function test_theme_alreadyPresent_noDuplicate() {
        const opts = _off(); opts.theme = true;
        compare(G.transform("https://g/x?theme=dark", opts),
                "https://g/x?theme=dark");
    }
    function test_theme_widgetThemeNoFalsePositive() {
        const opts = _off(); opts.theme = true;
        compare(G.transform("https://g/x?widgetTheme=dark", opts),
                "https://g/x?widgetTheme=dark&theme=${theme}");
    }

    // ===== Refresh ====================================================
    function test_refresh_added() {
        const opts = _off(); opts.refresh = true; opts.refreshSeconds = 30;
        compare(G.transform("https://g/x", opts),
                "https://g/x?refresh=30s");
    }
    function test_refresh_stripsExisting() {
        const opts = _off(); opts.refresh = true; opts.refreshSeconds = 5;
        compare(G.transform("https://g/x?refresh=10s", opts),
                "https://g/x?refresh=5s");
    }
    function test_refresh_disabled_doesNotStrip() {
        const opts = _off(); opts.refresh = false;
        compare(G.transform("https://g/x?refresh=10s", opts),
                "https://g/x?refresh=10s");
    }

    // ===== hideLogo + hidePanelMenu ===================================
    function test_hideLogo_added() {
        const opts = _off(); opts.hideLogo = true;
        compare(G.transform("https://g/x", opts),
                "https://g/x?hideLogo=true");
    }
    function test_hideLogo_alreadyPresent_noDuplicate() {
        const opts = _off(); opts.hideLogo = true;
        compare(G.transform("https://g/x?hideLogo=false", opts),
                "https://g/x?hideLogo=false");
    }
    function test_hidePanelMenu_added() {
        const opts = _off(); opts.hidePanelMenu = true;
        compare(G.transform("https://g/x", opts),
                "https://g/x?_ifp_hidePanelMenu=1");
    }
    function test_hidePanelMenu_alreadyPresent_noDuplicate() {
        const opts = _off(); opts.hidePanelMenu = true;
        compare(G.transform("https://g/x?_ifp_hidePanelMenu=0", opts),
                "https://g/x?_ifp_hidePanelMenu=0");
    }

    // ===== Combined pipeline (full feature stack) ====================
    function test_fullPipeline_endToEnd() {
        const opts = {
            convertDSolo: true, timeRange: "24h",
            kiosk: true, theme: true,
            refresh: true, refreshSeconds: 30,
            hideLogo: true, hidePanelMenu: true,
        };
        const out = G.transform("https://g/d/abc/slug?orgId=1&viewPanel=panel-7", opts);
        // Order: viewPanel→panelId, then from/to, kiosk (valueless),
        // theme, refresh, hideLogo, hidePanelMenu.
        compare(out, "https://g/d-solo/abc/slug?orgId=1&panelId=7&from=now-24h&to=now&kiosk&theme=${theme}&refresh=30s&hideLogo=true&_ifp_hidePanelMenu=1");
    }
    function test_fullPipeline_gotoLink_paramsApplied() {
        // /goto/<id> can't be d-solo-rewritten client-side, but every
        // other managed param still applies (Grafana 302-preserves query).
        const opts = {
            convertDSolo: true, timeRange: "1h",
            kiosk: true, theme: false,
            refresh: false, refreshSeconds: 0,
            hideLogo: false, hidePanelMenu: false,
        };
        const out = G.transform("https://g/goto/abc", opts);
        compare(out, "https://g/goto/abc?from=now-1h&to=now&kiosk");
    }

    // ===== splitFragment / appendParam / stripParam ===================
    function test_splitFragment_noFrag() { compare(G.splitFragment("https://x?a=1"), ["https://x?a=1", ""]); }
    function test_splitFragment_withFrag() { compare(G.splitFragment("https://x?a=1#anchor"), ["https://x?a=1", "#anchor"]); }
    function test_splitFragment_emptyFrag() { compare(G.splitFragment("https://x#"), ["https://x", "#"]); }
    function test_appendParam_firstParam() { compare(G.appendParam("https://x", "a", "1"), "https://x?a=1"); }
    function test_appendParam_secondParam() { compare(G.appendParam("https://x?a=1", "b", "2"), "https://x?a=1&b=2"); }
    function test_appendParam_preservesFragment() {
        compare(G.appendParam("https://x?a=1#h", "b", "2"), "https://x?a=1&b=2#h");
    }
    function test_stripParam_first()   { compare(G.stripParam("https://x?a=1&b=2", "a"), "https://x?b=2"); }
    function test_stripParam_middle()  { compare(G.stripParam("https://x?a=1&b=2&c=3", "b"), "https://x?a=1&c=3"); }
    function test_stripParam_last()    { compare(G.stripParam("https://x?a=1&b=2", "b"), "https://x?a=1"); }
    function test_stripParam_only()    { compare(G.stripParam("https://x?a=1", "a"), "https://x"); }
    function test_stripParam_absent()  { compare(G.stripParam("https://x?a=1", "missing"), "https://x?a=1"); }
    function test_stripParam_preservesFragment() {
        compare(G.stripParam("https://x?a=1&b=2#h", "a"), "https://x?b=2#h");
    }
    // Adjacent duplicates — Run-#1 fix would have left one survivor.
    function test_stripParam_consecutiveHeadDupes_allRemoved() {
        compare(G.stripParam("https://x?panelId=1&panelId=2", "panelId"), "https://x");
    }
    function test_stripParam_threeDupesScattered_allRemoved() {
        compare(G.stripParam("https://x?panelId=1&panelId=2&panelId=3", "panelId"), "https://x");
    }
    function test_stripParam_dupesWithOtherParams_allRemoved() {
        compare(G.stripParam("https://x?panelId=1&panelId=2&other=keep", "panelId"),
                "https://x?other=keep");
    }
    function test_stripParam_preservesValuelessFlag() {
        compare(G.stripParam("https://x?kiosk&a=1", "a"), "https://x?kiosk");
    }
    // Full-pipeline: dupe input must collapse to a single panelId.
    function test_dSolo_preExistingDupePanelIds_collapsed() {
        const opts = _off(); opts.convertDSolo = true;
        const out = G.transform("https://g/d/abc/slug?panelId=1&panelId=2&viewPanel=panel-7", opts);
        compare(out, "https://g/d-solo/abc/slug?panelId=7");
    }
}
