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
    function test_parseTabs_filtersDisabled() {
        // enabled:false rows are dropped from the live tab set; enabled:true
        // and the rows that omit the field (legacy / default-on) survive.
        const out = U.parseTabs('[{"url":"https://a","enabled":true},{"url":"https://b","enabled":false},{"url":"https://c"}]');
        compare(out.length, 2);
        compare(out[0].url, "https://a");
        compare(out[1].url, "https://c");
    }
    function test_parseTabs_keepsMissingEnabled() {
        // Missing `enabled` defaults to on — a pre-feature config stays visible.
        const out = U.parseTabs('[{"url":"https://ok","label":"L"}]');
        compare(out.length, 1);
        compare(out[0].url, "https://ok");
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

    // ----- hostKey (must equal the C++ canonicalizeHost lookup key) -----
    function test_hostKey_data() {
        return [
            { tag: "plain https",            url: "https://example.com/x",        expected: "example.com" },
            { tag: "plain http",             url: "http://example.com/",          expected: "example.com" },
            { tag: "explicit default https", url: "https://example.com:443/x",    expected: "example.com" },
            { tag: "explicit default http",  url: "http://example.com:80/",       expected: "example.com" },
            { tag: "non-default port",       url: "https://example.com:9100/",    expected: "example.com:9100" },
            { tag: "https on 80",            url: "https://example.com:80/",      expected: "example.com:80" },
            { tag: "http on 443",            url: "http://example.com:443/",      expected: "example.com:443" },
            { tag: "uppercase",              url: "HTTPS://EXAMPLE.Com:8443/a",   expected: "example.com:8443" },
            { tag: "ipv6 default port",      url: "https://[::1]/",               expected: "[::1]" },
            { tag: "ipv6 explicit default",  url: "http://[fe80::1]:80/",         expected: "[fe80::1]" },
            { tag: "ipv6 with port",         url: "https://[::1]:9100/",          expected: "[::1]:9100" },
            { tag: "ipv6 uppercase",         url: "https://[2001:DB8::1]:443/",   expected: "[2001:db8::1]" },
            { tag: "userinfo ignored",       url: "https://user:pw@example.com/", expected: "example.com" }
        ];
    }
    function test_hostKey(data) {
        compare(U.hostKey(data.url), data.expected);
    }
    function test_hostKey_throwsOnUnparsableUrl() {
        // Callers rely on the throw to skip a tab whose URL has no host.
        let threw = false;
        try { U.hostKey("not a url"); } catch (e) { threw = true; }
        verify(threw);
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

    // ----- displayUrl (concise card-header subtitle) -----
    function test_displayUrl_stripsSchemeQueryFragment() {
        // The query string is the long, low-signal part — it must go.
        compare(U.displayUrl("https://grafana.example.com/d-solo/abc/dash?orgId=1&panelId=27&kiosk#x"),
                "grafana.example.com/d-solo/abc/dash");
    }
    function test_displayUrl_keepsHostAndPath() {
        compare(U.displayUrl("https://streamystats.example.com/servers/1/dashboard"),
                "streamystats.example.com/servers/1/dashboard");
    }
    function test_displayUrl_stripsHttp() {
        compare(U.displayUrl("http://x.example/path"), "x.example/path");
    }
    function test_displayUrl_dropsTrailingSlash() {
        compare(U.displayUrl("https://example.com/"), "example.com");
    }
    function test_displayUrl_placeholderCollapsesToEmpty() {
        // The "Add URL" default is the bare scheme placeholder; subtitle
        // must collapse to "" so the caller hides it.
        compare(U.displayUrl("https://"), "");
    }
    function test_displayUrl_handlesNullish() {
        compare(U.displayUrl(null), "");
        compare(U.displayUrl(undefined), "");
        compare(U.displayUrl(""), "");
    }
    function test_displayUrl_queryOnlyNoFragment() {
        compare(U.displayUrl("https://h.example/p?a=1"), "h.example/p");
    }
}
