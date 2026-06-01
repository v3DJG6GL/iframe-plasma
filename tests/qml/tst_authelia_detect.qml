/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui/QueryUtils.js" as Q

TestCase {
    name: "AutheliaDetect"

    function test_emptyAutheliaHost_false() {
        verify(!Q.isAutheliaHost("https://anywhere.com/", ""));
        verify(!Q.isAutheliaHost("https://anywhere.com/", null));
        verify(!Q.isAutheliaHost("https://anywhere.com/", undefined));
    }

    function test_exactHostMatch() {
        verify(Q.isAutheliaHost("https://auth.example.com/2fa", "auth.example.com"));
    }

    function test_subdomainMatch() {
        verify(Q.isAutheliaHost("https://sso.auth.example.com/login",
                                 "auth.example.com"));
    }

    function test_unrelatedHost_false() {
        verify(!Q.isAutheliaHost("https://example.com/", "auth.example.com"));
    }

    function test_partialSuffixWithoutDot_false() {
        // "myauth.example.com" must not match "auth.example.com" — the
        // endsWith check is anchored on the dot prefix.
        verify(!Q.isAutheliaHost("https://myauth.example.com/",
                                  "auth.example.com"));
    }

    function test_caseInsensitive() {
        // WHATWG URL.host returns lowercased hosts. sanitizeAutheliaHost
        // (ConfigAuth.qml) trims + strips control bytes but does NOT
        // lowercase, so isAutheliaHost lowercases the stored value here
        // too — otherwise an operator-typed "Auth.Example.COM" would
        // silently mismatch and the Authelia overlay would never engage
        // (credentials would land on the upstream login page).
        verify(Q.isAutheliaHost("https://AUTH.EXAMPLE.COM/", "auth.example.com"));
        verify(Q.isAutheliaHost("https://auth.example.com/", "AUTH.EXAMPLE.COM"));
        verify(Q.isAutheliaHost("https://app.AUTH.EXAMPLE.COM/", "auth.example.com"));
    }

    function test_explicitPortInUrl_isKept() {
        // Qt V4's URL parser does NOT strip default ports (unlike WHATWG),
        // so an explicit `:443` in the URL stays in URL.host. Configuring
        // a bare hostname will mismatch — operators have to use the same
        // form everywhere.
        verify(!Q.isAutheliaHost("https://auth.example.com:443/2fa",
                                  "auth.example.com"));
        // Configure with the port to make the comparison match.
        verify(Q.isAutheliaHost("https://auth.example.com:443/2fa",
                                 "auth.example.com:443"));
    }

    function test_nonDefaultPortInUrl_requiresMatchingConfig() {
        verify(!Q.isAutheliaHost("https://auth.example.com:9000/2fa",
                                  "auth.example.com"));
        verify(Q.isAutheliaHost("https://auth.example.com:9000/2fa",
                                 "auth.example.com:9000"));
    }

    function test_ipv6Literal_bracketsStripped() {
        // Qt V4's URL parser returns the IPv6 address WITHOUT brackets,
        // so the configured autheliaHost must match the bracket-less form.
        verify(Q.isAutheliaHost("https://[::1]/login", "::1"));
        verify(!Q.isAutheliaHost("https://[::1]/login", "[::1]"));
    }

    function test_malformedUrl_returnsFalse() {
        verify(!Q.isAutheliaHost("not a url", "auth.example.com"));
        verify(!Q.isAutheliaHost("https://", "auth.example.com"));
    }

    function test_fragmentAndPathIgnored() {
        verify(Q.isAutheliaHost(
            "https://auth.example.com/2fa?rd=https%3A%2F%2Foriginal#step1",
            "auth.example.com"));
    }

    function test_emptyCurrentUrl_returnsFalse() {
        verify(!Q.isAutheliaHost("", "auth.example.com"));
    }

    // Suffix-collision: this is the case where the configured value is
    // dangerously short (e.g. just "com"). The function does match any
    // *.com host then — but the responsibility for rejecting such input
    // belongs to the KCM, not this helper. Document the contract.
    function test_dangerouslyShortHost_matchesEverything() {
        verify(Q.isAutheliaHost("https://anything.com/", "com"));
    }

    // Defence-in-depth: ConfigAuth's load-time sanitize covers per-profile
    // autheliaHost, but a hand-edited or imported value could still feed
    // this comparison raw. Stripping control bytes at the comparison site
    // closes that leak centrally.
    function test_zeroWidthSpace_stillMatches() {
        // U+200B between the dots — a literal `===` would silently fail.
        verify(Q.isAutheliaHost("https://auth.example.com/",
                                 "auth.example​.com"));
    }
    function test_rightToLeftOverride_stillMatches() {
        // U+202E (RLO) leading byte (legacy unsanitised global).
        verify(Q.isAutheliaHost("https://auth.example.com/",
                                 "‮auth.example.com"));
    }
    function test_byteOrderMark_stillMatches() {
        verify(Q.isAutheliaHost("https://auth.example.com/",
                                 "auth.example.com﻿"));
    }
    function test_onlyControlBytes_returnsFalse() {
        // Strip-to-empty must not match every host.
        verify(!Q.isAutheliaHost("https://auth.example.com/", "​‮"));
    }
}
