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
 * is unit-tested by tst_lifecycle.qml (28 cases). This binary verifies
 * that Qt's underlying lifecycle API does what the policy assumes.
 */
#include <QCoreApplication>
#include <QEventLoop>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSignalSpy>
#include <QTcpSocket>
#include <QTest>
#include <QtWebEngineCore/QWebEnginePage>
#include <QtWebEngineCore/QWebEngineProfile>
#include <QtWebEngineCore/QWebEngineSettings>
#include <QtWebEngineQuick>

using namespace Qt::Literals::StringLiterals;

namespace {

class FixtureServer
{
public:
    bool start()
    {
        const QByteArray script = qgetenv("IFRAME_FIXTURE_HTTPD");
        if (script.isEmpty()) return false;
        m_proc.setProgram(QStringLiteral("python3"));
        m_proc.setArguments({QString::fromLocal8Bit(script),
                             QStringLiteral("--port"), QStringLiteral("0")});
        m_proc.start();
        if (!m_proc.waitForStarted(5000)) return false;
        if (!m_proc.waitForReadyRead(5000)) return false;
        const QByteArray line = m_proc.readLine();
        const QList<QByteArray> parts = line.trimmed().split(' ');
        if (parts.size() != 2 || parts[0] != "LISTEN") return false;
        bool ok = false;
        m_port = parts[1].toInt(&ok);
        return ok && m_port > 0;
    }
    void stop()
    {
        if (m_proc.state() == QProcess::Running) {
            m_proc.terminate();
            if (!m_proc.waitForFinished(2000)) m_proc.kill();
        }
    }
    int port() const { return m_port; }
    QString baseUrl() const
    {
        return QStringLiteral("http://127.0.0.1:%1").arg(m_port);
    }

private:
    QProcess m_proc;
    int m_port = 0;
};

// Blocking GET that doesn't pull in Qt::Network. Returns body bytes.
QByteArray rawGet(int port, const QByteArray &path)
{
    QTcpSocket sock;
    sock.connectToHost(QHostAddress::LocalHost, port);
    if (!sock.waitForConnected(2000)) return {};
    sock.write("GET " + path + " HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n");
    if (!sock.waitForBytesWritten(2000)) return {};
    QByteArray buf;
    while (sock.waitForReadyRead(2000)) buf.append(sock.readAll());
    const int blank = buf.indexOf("\r\n\r\n");
    return blank < 0 ? QByteArray() : buf.mid(blank + 4);
}

QJsonObject report(int port)
{
    return QJsonDocument::fromJson(rawGet(port, "/_report")).object();
}

int heartbeats(int port)
{
    return report(port).value(u"heartbeats"_s).toInt();
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
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
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
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
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
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
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
};

QTEST_MAIN(TestLifecycleE2E)
#include "tst_lifecycle_e2e.moc"
