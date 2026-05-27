/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#include "basicauthinterceptor.h"

#include <QTest>

using namespace Qt::Literals::StringLiterals;
using iframeplasma::auth::buildAuthHeader;

class TestBuildAuthHeader : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    // ---------------------------------------------------------------
    // Successful constructions
    // ---------------------------------------------------------------
    void basic_simple()
    {
        QString reason;
        const auto h = buildAuthHeader(u"basic"_s, u"alice"_s, u"secret"_s, &reason);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray("Basic YWxpY2U6c2VjcmV0"));
        QVERIFY(reason.isEmpty());
    }

    void basic_empty_user()
    {
        const auto h = buildAuthHeader(u"basic"_s, u""_s, u"p"_s, nullptr);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray("Basic OnA="));
    }

    void basic_utf8_password()
    {
        const auto h = buildAuthHeader(u"basic"_s, u"u"_s,
            QString::fromUtf8("p\xc3\xa4ssw\xc3\xb6rd"), nullptr);
        QVERIFY(h.has_value());
        const QByteArray creds = QByteArray("u:p\xc3\xa4ssw\xc3\xb6rd");
        QCOMPARE(*h, QByteArray("Basic ") + creds.toBase64());
    }

    void basic_username_with_tab()
    {
        const auto h = buildAuthHeader(u"basic"_s, u"a\tb"_s, u"p"_s, nullptr);
        QVERIFY(h.has_value());
    }

    void bearer_simple()
    {
        const auto h = buildAuthHeader(u"bearer"_s, u""_s, u"eyJ0"_s, nullptr);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray("Bearer eyJ0"));
    }

    void bearer_trims_whitespace()
    {
        const auto h = buildAuthHeader(u"bearer"_s, u""_s, u"  tok  "_s, nullptr);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray("Bearer tok"));
    }

    void bearer_internal_tab_kept()
    {
        const auto h = buildAuthHeader(u"bearer"_s, u""_s, u"a\tb"_s, nullptr);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray("Bearer a\tb"));
    }

    void raw_simple()
    {
        const auto h = buildAuthHeader(u"raw"_s, u""_s, u"Custom xyz"_s, nullptr);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray("Custom xyz"));
    }

    void raw_double_quotes_stripped()
    {
        const auto h = buildAuthHeader(u"raw"_s, u""_s, u"\"Custom\""_s, nullptr);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray("Custom"));
    }

    void raw_single_quotes_stripped()
    {
        const auto h = buildAuthHeader(u"raw"_s, u""_s, u"'Custom'"_s, nullptr);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray("Custom"));
    }

    void raw_mismatched_quotes_kept()
    {
        const auto h = buildAuthHeader(u"raw"_s, u""_s, u"\"Custom"_s, nullptr);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray("\"Custom"));
    }

    void raw_trims_outer_whitespace()
    {
        const auto h = buildAuthHeader(u"raw"_s, u""_s, u"  value  "_s, nullptr);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray("value"));
    }

    // ---------------------------------------------------------------
    // Validation failures
    // ---------------------------------------------------------------
    void rejects_empty_secret()
    {
        QString reason;
        QVERIFY(!buildAuthHeader(u"basic"_s, u"u"_s, u""_s, &reason).has_value());
        QCOMPARE(reason, u"empty-secret"_s);
    }

    void rejects_empty_secret_bearer()
    {
        QString reason;
        QVERIFY(!buildAuthHeader(u"bearer"_s, u""_s, u""_s, &reason).has_value());
        QCOMPARE(reason, u"empty-secret"_s);
    }

    void rejects_empty_secret_raw()
    {
        QString reason;
        QVERIFY(!buildAuthHeader(u"raw"_s, u""_s, u""_s, &reason).has_value());
        QCOMPARE(reason, u"empty-secret"_s);
    }

    void rejects_colon_in_basic_username()
    {
        QString reason;
        QVERIFY(!buildAuthHeader(u"basic"_s, u"a:b"_s, u"p"_s, &reason).has_value());
        QCOMPARE(reason, u"colon-in-basic-username"_s);
    }

    void rejects_C0_control_in_username()
    {
        QString reason;
        const QString u = u"a"_s + QChar(0x01) + u"b"_s;
        QVERIFY(!buildAuthHeader(u"basic"_s, u, u"p"_s, &reason).has_value());
        QCOMPARE(reason, u"control-in-username"_s);
    }

    void rejects_DEL_in_username()
    {
        QString reason;
        const QString u = u"a"_s + QChar(0x7F) + u"b"_s;
        QVERIFY(!buildAuthHeader(u"basic"_s, u, u"p"_s, &reason).has_value());
        QCOMPARE(reason, u"control-in-username"_s);
    }

    void rejects_LF_in_username()
    {
        QString reason;
        QVERIFY(!buildAuthHeader(u"basic"_s, u"a\nb"_s, u"p"_s, &reason).has_value());
        QCOMPARE(reason, u"control-in-username"_s);
    }

    void rejects_CR_in_username()
    {
        QString reason;
        QVERIFY(!buildAuthHeader(u"basic"_s, u"a\rb"_s, u"p"_s, &reason).has_value());
        QCOMPARE(reason, u"control-in-username"_s);
    }

    void rejects_bearer_CRLF_in_secret()
    {
        QString reason;
        QVERIFY(!buildAuthHeader(u"bearer"_s, u""_s, u"tok\r\nX-Inject: x"_s, &reason).has_value());
        QCOMPARE(reason, u"control-in-header"_s);
    }

    void rejects_bearer_NUL_in_secret()
    {
        QString reason;
        const QString s = u"tok"_s + QChar(0x00) + u"data"_s;
        QVERIFY(!buildAuthHeader(u"bearer"_s, u""_s, s, &reason).has_value());
        QCOMPARE(reason, u"control-in-header"_s);
    }

    void rejects_raw_VT_in_secret()
    {
        QString reason;
        const QString s = u"a"_s + QChar(0x0B) + u"b"_s;
        QVERIFY(!buildAuthHeader(u"raw"_s, u""_s, s, &reason).has_value());
        QCOMPARE(reason, u"control-in-header"_s);
    }

    void rejects_raw_DEL_in_secret()
    {
        QString reason;
        const QString s = u"a"_s + QChar(0x7F) + u"b"_s;
        QVERIFY(!buildAuthHeader(u"raw"_s, u""_s, s, &reason).has_value());
        QCOMPARE(reason, u"control-in-header"_s);
    }

    void rejects_unknown_authtype()
    {
        QString reason;
        QVERIFY(!buildAuthHeader(u"oauth2"_s, u"u"_s, u"x"_s, &reason).has_value());
        QCOMPARE(reason, u"unknown-authtype"_s);
    }

    void rejects_empty_authtype()
    {
        QString reason;
        QVERIFY(!buildAuthHeader(u""_s, u"u"_s, u"x"_s, &reason).has_value());
        QCOMPARE(reason, u"unknown-authtype"_s);
    }

    void rejects_capitalised_authtype()
    {
        QString reason;
        QVERIFY(!buildAuthHeader(u"Basic"_s, u"u"_s, u"x"_s, &reason).has_value());
        QCOMPARE(reason, u"unknown-authtype"_s);
    }

    // ---------------------------------------------------------------
    // nullptr errorReason safety
    // ---------------------------------------------------------------
    void null_errorReason_safe()
    {
        QVERIFY(!buildAuthHeader(u"basic"_s, u"u"_s, u""_s, nullptr).has_value());
        QVERIFY(!buildAuthHeader(u"basic"_s, u"a:b"_s, u"p"_s, nullptr).has_value());
        QVERIFY(!buildAuthHeader(u"oauth"_s, u"u"_s, u"p"_s, nullptr).has_value());
    }

    void basic_decodes_to_user_colon_pass()
    {
        const auto h = buildAuthHeader(u"basic"_s, u"user"_s, u"pa$$word!"_s, nullptr);
        QVERIFY(h.has_value());
        const QByteArray prefix = QByteArrayLiteral("Basic ");
        QVERIFY(h->startsWith(prefix));
        const QByteArray decoded = QByteArray::fromBase64(h->mid(prefix.size()));
        QCOMPARE(decoded, QByteArray("user:pa$$word!"));
    }

    void basic_long_secret()
    {
        const QString longSecret = u"a"_s.repeated(4096);
        const auto h = buildAuthHeader(u"basic"_s, u"u"_s, longSecret, nullptr);
        QVERIFY(h.has_value());
        QVERIFY(h->size() > 4000);
        QVERIFY(h->startsWith("Basic "));
    }

    void bearer_only_whitespace_trims_then_passes_through()
    {
        const auto h = buildAuthHeader(u"bearer"_s, u""_s, u"  "_s, nullptr);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray("Bearer "));
    }

    void raw_empty_after_strip_still_passes_control_check()
    {
        const auto h = buildAuthHeader(u"raw"_s, u""_s, u"''"_s, nullptr);
        QVERIFY(h.has_value());
        QCOMPARE(*h, QByteArray(""));
    }
};

QTEST_GUILESS_MAIN(TestBuildAuthHeader)
#include "tst_buildauthheader.moc"
