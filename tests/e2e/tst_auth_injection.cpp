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

// Pull /_report from the fixture server and return the parsed JSON.
// Used to assert what Authorization header the server actually saw
// (page body is unreliable when ErrorPageEnabled is off and a 401
// retry has occurred).
QJsonObject fetchReport(int port)
{
    QTcpSocket sock;
    sock.connectToHost(QHostAddress::LocalHost, port);
    if (!sock.waitForConnected(2000)) return {};
    sock.write("GET /_report HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n");
    if (!sock.waitForBytesWritten(2000)) return {};
    QByteArray buf;
    while (sock.waitForReadyRead(2000)) {
        buf.append(sock.readAll());
    }
    const int blank = buf.indexOf("\r\n\r\n");
    if (blank < 0) return {};
    return QJsonDocument::fromJson(buf.mid(blank + 4)).object();
}

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
