/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * End-to-end: spin up the fixture HTTP server, attach BasicAuthInterceptor
 * to a real QWebEngineProfile, load /basic, and assert the request
 * carried the Authorization header (via the server's /_report endpoint
 * and the rendered page body).
 *
 * Notes for the second/third tests: when there is no interceptor (or the
 * registered host doesn't match), Chromium's network stack auto-retries
 * the 401 with empty credentials ("Basic Og==", i.e. ":"). So we assert
 * on what the SERVER ultimately replied with — basic-ok (200) when the
 * interceptor injected our real "user:secret", auth-required (401) when
 * it didn't — rather than the verbatim Authorization header.
 */
#include "basicauthinterceptor.h"
#include "fixtureserver.h"

#include <QCoreApplication>
#include <QEventLoop>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTest>
#include <QtWebEngineCore/QWebEnginePage>
#include <QtWebEngineCore/QWebEngineProfile>
#include <QtWebEngineCore/QWebEngineSettings>
#include <QtWebEngineQuick>

using namespace Qt::Literals::StringLiterals;

namespace {

static constexpr QLatin1String EXPECTED_HEADER{"Basic dXNlcjpzZWNyZXQ="};

} // namespace

class TestAuthInjection : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QtWebEngineQuick::initialize();
    }

    void noInterceptor_serverReturns401()
    {
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start (IFRAME_FIXTURE_HTTPD unset?)");
        }

        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/basic"_s));
        QVERIFY(loadSpy.wait(10000));

        // Without an interceptor the server never sees the "user:secret"
        // header — only whatever Chromium's auto-retry happened to send
        // (empty creds at best).
        const QJsonObject rep = fetchReport(fixture.port());
        const QString auth = rep.value(u"lastAuthorization"_s).toString();
        QVERIFY2(auth != EXPECTED_HEADER,
                 qPrintable(u"unexpected interceptor-style header: "_s + auth));

        fixture.stop();
    }

    void interceptor_injectsAuthorizationOnRegisteredHost()
    {
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
        const QString hostKey = QStringLiteral("127.0.0.1:%1").arg(fixture.port());

        BasicAuthInterceptor interceptor;
        interceptor.applyProfile(
            u"test"_s, u"basic"_s, u"user"_s, u"secret"_s, {hostKey});

        QWebEngineProfile profile;
        profile.setUrlRequestInterceptor(&interceptor);
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/basic"_s));
        QVERIFY(loadSpy.wait(10000));

        // Interceptor injected our credentials before the request hit
        // the wire; the server saw the exact header bytes.
        const QJsonObject rep = fetchReport(fixture.port());
        QCOMPARE(rep.value(u"lastAuthorization"_s).toString(),
                 QString(EXPECTED_HEADER));

        fixture.stop();
    }

    void interceptor_doesNotLeakAuthToOtherHost()
    {
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
        // Register against a different host:port — the interceptor must
        // not inject when the request hits our fixture.
        BasicAuthInterceptor interceptor;
        interceptor.applyProfile(
            u"test"_s, u"basic"_s, u"user"_s, u"secret"_s,
            {u"unrelated.example:1234"_s});

        QWebEngineProfile profile;
        profile.setUrlRequestInterceptor(&interceptor);
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/basic"_s));
        QVERIFY(loadSpy.wait(10000));

        // Host-mismatch — the interceptor must not have injected our
        // real credentials onto this request.
        const QJsonObject rep = fetchReport(fixture.port());
        const QString auth = rep.value(u"lastAuthorization"_s).toString();
        QVERIFY2(auth != EXPECTED_HEADER,
                 qPrintable(u"interceptor leaked credentials to wrong host: "_s + auth));

        fixture.stop();
    }
};

QTEST_MAIN(TestAuthInjection)
#include "tst_auth_injection.moc"
