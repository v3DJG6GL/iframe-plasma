/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#include "basicauthinterceptor.h"

#include <QTest>

class TestCanonicalizeHost : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void canonical_data()
    {
        QTest::addColumn<QString>("rawHost");
        QTest::addColumn<QString>("scheme");
        QTest::addColumn<int>("port");
        QTest::addColumn<QString>("expected");

        // --- IPv4 / DNS host ---------------------------------------------
        QTest::newRow("default-https port")       << "example.com" << "https" << -1 << "example.com";
        QTest::newRow("default-http port")        << "example.com" << "http"  << -1 << "example.com";
        QTest::newRow("explicit-default-https")   << "example.com" << "https" << 443 << "example.com";
        QTest::newRow("explicit-default-http")    << "example.com" << "http"  << 80  << "example.com";
        QTest::newRow("non-default-https 9100")   << "example.com" << "https" << 9100 << "example.com:9100";
        QTest::newRow("non-default-http 8080")    << "example.com" << "http"  << 8080 << "example.com:8080";
        QTest::newRow("non-default-https 80")     << "example.com" << "https" << 80   << "example.com:80";
        QTest::newRow("non-default-http 443")     << "example.com" << "http"  << 443  << "example.com:443";

        // --- Case folding ------------------------------------------------
        QTest::newRow("uppercase-host")           << "EXAMPLE.COM" << "https" << -1   << "example.com";
        QTest::newRow("mixed-case-host")          << "Example.CoM" << "https" << 9100 << "example.com:9100";

        // --- IPv6 literal: brackets re-added; port suffix as separate ----
        QTest::newRow("ipv6-localhost default")   << "::1"         << "https" << -1   << "[::1]";
        QTest::newRow("ipv6-localhost http-def")  << "::1"         << "http"  << 80   << "[::1]";
        QTest::newRow("ipv6-localhost non-def")   << "::1"         << "https" << 9100 << "[::1]:9100";
        QTest::newRow("ipv6-full default")        << "2001:db8::1" << "https" << -1   << "[2001:db8::1]";
        QTest::newRow("ipv6-full non-default")    << "2001:db8::1" << "http"  << 8080 << "[2001:db8::1]:8080";
        QTest::newRow("ipv6-uppercase folded")    << "2001:DB8::1" << "https" << -1   << "[2001:db8::1]";

        // --- IDN punycode pass-through (QUrl gives us punycode) ----------
        QTest::newRow("idn-punycode")             << "xn--mnchen-3ya.de" << "https" << -1 << "xn--mnchen-3ya.de";

        // --- Empty / malformed host -------------------------------------
        // QUrl::host() returns empty for "http:///path"-shaped URLs.
        QTest::newRow("empty-host default")       << ""            << "https" << -1 << "";
        QTest::newRow("empty-host non-default")   << ""            << "https" << 9100 << ":9100";

        // --- Single-label hosts -----------------------------------------
        QTest::newRow("single-label")             << "localhost"   << "http"  << -1 << "localhost";

        // --- Boundary numeric ports -------------------------------------
        QTest::newRow("port-1")                   << "host"        << "http"  << 1   << "host:1";
        QTest::newRow("port-65535")               << "host"        << "https" << 65535 << "host:65535";

        // --- Hyphen / underscore in host --------------------------------
        QTest::newRow("hyphenated")               << "auth-1.example.com" << "https" << -1 << "auth-1.example.com";
        QTest::newRow("subdomain depth 3")        << "a.b.c.example.com"  << "https" << -1 << "a.b.c.example.com";
    }

    void canonical()
    {
        QFETCH(QString, rawHost);
        QFETCH(QString, scheme);
        QFETCH(int, port);
        QFETCH(QString, expected);
        QCOMPARE(iframeplasma::auth::canonicalizeHost(rawHost, scheme, port), expected);
    }
};

QTEST_GUILESS_MAIN(TestCanonicalizeHost)
#include "tst_canonicalizehost.moc"
