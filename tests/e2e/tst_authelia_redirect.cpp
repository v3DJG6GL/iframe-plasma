/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * End-to-end: load /authelia-redir, follow the 302, and assert the
 * page lands on /authelia/2fa. Verifies that WebEngine's automatic
 * 302-following arrives at the URL WebTab.qml's onAutheliaHost would
 * then match against the configured autheliaHost.
 *
 * The QML-side host-match logic itself is covered by the
 * tst_authelia_detect.qml unit tests; this binary closes the loop by
 * proving the URL handed to that matcher post-redirect is the right
 * one.
 */
#include <QCoreApplication>
#include <QEventLoop>
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

QString pageBody(QWebEnginePage &page)
{
    QString out;
    QEventLoop loop;
    page.toPlainText([&out, &loop](const QString &s) {
        out = s; loop.quit();
    });
    QTimer::singleShot(5000, &loop, &QEventLoop::quit);
    loop.exec();
    return out;
}

} // namespace

class TestAutheliaRedirect : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QtWebEngineQuick::initialize();
    }

    void redirect_landsOnAutheliaPath()
    {
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }

        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/authelia-redir"_s));
        QVERIFY(loadSpy.wait(10000));

        // WebEngine follows 302 to /authelia/2fa.
        const QString finalUrl = page.url().toString();
        QVERIFY2(finalUrl.endsWith(u"/authelia/2fa"_s),
                 qPrintable(u"expected /authelia/2fa, got: "_s + finalUrl));

        // Body marker confirms the redirected page content rendered.
        const QString body = pageBody(page);
        QVERIFY2(body.contains(u"authelia-2fa-login"_s),
                 qPrintable(u"expected 2fa-login marker, got: "_s + body));

        fixture.stop();
    }

    void redirect_finalHostMatchesFixtureHost()
    {
        // WebTab.qml's onAutheliaHost would compare new URL(currentUrl).host
        // to the configured autheliaHost. This test confirms the host
        // component of the post-redirect URL is exactly 127.0.0.1:<port>
        // — i.e. an operator who put that string in autheliaHost would
        // get a match.
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/authelia-redir"_s));
        QVERIFY(loadSpy.wait(10000));

        const QString expectedHost = QStringLiteral("127.0.0.1:%1").arg(fixture.port());
        const QUrl url = page.url();
        // QUrl::host() strips the port; QUrl::authority() includes it.
        QCOMPARE(url.authority(), expectedHost);

        fixture.stop();
    }

    void directLoad_neverHitsAutheliaPath()
    {
        // Sanity: a direct load of /basic (no Authelia redirect) leaves
        // the URL on /basic, not /authelia/2fa. Confirms the assertion
        // above isn't trivially true.
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }
        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/basic"_s));
        QVERIFY(loadSpy.wait(10000));

        QVERIFY(!page.url().toString().contains(u"/authelia/"_s));

        fixture.stop();
    }
};

QTEST_MAIN(TestAutheliaRedirect)
#include "tst_authelia_redirect.moc"
