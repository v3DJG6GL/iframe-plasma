/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * End-to-end: the Qt WebEngine 6.10 GC workaround (PageScripts.js
 * gcWorkaroundSource, QTBUG-141377). With --js-flags=--expose-gc in
 * QTWEBENGINE_CHROMIUM_FLAGS, `gc` must exist in the page's MainWorld at
 * DocumentCreation and the injected script must arm itself; the script is
 * built from the production PageScripts.js, not a copy.
 */
#include <QFile>
#include <QJSEngine>
#include <QProcess>
#include <QSignalSpy>
#include <QTest>
#include <QtWebEngineCore/QWebEnginePage>
#include <QtWebEngineCore/QWebEngineProfile>
#include <QtWebEngineCore/QWebEngineScript>
#include <QtWebEngineCore/QWebEngineScriptCollection>
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
        const QList<QByteArray> parts = m_proc.readLine().trimmed().split(' ');
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
    QString baseUrl() const { return QStringLiteral("http://127.0.0.1:%1").arg(m_port); }

private:
    QProcess m_proc;
    int m_port = 0;
};

// Evaluate PageScripts.js (minus Qt's `.pragma library`) and call
// gcWorkaroundSource(intervalSec).
QString gcScriptSource(int intervalSec)
{
    QFile f(QStringLiteral(IFRAME_SOURCE_DIR "/package/contents/ui/PageScripts.js"));
    if (!f.open(QIODevice::ReadOnly)) return {};
    QString src = QString::fromUtf8(f.readAll());
    src.replace(u".pragma library"_s, QString());
    QJSEngine engine;
    engine.evaluate(src);
    const QJSValue fn = engine.globalObject().property(u"gcWorkaroundSource"_s);
    return fn.call({intervalSec}).toString();
}

// Run `js` in the page's MainWorld and wait for the result; an invalid
// QVariant means it timed out.
QVariant runMainWorld(QWebEnginePage &page, const QString &js)
{
    QVariant out;
    bool done = false;
    page.runJavaScript(js, QWebEngineScript::MainWorld, [&](const QVariant &v) {
        out = v;
        done = true;
    });
    (void)QTest::qWaitFor([&] { return done; }, 5000);
    return out;
}

} // namespace

class TestGcE2E : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        // Chromium reads its flags when the first profile is created, so
        // appending here (before any page) is early enough.
        const QByteArray flags =
            qgetenv("QTWEBENGINE_CHROMIUM_FLAGS") + QByteArray(" --js-flags=--expose-gc");
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", flags);
        QtWebEngineQuick::initialize();
    }

    void scriptSource_isBuiltFromProductionLibrary()
    {
        const QString src = gcScriptSource(20);
        QVERIFY(src.contains(u"__ifpGcArmed"_s));
        QVERIFY(src.contains(u"var ms = 20000;"_s));
        QCOMPARE(gcScriptSource(0), QString());
    }

    void exposeGc_scriptArmsInMainWorld()
    {
        FixtureServer fixture;
        if (!fixture.start()) {
            QSKIP("fixture server failed to start");
        }

        QWebEngineProfile profile;
        QWebEnginePage page(&profile);
        page.settings()->setAttribute(QWebEngineSettings::ErrorPageEnabled, false);

        QWebEngineScript s;
        s.setName(u"iframe-plasma-gc"_s);
        s.setInjectionPoint(QWebEngineScript::DocumentCreation);
        s.setWorldId(QWebEngineScript::MainWorld);
        s.setRunsOnSubFrames(false);
        s.setSourceCode(gcScriptSource(1));
        page.scripts().insert(s);

        QSignalSpy loadSpy(&page, &QWebEnginePage::loadFinished);
        page.load(QUrl(fixture.baseUrl() + u"/beat-page"_s));
        QVERIFY(loadSpy.wait(10000));

        QCOMPARE(runMainWorld(page, u"typeof gc"_s).toString(), u"function"_s);
        QCOMPARE(runMainWorld(page, u"window.__ifpGcArmed === true"_s).toBool(), true);
        // A forced collection runs without throwing.
        QCOMPARE(runMainWorld(page, u"(function(){ gc(); return 'ok'; })()"_s).toString(),
                 u"ok"_s);

        fixture.stop();
    }
};

QTEST_MAIN(TestGcE2E)
#include "tst_gc_e2e.moc"
