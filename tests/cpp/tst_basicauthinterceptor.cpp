/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#include "basicauthinterceptor.h"

#include <QObject>
#include <QStringList>
#include <QTest>
#include <QtConcurrent>

using namespace Qt::Literals::StringLiterals;

class TestBasicAuthInterceptor : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    // ---------------------------------------------------------------
    // Initial state + clearAll
    // ---------------------------------------------------------------
    void freshInterceptorIsEmpty()
    {
        BasicAuthInterceptor i;
        QCOMPARE(i.headersSnapshot().size(), 0);
    }

    void clearAll_onEmpty_isNoOp()
    {
        BasicAuthInterceptor i;
        i.clearAll();
        QCOMPARE(i.headersSnapshot().size(), 0);
    }

    void clearAll_emptiesAfterApply()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"u"_s, u"p"_s, {u"a.example.com"_s, u"b.example.com"_s});
        QCOMPARE(i.headersSnapshot().size(), 2);
        i.clearAll();
        QCOMPARE(i.headersSnapshot().size(), 0);
    }

    // ---------------------------------------------------------------
    // applyProfile: input gates
    // ---------------------------------------------------------------
    void applyProfile_nonePassthrough_doesNotRegister()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"none"_s, u""_s, u"ignored"_s, {u"a.com"_s});
        QCOMPARE(i.headersSnapshot().size(), 0);
    }

    void applyProfile_emptyProfileId_doesNotRegister()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u""_s, u"basic"_s, u"u"_s, u"p"_s, {u"a.com"_s});
        QCOMPARE(i.headersSnapshot().size(), 0);
    }

    void applyProfile_emptyHostList_doesNotRegister()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"u"_s, u"p"_s, {});
        QCOMPARE(i.headersSnapshot().size(), 0);
    }

    void applyProfile_emptySecret_doesNotRegister()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"u"_s, u""_s, {u"a.com"_s});
        QCOMPARE(i.headersSnapshot().size(), 0);
    }

    void applyProfile_unknownAuthType_doesNotRegister()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"oauth"_s, u"u"_s, u"p"_s, {u"a.com"_s});
        QCOMPARE(i.headersSnapshot().size(), 0);
    }

    void applyProfile_colonInBasicUser_doesNotRegister()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"a:b"_s, u"p"_s, {u"a.com"_s});
        QCOMPARE(i.headersSnapshot().size(), 0);
    }

    void applyProfile_controlInHeader_doesNotRegister()
    {
        BasicAuthInterceptor i;
        const QString s = u"tok"_s + QChar(0x0B) + u"data"_s;
        i.applyProfile(u"P"_s, u"raw"_s, u""_s, s, {u"a.com"_s});
        QCOMPARE(i.headersSnapshot().size(), 0);
    }

    // ---------------------------------------------------------------
    // Host normalisation: lower-case + trim + skip-empty
    // ---------------------------------------------------------------
    void applyProfile_lowercasesHostKeys()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"u"_s, u"p"_s,
                       {u"EXAMPLE.com"_s, u"Foo.Bar"_s});
        const auto h = i.headersSnapshot();
        QVERIFY(h.contains(u"example.com"_s));
        QVERIFY(h.contains(u"foo.bar"_s));
        QVERIFY(!h.contains(u"EXAMPLE.com"_s));
    }

    void applyProfile_trimsWhitespaceFromHosts()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"u"_s, u"p"_s, {u"  a.com  "_s});
        const auto h = i.headersSnapshot();
        QVERIFY(h.contains(u"a.com"_s));
        QCOMPARE(h.size(), 1);
    }

    void applyProfile_skipsEmptyAndWhitespaceHosts()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"u"_s, u"p"_s,
                       {u""_s, u"   "_s, u"good.com"_s});
        const auto h = i.headersSnapshot();
        QCOMPARE(h.size(), 1);
        QVERIFY(h.contains(u"good.com"_s));
    }

    void applyProfile_duplicateHosts_collapseToOne()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"u"_s, u"p"_s,
                       {u"x.com"_s, u"X.COM"_s, u"x.com"_s});
        QCOMPARE(i.headersSnapshot().size(), 1);
    }

    void applyProfile_portPreserved()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"u"_s, u"p"_s, {u"x.com:9100"_s});
        QVERIFY(i.headersSnapshot().contains(u"x.com:9100"_s));
    }

    void applyProfile_ipv6Bracketed()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"u"_s, u"p"_s, {u"[::1]:9100"_s});
        QVERIFY(i.headersSnapshot().contains(u"[::1]:9100"_s));
    }

    // ---------------------------------------------------------------
    // Header value content
    // ---------------------------------------------------------------
    void applyProfile_basicHeaderValue()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"alice"_s, u"secret"_s, {u"x.com"_s});
        QCOMPARE(i.headersSnapshot().value(u"x.com"_s),
                 QByteArray("Basic YWxpY2U6c2VjcmV0"));
    }

    void applyProfile_bearerHeaderValue()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"bearer"_s, u""_s, u"eyJ0"_s, {u"x.com"_s});
        QCOMPARE(i.headersSnapshot().value(u"x.com"_s),
                 QByteArray("Bearer eyJ0"));
    }

    void applyProfile_rawHeaderValue()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"raw"_s, u""_s, u"X-Foo: bar"_s, {u"x.com"_s});
        QCOMPARE(i.headersSnapshot().value(u"x.com"_s),
                 QByteArray("X-Foo: bar"));
    }

    // ---------------------------------------------------------------
    // Multiple profiles + replacement semantics
    // ---------------------------------------------------------------
    void applyProfile_secondProfileOverwritesSameHost()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"A"_s, u"basic"_s, u"u1"_s, u"p1"_s, {u"shared.com"_s});
        const QByteArray first = i.headersSnapshot().value(u"shared.com"_s);
        i.applyProfile(u"B"_s, u"basic"_s, u"u2"_s, u"p2"_s, {u"shared.com"_s});
        const QByteArray second = i.headersSnapshot().value(u"shared.com"_s);
        QVERIFY(first != second);
    }

    void applyProfile_independentHosts_coexist()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"A"_s, u"basic"_s, u"u1"_s, u"p1"_s, {u"a.com"_s});
        i.applyProfile(u"B"_s, u"bearer"_s, u""_s, u"tok"_s, {u"b.com"_s});
        const auto h = i.headersSnapshot();
        QCOMPARE(h.size(), 2);
        QVERIFY(h.value(u"a.com"_s).startsWith("Basic "));
        QCOMPARE(h.value(u"b.com"_s), QByteArray("Bearer tok"));
    }

    // ---------------------------------------------------------------
    // attachTo / detachFrom
    // ---------------------------------------------------------------
    void attachTo_nullProfile_returnsFalse()
    {
        BasicAuthInterceptor i;
        QVERIFY(!i.attachTo(nullptr));
    }

    void attachTo_wrongType_returnsFalse()
    {
        BasicAuthInterceptor i;
        QObject foreign;
        QVERIFY(!i.attachTo(&foreign));
    }

    void detachFrom_nullProfile_returnsFalse()
    {
        BasicAuthInterceptor i;
        QVERIFY(!i.detachFrom(nullptr));
    }

    void detachFrom_wrongType_returnsFalse()
    {
        BasicAuthInterceptor i;
        QObject foreign;
        QVERIFY(!i.detachFrom(&foreign));
    }

    // ---------------------------------------------------------------
    // Thread safety: UI-thread write + IO-thread read (via headersSnapshot)
    // run concurrently without deadlocking or corrupting the hash.
    // ---------------------------------------------------------------
    void concurrentReadAndApply_noDeadlock()
    {
        BasicAuthInterceptor i;
        i.applyProfile(u"P"_s, u"basic"_s, u"u"_s, u"p"_s, {u"seed.com"_s});

        constexpr int N = 200;
        // Writer churn on UI-thread equivalent.
        auto writer = QtConcurrent::run([&]() {
            for (int k = 0; k < N; ++k) {
                const QString host = u"host"_s + QString::number(k) + u".com"_s;
                i.applyProfile(u"P"_s, u"basic"_s, u"u"_s, u"p"_s, {host});
            }
        });
        // Reader churn on IO-thread equivalent.
        auto reader = QtConcurrent::run([&]() {
            for (int k = 0; k < N; ++k) {
                const auto snap = i.headersSnapshot();
                Q_UNUSED(snap);
            }
        });
        writer.waitForFinished();
        reader.waitForFinished();
        // After both finish, seed entry must still be present + at least one
        // writer entry must exist.
        const auto h = i.headersSnapshot();
        QVERIFY(h.contains(u"seed.com"_s));
        QVERIFY(h.size() >= 2);
    }
};

QTEST_GUILESS_MAIN(TestBasicAuthInterceptor)
#include "tst_basicauthinterceptor.moc"
