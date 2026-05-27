/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/UrlUtils.js" as U

TestCase {
    name: "ParseSafe"

    // ----- isSafeTabUrl -----
    function test_isSafeTabUrl_acceptsHttp()   { verify(U.isSafeTabUrl("http://example.com/")); }
    function test_isSafeTabUrl_acceptsHttps()  { verify(U.isSafeTabUrl("https://example.com/")); }
    function test_isSafeTabUrl_acceptsHttpsMixed() { verify(U.isSafeTabUrl("HTTPS://x")); }
    function test_isSafeTabUrl_rejectsJavascript() { verify(!U.isSafeTabUrl("javascript:alert(1)")); }
    function test_isSafeTabUrl_rejectsData()        { verify(!U.isSafeTabUrl("data:text/html,x")); }
    function test_isSafeTabUrl_rejectsFile()        { verify(!U.isSafeTabUrl("file:///etc/passwd")); }
    function test_isSafeTabUrl_rejectsBlob()        { verify(!U.isSafeTabUrl("blob:abc")); }
    function test_isSafeTabUrl_rejectsScheme0()     { verify(!U.isSafeTabUrl("")); }
    function test_isSafeTabUrl_rejectsNonString()   { verify(!U.isSafeTabUrl(null) && !U.isSafeTabUrl(undefined) && !U.isSafeTabUrl(42)); }
    function test_isSafeTabUrl_rejectsLeadingSpace() { verify(!U.isSafeTabUrl(" https://x")); }

    // ----- parseTabs -----
    function test_parseTabs_emptyString()         { compare(U.parseTabs(""), []); }
    function test_parseTabs_emptyArrayLiteral()   { compare(U.parseTabs("[]"), []); }
    function test_parseTabs_malformedJSON_returnsEmpty() {
        const out = U.parseTabs("{not json");
        compare(out, []);
    }
    function test_parseTabs_nonArrayJSON_returnsEmpty() {
        compare(U.parseTabs('{"label":"x"}'), []);
    }
    function test_parseTabs_filtersUnsafeUrls() {
        const out = U.parseTabs('[{"url":"https://ok"},{"url":"javascript:1"},{"url":"https://ok2"}]');
        compare(out.length, 2);
        compare(out[0].url, "https://ok");
        compare(out[1].url, "https://ok2");
    }
    function test_parseTabs_skipsNullEntries() {
        const out = U.parseTabs('[null,{"url":"https://ok"}]');
        compare(out.length, 1);
        compare(out[0].url, "https://ok");
    }
    function test_parseTabs_keepsExtraFields() {
        const out = U.parseTabs('[{"url":"https://ok","label":"L","custom":42}]');
        compare(out[0].label, "L");
        compare(out[0].custom, 42);
    }
    function test_parseTabs_singleEntry() {
        const out = U.parseTabs('[{"url":"https://kde.org","label":"KDE"}]');
        compare(out.length, 1);
        compare(out[0].label, "KDE");
    }

    // ----- parseAuthProfiles -----
    function test_parseAuthProfiles_emptyString()       { compare(U.parseAuthProfiles(""), []); }
    function test_parseAuthProfiles_emptyArrayLiteral() { compare(U.parseAuthProfiles("[]"), []); }
    function test_parseAuthProfiles_malformed_returnsEmpty() { compare(U.parseAuthProfiles("{not"), []); }
    function test_parseAuthProfiles_nonArrayJSON_returnsEmpty() {
        compare(U.parseAuthProfiles('{"id":"x"}'), []);
    }
    function test_parseAuthProfiles_keepsAllRows() {
        const out = U.parseAuthProfiles('[{"id":"a","authType":"basic"},{"id":"b","authType":"bearer"}]');
        compare(out.length, 2);
        compare(out[0].id, "a");
        compare(out[1].authType, "bearer");
    }
    function test_parseAuthProfiles_doesNotValidateAuthType() {
        // Unknown authType is preserved; consumer code falls back via
        // authSpec() — testing tolerance here.
        const out = U.parseAuthProfiles('[{"id":"x","authType":"oauth2"}]');
        compare(out[0].authType, "oauth2");
    }

    // ----- isGrafanaEmbed -----
    function test_isGrafanaEmbed_matchesDsolo() {
        verify(U.isGrafanaEmbed("https://grafana.example.com/d-solo/abc-123/dashboard?panelId=2"));
    }
    function test_isGrafanaEmbed_matchesD() {
        verify(U.isGrafanaEmbed("https://grafana.example.com/d/abc/slug?viewPanel=2"));
    }
    function test_isGrafanaEmbed_matchesWithUnderscores() {
        verify(U.isGrafanaEmbed("https://x/d/abc_123-de/slug"));
    }
    function test_isGrafanaEmbed_rejectsRandomUrl() {
        verify(!U.isGrafanaEmbed("https://kde.org/"));
    }
    function test_isGrafanaEmbed_rejectsEmpty() {
        verify(!U.isGrafanaEmbed(""));
        verify(!U.isGrafanaEmbed(null));
        verify(!U.isGrafanaEmbed(undefined));
    }
    function test_isGrafanaEmbed_rejectsGoto() {
        // /goto/<id> short links must be d-solo-rewritten by the helper;
        // the toolbar gate doesn't enable them.
        verify(!U.isGrafanaEmbed("https://grafana.example.com/goto/abc"));
    }
    function test_isGrafanaEmbed_dropsFragmentBeforeScanning() {
        // A hash-routed share URL whose `#fragment` happens to contain
        // `/d/<uid>/` must NOT false-positive — the regex scans only the
        // pre-fragment base. Same bug-class as Runs #15/#19 on the
        // transform/parseSettings/viewPanel-derive sites.
        verify(!U.isGrafanaEmbed("https://example.com/page#/d/abc/dashboard"));
        verify(!U.isGrafanaEmbed("https://example.com/x#/d-solo/abc/y"));
    }
    function test_isGrafanaEmbed_keepsRealGrafanaWithFragment() {
        // A real Grafana URL whose path matches the regex must still
        // pass even when a `#section=...` fragment is appended.
        verify(U.isGrafanaEmbed("https://grafana.example.com/d/abc/slug?orgId=1#section=2"));
    }
}
