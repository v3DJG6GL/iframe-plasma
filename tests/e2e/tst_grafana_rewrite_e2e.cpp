/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * End-to-end: load /goto/abc, watch WebEngine follow the 302 chain to
 * /d/abc/slug?viewPanel=panel-7, and assert the fixture's /_record
 * endpoint saw the right final URL.
 *
 * GrafanaUrl.transform's pure pipeline is covered by
 * tst_grafana_url_rewrite.qml (65 cases). This binary verifies the
 * server-side counterpart of the helper's documented limitation:
 * /goto/<id> short links can't be d-solo-rewritten client-side because
 * Grafana resolves them via a 302, so the helper preserves them and
 * the navigation handles the resolution.
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

QJsonObject fetchReport(int port)
{
    QTcpSocket sock;
    sock.connectToHost(QHostAddress::LocalHost, port);
    if (!sock.waitForConnected(2000)) return {};
    sock.write("GET /_report HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n");
    if (!sock.waitForBytesWritten(2000)) return {};
    QByteArray buf;
    while (sock.waitForReadyRead(2000)) buf.append(sock.readAll());
    const int blank = buf.indexOf("\r\n\r\n");
    if (blank < 0) return {};
    return QJsonDocument::fromJson(buf.mid(blank + 4)).object();
}

// Wait for the inline /d/ page's `fetch('/_record?u=…')` to actually
// hit the server. WebEngine's loadFinished signal fires when the page
// itself loads; the in-page fetch is async and may arrive a moment
// later. Poll /_report until lastUrl looks like the recorded one.
bool waitForRecord(int port, const QString &substring, int maxMs = 5000)
{
    const auto start = QDateTime::currentMSecsSinceEpoch();
    while (QDateTime::currentMSecsSinceEpoch() - start < maxMs) {
        const QJsonObject rep = fetchReport(port);
        const QString last = rep.value(u"lastUrl"_s).toString();
        if (last.contains(substring)) return true;
        QTest::qWait(100);
    }
    return false;
}

} // namespace

class TestGrafanaRewriteE2E : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QtWebEngineQuick::initialize();
    }

    void gotoLink_resolvesToDashboardWithViewPanel()
    {
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }

        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/goto/abc"_s));
        QVERIFY(loadSpy.wait(10000));

        // After 302-following, the page sits on /d/abc/slug?viewPanel=panel-7.
        const QString finalUrl = page.url().toString();
        QVERIFY2(finalUrl.contains(u"/d/abc/slug"_s),
                 qPrintable(u"expected /d/abc/slug, got: "_s + finalUrl));
        QVERIFY2(finalUrl.contains(u"viewPanel=panel-7"_s),
                 qPrintable(u"expected viewPanel=panel-7 query, got: "_s + finalUrl));

        // The inline JS posts its own location.href to /_record.
        QVERIFY2(waitForRecord(fixture.port(), u"/d/abc/slug"_s),
                 "fixture did not record the resolved URL");

        fixture.stop();
    }

    void dSoloDirect_renderedAndRecorded()
    {
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/d-solo/uid42/dash?panelId=5"_s));
        QVERIFY(loadSpy.wait(10000));

        QVERIFY(page.url().toString().contains(u"/d-solo/uid42/dash"_s));
        QVERIFY2(waitForRecord(fixture.port(), u"/d-solo/uid42/dash"_s),
                 "fixture did not record direct d-solo URL");

        fixture.stop();
    }

    void themePage_reflectsQueryParam()
    {
        // Sanity for the WebTab ${theme} substitution path: a URL with
        // ?theme=dark renders a body with the literal marker, so a
        // production widget passing theme=dark into a Grafana embed
        // can be trusted to actually serve theme=dark on the wire.
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/theme.html?theme=dark"_s));
        QVERIFY(loadSpy.wait(10000));

        QString body;
        QEventLoop loop;
        page.toPlainText([&body, &loop](const QString &s) {
            body = s; loop.quit();
        });
        QTimer::singleShot(5000, &loop, &QEventLoop::quit);
        loop.exec();

        QVERIFY2(body.contains(u"theme=dark"_s),
                 qPrintable(u"expected theme=dark marker, got: "_s + body));

        fixture.stop();
    }
};

QTEST_MAIN(TestGrafanaRewriteE2E)
#include "tst_grafana_rewrite_e2e.moc"
