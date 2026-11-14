/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * End-to-end: load /cookie-set (server returns Set-Cookie), then load
 * /cookie-check (server returns 200 iff the cookie comes back) and
 * verify cookies survive lifecycle Frozen → Active and Discarded →
 * Active transitions on the same QWebEngineProfile.
 *
 * This is the contract iframe-plasma's per-auth-profile WebEngineProfile
 * relies on: Authelia/Grafana session cookies must outlast the lifecycle
 * downgrade so a thumbnail rotating through tabs doesn't keep
 * re-authenticating.
 */
#include "fixtureserver.h"

#include <QCoreApplication>
#include <QSignalSpy>
#include <QTcpSocket>
#include <QTest>
#include <QtWebEngineCore/QWebEnginePage>
#include <QtWebEngineCore/QWebEngineProfile>
#include <QtWebEngineCore/QWebEngineSettings>
#include <QtWebEngineQuick>

using namespace Qt::Literals::StringLiterals;

namespace {

bool loadAndWait(QWebEnginePage &page, const QUrl &url)
{
    QSignalSpy spy(&page, &QWebEnginePage::loadFinished);
    page.load(url);
    if (!spy.wait(10000)) return false;
    return true;
}

} // namespace

class TestCookiesPersist : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QtWebEngineQuick::initialize();
    }

    void cookieSet_thenCheck_returns200OnSameProfile()
    {
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QVERIFY(loadAndWait(page, QUrl(fixture.baseUrl() + u"/cookie-set"_s)));
        QVERIFY(loadAndWait(page, QUrl(fixture.baseUrl() + u"/cookie-check"_s)));
        QVERIFY2(pageBody(page).contains(u"cookie-present"_s),
                 "/cookie-check did not see the cookie on the same profile");
        fixture.stop();
    }

    void freshProfile_doesNotCarryCookie()
    {
        // Sanity: confirm cookies are scoped per-profile. A fresh
        // off-the-record profile starts with no cookies, so /cookie-check
        // should return cookie-missing (401 body).
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
        QWebEngineProfile profile1;
        QWebEnginePage page1(&profile1);
        page1.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);
        QVERIFY(loadAndWait(page1, QUrl(fixture.baseUrl() + u"/cookie-set"_s)));

        QWebEngineProfile profile2;
        QWebEnginePage page2(&profile2);
        page2.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);
        QVERIFY(loadAndWait(page2, QUrl(fixture.baseUrl() + u"/cookie-check"_s)));
        QVERIFY2(pageBody(page2).contains(u"cookie-missing"_s),
                 "fresh profile saw cookie from a different profile");
        fixture.stop();
    }

    void cookieSurvivesFrozenAndResume()
    {
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QVERIFY(loadAndWait(page, QUrl(fixture.baseUrl() + u"/cookie-set"_s)));

        // Force Frozen, wait, resume to Active, then re-check.
        page.setVisible(false);
        page.setLifecycleState(QWebEnginePage::LifecycleState::Frozen);
        QTest::qWait(500);
        page.setVisible(true);
        page.setLifecycleState(QWebEnginePage::LifecycleState::Active);

        QVERIFY(loadAndWait(page, QUrl(fixture.baseUrl() + u"/cookie-check"_s)));
        QVERIFY2(pageBody(page).contains(u"cookie-present"_s),
                 "cookie did not survive Frozen → Active");
        fixture.stop();
    }

    void cookieSurvivesDiscardedAndReload()
    {
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QVERIFY(loadAndWait(page, QUrl(fixture.baseUrl() + u"/cookie-set"_s)));

        // Force Discarded (renderer killed). Discarded → Active auto-
        // reloads the page in QtWebEngine — explicit reload is a no-op
        // here, but be defensive and load the check URL fresh.
        page.setVisible(false);
        page.setLifecycleState(QWebEnginePage::LifecycleState::Discarded);
        QTest::qWait(500);
        page.setVisible(true);
        page.setLifecycleState(QWebEnginePage::LifecycleState::Active);

        QVERIFY(loadAndWait(page, QUrl(fixture.baseUrl() + u"/cookie-check"_s)));
        QVERIFY2(pageBody(page).contains(u"cookie-present"_s),
                 "cookie did not survive Discarded → Active");
        fixture.stop();
    }
};

QTEST_MAIN(TestCookiesPersist)
#include "tst_cookies_persist.moc"
