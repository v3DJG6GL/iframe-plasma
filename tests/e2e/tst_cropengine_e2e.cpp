/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * End-to-end: CropEngine.js in a real Chromium page shown by a QML
 * WebEngineView (the widget's own setup), for behaviour jsdom can't model:
 * animation frames on a hidden page, and the fit-mode observer loop.
 * The injected source is built from the production CropEngine.js.
 */
#include <QFile>
#include <QJSEngine>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>
#include <QtWebEngineQuick>

using namespace Qt::Literals::StringLiterals;

namespace {

// Evaluate CropEngine.js (minus `.pragma library`) and return
// buildApplyJs(selector, <optsJson parsed>).
QString buildApplyJs(const QString &selector, const QString &optsJson)
{
    QFile f(QStringLiteral(IFRAME_SOURCE_DIR "/package/contents/ui/CropEngine.js"));
    if (!f.open(QIODevice::ReadOnly)) return {};
    QString src = QString::fromUtf8(f.readAll());
    src.replace(u".pragma library"_s, QString());
    QJSEngine engine;
    engine.evaluate(src);
    const QJSValue opts = engine.evaluate(u"("_s + optsJson + u")"_s);
    return engine.globalObject().property(u"buildApplyJs"_s)
        .call({QJSValue(selector), opts}).toString();
}

const char kHarnessQml[] = R"(
import QtQuick
import QtQuick.Window
import QtWebEngine
Window {
    width: 480; height: 320; visible: true
    property alias view: v
    property string consoleLog: ""
    property var jsResult: undefined
    property bool jsDone: false
    function run(js) {
        jsDone = false;
        v.runJavaScript(js, function(r) { jsResult = r; jsDone = true; });
    }
    WebEngineView {
        id: v
        anchors.fill: parent
        onJavaScriptConsoleMessage: function(level, message) {
            consoleLog += message + "\n";
        }
    }
}
)";

} // namespace

class TestCropEngineE2E : public QObject
{
    Q_OBJECT

    QQmlEngine *m_engine = nullptr;
    QQuickWindow *m_win = nullptr;

    QQuickItem *view() const
    {
        return m_win->property("view").value<QQuickItem *>();
    }
    QVariant run(const QString &js)
    {
        QMetaObject::invokeMethod(m_win, "run", Q_ARG(QVariant, js));
        if (!QTest::qWaitFor([&] { return m_win->property("jsDone").toBool(); }, 5000)) {
            return QVariant(u"<timeout>"_s);
        }
        return m_win->property("jsResult");
    }
    bool loadHtml(const QString &html)
    {
        QMetaObject::invokeMethod(view(), "loadHtml", Q_ARG(QString, html),
                                  Q_ARG(QUrl, QUrl(u"http://ifp.test/"_s)));
        // about:blank is "complete" too — wait for OUR document.
        return QTest::qWaitFor([&] {
            return run(u"location.href + ' ' + document.readyState"_s)
                   == u"http://ifp.test/ complete"_s;
        }, 10000);
    }

private Q_SLOTS:
    void initTestCase()
    {
        QtWebEngineQuick::initialize();
    }

    void init()
    {
        m_engine = new QQmlEngine;
        QQmlComponent c(m_engine);
        c.setData(kHarnessQml, QUrl(u"qrc:/harness.qml"_s));
        m_win = qobject_cast<QQuickWindow *>(c.create());
        QVERIFY2(m_win, qPrintable(c.errorString()));
        QVERIFY(QTest::qWaitForWindowExposed(m_win));
    }

    void cleanup()
    {
        delete m_win;
        m_win = nullptr;
        delete m_engine;
        m_engine = nullptr;
    }

    // Premise of the hidden keyword-scan fix: an invisible WebEngineView
    // (non-current StackLayout child) gets no animation frames, while
    // timers keep running.
    void hiddenView_stopsAnimationFrames_timersContinue()
    {
        QVERIFY(loadHtml(u"<!doctype html><body>x<script>"
                         "window.__raf=0; window.__iv=0;"
                         "(function f(){ __raf++; requestAnimationFrame(f); })();"
                         "setInterval(function(){ __iv++; }, 100);"
                         "</script></body>"_s));
        QTest::qWait(1000);
        const int rafVisible = run(u"__raf"_s).toInt();
        if (rafVisible < 5) {
            QSKIP("no animation frames even while visible (headless compositor?)");
        }

        view()->setVisible(false);
        QTest::qWait(300);
        const int raf0 = run(u"__raf"_s).toInt();
        const int iv0 = run(u"__iv"_s).toInt();
        QTest::qWait(2000);
        const int rafHidden = run(u"__raf"_s).toInt() - raf0;
        const int ivHidden = run(u"__iv"_s).toInt() - iv0;
        qInfo() << "visible rAF/1s" << rafVisible << "hidden rAF/2s" << rafHidden
                << "hidden interval ticks/2s" << ivHidden
                << "document.hidden" << run(u"document.hidden"_s).toBool();
        QCOMPARE(rafHidden, 0);
        QVERIFY(ivHidden > 0);
    }

    // Keyword exclusion must be able to clear while the tab is hidden: the
    // excluded thumbnail is invisible, so the scan can't depend on rAF.
    void hiddenView_keywordClearIsReported()
    {
        QVERIFY(loadHtml(u"<!doctype html><body><div id='t'>No active streams</div></body>"_s));
        const QString apply = buildApplyJs(u"#t"_s, u"{\"keywords\":[\"No active streams\"]}"_s);
        QVERIFY(!apply.isEmpty());
        run(apply);
        QTRY_VERIFY_WITH_TIMEOUT(m_win->property("consoleLog").toString()
                                     .contains(u"[ifp-keyword] hit=true"_s), 5000);

        view()->setVisible(false);
        QTest::qWait(300);
        run(u"document.getElementById('t').textContent = 'Streaming now';"_s);
        // The 3 s interval must pick it up while hidden.
        QTRY_VERIFY_WITH_TIMEOUT(m_win->property("consoleLog").toString()
                                     .contains(u"[ifp-keyword] hit=false"_s), 8000);
    }

    // Fit mode must go idle on a static page: re-applying the same scale
    // must not re-trigger the wrapper observer every frame.
    void fitMode_isIdleOnStaticPage()
    {
        QVERIFY(loadHtml(u"<!doctype html><body style='margin:0'>"
                         "<div id='wrap'><div id='t' style='width:100px;height:60px'>small</div></div>"
                         "<script>window.__resizes=0;"
                         "window.addEventListener('resize', function(){ __resizes++; });</script>"
                         "</body>"_s));
        const QString apply = buildApplyJs(u"#t"_s, u"{\"scaleMode\":\"fit\"}"_s);
        run(apply);
        // The wrapper MutationObserver is only installed by the first
        // schedule() — the 3 s interval — so settle past that first.
        QTest::qWait(3500);
        const int r0 = run(u"__resizes"_s).toInt();
        QTest::qWait(3000);
        const int r1 = run(u"__resizes"_s).toInt();
        qInfo() << "fit-mode resize events: settle" << r0 << "next 3s" << (r1 - r0)
                << "transform" << run(u"document.getElementById('t').style.transform"_s).toString()
                << "wrapObserver" << run(u"!!window.__ifpThumbWrapObserver"_s).toBool();
        QVERIFY(run(u"document.getElementById('t').style.transform"_s).toString()
                    .startsWith(u"scale("_s));
        // Only the 3 s interval may re-apply (at most one tick in 3 s).
        QVERIFY2(r1 - r0 <= 1, qPrintable(u"fit mode re-applied %1 times in 3 s"_s.arg(r1 - r0)));
    }

    // ...but a real content change inside the wrapper still re-scales.
    void fitMode_followsContentResize()
    {
        QVERIFY(loadHtml(u"<!doctype html><body style='margin:0'>"
                         "<div id='wrap'><div id='t'><div id='inner' style='width:100px;height:60px'>"
                         "small</div></div></div></body>"_s));
        run(buildApplyJs(u"#t"_s, u"{\"scaleMode\":\"fit\"}"_s));
        QTest::qWait(3500);                 // past the first schedule()
        const QString before = run(u"document.getElementById('t').style.transform"_s).toString();
        QVERIFY(before.startsWith(u"scale("_s));
        run(u"document.getElementById('inner').style.width = '200px';"_s);
        QTRY_VERIFY_WITH_TIMEOUT(
            run(u"document.getElementById('t').style.transform"_s).toString() != before, 5000);
    }
};

QTEST_MAIN(TestCropEngineE2E)
#include "tst_cropengine_e2e.moc"
