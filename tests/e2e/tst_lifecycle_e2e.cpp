/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * End-to-end: load /beat-page (setInterval JS that pings /_beat every
 * 100 ms), then drive QWebEnginePage::setLifecycleState() through the
 * Active → Frozen → Active → Discarded → Active sequence and verify
 * the heartbeat counter on the fixture matches the documented Chromium
 * contract (Frozen pauses timers; Discarded kills the renderer + reload
 * on return; Active resumes/restarts).
 *
 * The LifecyclePolicy state machine (decideOnChange / decideOnTimer)
 * is unit-tested by tst_lifecycle.qml. This binary verifies
 * that Qt's underlying lifecycle API does what the policy assumes.
 */
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

int heartbeats(int port)
{
    return fetchReport(port).value(u"heartbeats"_s).toInt();
}

void resetCounters(int port)
{
    rawGet(port, "/_reset");
}

} // namespace

class TestLifecycleE2E : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QtWebEngineQuick::initialize();
    }

    // Notes on timing:
    //   The headless software-rendering backend without a backing
    //   QWindow gives setInterval timers a noticeably degraded firing
    //   rate (often only a handful of hits per second versus the
    //   nominal 10/s the page requests). The assertions below use
    //   liberal thresholds + ratios rather than tight counts so the
    //   suite stays green across runners; the *direction* of change
    //   (Active accumulates → Frozen stalls → Active resumes) is
    //   what the test proves.

    void activeView_continuesBeating()
    {
        FixtureServer fixture;
        if (qEnvironmentVariableIsEmpty("IFRAME_FIXTURE_HTTPD")) {
            QSKIP("IFRAME_FIXTURE_HTTPD is not set");
        }
        QVERIFY2(fixture.start(), qPrintable(fixture.error()));
        resetCounters(fixture.port());

        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/beat-page"_s));
        QVERIFY(loadSpy.wait(10000));

        // Give the page a generous window to fire its setInterval.
        QTest::qWait(2000);
        const int active = heartbeats(fixture.port());
        QVERIFY2(active >= 1,
                 qPrintable(QStringLiteral("expected ≥1 beat while Active, got %1").arg(active)));

        fixture.stop();
    }

    void frozenView_significantlyReducesBeating()
    {
        FixtureServer fixture;
        if (qEnvironmentVariableIsEmpty("IFRAME_FIXTURE_HTTPD")) {
            QSKIP("IFRAME_FIXTURE_HTTPD is not set");
        }
        QVERIFY2(fixture.start(), qPrintable(fixture.error()));
        resetCounters(fixture.port());

        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/beat-page"_s));
        QVERIFY(loadSpy.wait(10000));

        // Accumulate baseline beats while Active. Long window so even
        // the slow software backend gets at least a couple in.
        QTest::qWait(2000);
        const int baseline = heartbeats(fixture.port());
        if (baseline < 1) {
            QSKIP("software backend did not fire any beats within 2 s; "
                  "frozen-vs-active comparison would be meaningless");
        }

        // Lifecycle requires the view to be hidden; Chromium pins a
        // visible page to Active via recommendedState.
        page.setVisible(false);
        page.setLifecycleState(QWebEnginePage::LifecycleState::Frozen);

        // Same-length window again, this time frozen. Allow a small
        // grace for an already-in-flight fetch landing after the
        // state change committed.
        QTest::qWait(2000);
        const int afterFreeze = heartbeats(fixture.port());
        const int frozenDelta = afterFreeze - baseline;
        QVERIFY2(frozenDelta <= 1,
                 qPrintable(QStringLiteral("expected freeze to stall beats; "
                            "baseline=%1 after=%2 delta=%3").arg(baseline).arg(afterFreeze).arg(frozenDelta)));

        fixture.stop();
    }

    void resumeFromFrozen_restartsBeating()
    {
        FixtureServer fixture;
        if (qEnvironmentVariableIsEmpty("IFRAME_FIXTURE_HTTPD")) {
            QSKIP("IFRAME_FIXTURE_HTTPD is not set");
        }
        QVERIFY2(fixture.start(), qPrintable(fixture.error()));
        resetCounters(fixture.port());

        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/beat-page"_s));
        QVERIFY(loadSpy.wait(10000));

        QTest::qWait(1000);
        page.setVisible(false);
        page.setLifecycleState(QWebEnginePage::LifecycleState::Frozen);
        QTest::qWait(800);
        const int beforeResume = heartbeats(fixture.port());

        page.setVisible(true);
        page.setLifecycleState(QWebEnginePage::LifecycleState::Active);
        QTest::qWait(2000);
        const int afterResume = heartbeats(fixture.port());
        const int resumeDelta = afterResume - beforeResume;
        QVERIFY2(resumeDelta >= 1,
                 qPrintable(QStringLiteral("expected resume to restart beats; "
                            "before=%1 after=%2 delta=%3").arg(beforeResume).arg(afterResume).arg(resumeDelta)));

        fixture.stop();
    }

    // Renderer recycling (WebViewLifecycle.recycleAfterSec) dates each
    // renderer by sampling renderProcessPid and relies on Discarded
    // killing it: the pid drops to 0, and after Discarded -> Active the
    // page runs in a new process with a different pid.
    // (renderProcessPidChanged was NOT observed to fire here on Qt 6.10,
    // which is why the controller samples the pid instead.)
    void discard_replacesRenderProcess()
    {
        FixtureServer fixture;
        if (qEnvironmentVariableIsEmpty("IFRAME_FIXTURE_HTTPD")) {
            QSKIP("IFRAME_FIXTURE_HTTPD is not set");
        }
        QVERIFY2(fixture.start(), qPrintable(fixture.error()));

        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/beat-page"_s));
        QVERIFY(loadSpy.wait(10000));
        const qint64 firstPid = page.renderProcessPid();
        QVERIFY2(firstPid > 0, "no renderer after load");

        page.setVisible(false);
        page.setLifecycleState(QWebEnginePage::LifecycleState::Frozen);
        page.setLifecycleState(QWebEnginePage::LifecycleState::Discarded);
        QTRY_COMPARE_WITH_TIMEOUT(page.renderProcessPid(), qint64(0), 5000);

        loadSpy.clear();
        page.setVisible(true);
        page.setLifecycleState(QWebEnginePage::LifecycleState::Active);
        QVERIFY(loadSpy.wait(10000));
        QTRY_VERIFY_WITH_TIMEOUT(page.renderProcessPid() > 0, 5000);
        QVERIFY(page.renderProcessPid() != firstPid);

        fixture.stop();
    }
};

QTEST_MAIN(TestLifecycleE2E)
#include "tst_lifecycle_e2e.moc"
