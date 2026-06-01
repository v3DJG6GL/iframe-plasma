/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#include "fakewallet.h"
#include "secretsbridge.h"

#include <QSignalSpy>
#include <QTest>
#include <memory>

using namespace Qt::Literals::StringLiterals;

// `QString(const char16_t*)` is implicit on Qt 6.8+ but missing on 6.7.2
// (which neon-unstable still ships in CI). Declare as `QString` via the
// `_s` UDL so the existing `QString(kFolder)` call sites are no-op
// copy-constructs that compile on both.
static const QString kFolder = u"io.github.v3DJG6GL.iframe-plasma"_s;

static std::unique_ptr<FakeWallet> makeWallet()
{
    return std::make_unique<FakeWallet>();
}

class TestSecretsBridge : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    // ---------------------------------------------------------------
    // Construction + isWalletReady lifecycle
    // ---------------------------------------------------------------
    void freshBridge_isNotReady()
    {
        SecretsBridge b{makeWallet()};
        QVERIFY(!b.isWalletReady());
    }

    void afterSuccessfulHas_isReady()
    {
        SecretsBridge b{makeWallet()};
        b.has(u"k"_s);  // triggers ensureOpen
        QVERIFY(b.isWalletReady());
    }

    void afterCloseForTest_isNotReady()
    {
        auto w = makeWallet();
        auto *raw = w.get();
        SecretsBridge b{std::move(w)};
        b.has(u"k"_s);
        QVERIFY(b.isWalletReady());
        raw->closeForTest();
        QVERIFY(!b.isWalletReady());
    }

    // ---------------------------------------------------------------
    // has()
    // ---------------------------------------------------------------
    void has_emptyKey_false()
    {
        SecretsBridge b{makeWallet()};
        QVERIFY(!b.has(u""_s));
    }

    void has_walletUnavailable_false()
    {
        auto w = makeWallet();
        w->setEnabled(false);
        SecretsBridge b{std::move(w)};
        QVERIFY(!b.has(u"k"_s));
    }

    void has_present_true()
    {
        auto w = makeWallet();
        w->seedPassword(QString(kFolder), u"k"_s, u"v"_s);
        SecretsBridge b{std::move(w)};
        QVERIFY(b.has(u"k"_s));
    }

    void has_absent_false()
    {
        auto w = makeWallet();
        w->seedPassword(QString(kFolder), u"a"_s, u"v"_s);
        SecretsBridge b{std::move(w)};
        QVERIFY(!b.has(u"b"_s));
    }

    // ---------------------------------------------------------------
    // getMap() / setMap() round-trip
    // ---------------------------------------------------------------
    void getMap_emptyKey_returnsEmpty()
    {
        SecretsBridge b{makeWallet()};
        QCOMPARE(b.getMap(u""_s), QVariantMap());
    }

    void getMap_walletUnavailable_returnsEmpty()
    {
        auto w = makeWallet();
        w->setEnabled(false);
        SecretsBridge b{std::move(w)};
        QCOMPARE(b.getMap(u"k"_s), QVariantMap());
    }

    void getMap_walletReadFails_returnsEmpty()
    {
        auto w = makeWallet();
        QMap<QString, QString> m{{u"password"_s, u"p"_s}};
        w->seedMap(QString(kFolder), u"k"_s, m);
        w->setReadWillFail(true);
        SecretsBridge b{std::move(w)};
        QCOMPARE(b.getMap(u"k"_s), QVariantMap());
    }

    void getMap_success_returnsAllFields()
    {
        auto w = makeWallet();
        QMap<QString, QString> m{{u"password"_s, u"p"_s},
                                  {u"bearerToken"_s, u"t"_s},
                                  {u"rawHeader"_s, u"r"_s}};
        w->seedMap(QString(kFolder), u"profile:abc"_s, m);
        SecretsBridge b{std::move(w)};
        const QVariantMap got = b.getMap(u"profile:abc"_s);
        QCOMPARE(got.value(u"password"_s).toString(), u"p"_s);
        QCOMPARE(got.value(u"bearerToken"_s).toString(), u"t"_s);
        QCOMPARE(got.value(u"rawHeader"_s).toString(), u"r"_s);
    }

    void setMap_emptyKey_returnsFalse()
    {
        SecretsBridge b{makeWallet()};
        QVERIFY(!b.setMap(u""_s, {{u"x"_s, u"y"_s}}));
    }

    void setMap_walletUnavailable_returnsFalse()
    {
        auto w = makeWallet();
        w->setEnabled(false);
        SecretsBridge b{std::move(w)};
        QVERIFY(!b.setMap(u"k"_s, {{u"x"_s, u"y"_s}}));
    }

    void setMap_writeFails_returnsFalse()
    {
        auto w = makeWallet();
        w->setWriteWillFail(true);
        SecretsBridge b{std::move(w)};
        QVERIFY(!b.setMap(u"k"_s, {{u"x"_s, u"y"_s}}));
    }

    void setMap_roundtrip()
    {
        SecretsBridge b{makeWallet()};
        const QVariantMap in{{u"password"_s, u"p"_s}, {u"bearerToken"_s, u"t"_s}};
        QVERIFY(b.setMap(u"profile:1"_s, in));
        const QVariantMap out = b.getMap(u"profile:1"_s);
        QCOMPARE(out.value(u"password"_s).toString(), u"p"_s);
        QCOMPARE(out.value(u"bearerToken"_s).toString(), u"t"_s);
    }

    // ---------------------------------------------------------------
    // removeKey()
    // ---------------------------------------------------------------
    void removeKey_emptyKey_returnsFalse()
    {
        SecretsBridge b{makeWallet()};
        QVERIFY(!b.removeKey(u""_s));
    }

    void removeKey_walletUnavailable_returnsFalse()
    {
        auto w = makeWallet();
        w->setEnabled(false);
        SecretsBridge b{std::move(w)};
        QVERIFY(!b.removeKey(u"k"_s));
    }

    void removeKey_present_returnsTrueAndGone()
    {
        SecretsBridge b{makeWallet()};
        QVERIFY(b.setMap(u"k"_s, {{u"x"_s, u"y"_s}}));
        QVERIFY(b.removeKey(u"k"_s));
        QVERIFY(b.getMap(u"k"_s).isEmpty());
    }

    void removeKey_absent_returnsFalse()
    {
        SecretsBridge b{makeWallet()};
        QVERIFY(!b.removeKey(u"never-stored"_s));
    }

    // ---------------------------------------------------------------
    // Folder auto-creation
    // ---------------------------------------------------------------
    void ensureOpen_createsFolderIfMissing()
    {
        auto w = makeWallet();
        auto *raw = w.get();
        SecretsBridge b{std::move(w)};
        QVERIFY(!raw->hasFolderForTest(QString(kFolder)));
        b.has(u"any-key"_s);
        QVERIFY(raw->hasFolderForTest(QString(kFolder)));
    }

    // Warm-path recovery: when an external actor (kwalletmanager) removes
    // the folder while our wallet handle is still open, the next setFolder
    // call fails. ensureOpen must detect this, recreate the folder and
    // retry — otherwise subsequent reads/writes silently target whatever
    // folder kwalletd settled on. Without coverage, a regression that drops
    // the recovery branch passes CI because the empty-folder path still
    // satisfies the rest of the SecretsBridge contract.
    void ensureOpen_warmPath_folderDeletedExternally_recoversAndCompletesWrite()
    {
        auto w = makeWallet();
        auto *raw = w.get();
        SecretsBridge b{std::move(w)};
        // Prime the warm-path: open the wallet and set folder.
        QVERIFY(b.setMap(u"k1"_s, {{u"a"_s, u"1"_s}}));
        QVERIFY(raw->hasFolderForTest(QString(kFolder)));
        // External deletion — wallet still open, but folder is gone.
        raw->removeFolderForTest(QString(kFolder));
        QVERIFY(!raw->hasFolderForTest(QString(kFolder)));
        // Next op enters the warm-path; setFolder fails → recovery
        // branch recreates the folder and the write must succeed.
        QVERIFY(b.setMap(u"k2"_s, {{u"b"_s, u"2"_s}}));
        QVERIFY(raw->hasFolderForTest(QString(kFolder)));
    }

    void ensureOpen_warmPath_folderDeletedExternally_recoversAndReads()
    {
        auto w = makeWallet();
        auto *raw = w.get();
        SecretsBridge b{std::move(w)};
        b.has(u"any-key"_s);  // prime warm-path
        raw->removeFolderForTest(QString(kFolder));
        // has() must not raise an error signal on the recovery path;
        // a missing key after recreate returns false without going through
        // the unenabled / open-failed branches.
        QSignalSpy errSpy(&b, &SecretsBridge::error);
        QVERIFY(!b.has(u"any-key"_s));
        QCOMPARE(errSpy.count(), 0);
        QVERIFY(raw->hasFolderForTest(QString(kFolder)));
    }

    // ---------------------------------------------------------------
    // secretsChanged signal — load-bearing for the prime-after-write
    // chain (AuthSupport.qml wires this into the QML support signal,
    // which main.qml uses to re-fire primeAuthProfiles so a freshly
    // entered password reaches the interceptor — see 67e2651).
    // Untested, a regression that drops Q_EMIT secretsChanged() or
    // fires it on a failure path silently breaks that flow.
    // ---------------------------------------------------------------
    void setMap_success_emitsSecretsChanged()
    {
        SecretsBridge b{makeWallet()};
        QSignalSpy spy(&b, &SecretsBridge::secretsChanged);
        QVERIFY(b.setMap(u"k"_s, {{u"x"_s, u"y"_s}}));
        QCOMPARE(spy.count(), 1);
    }

    void setMap_failure_doesNotEmitSecretsChanged()
    {
        auto w = makeWallet();
        w->setWriteWillFail(true);
        SecretsBridge b{std::move(w)};
        QSignalSpy spy(&b, &SecretsBridge::secretsChanged);
        QVERIFY(!b.setMap(u"k"_s, {{u"x"_s, u"y"_s}}));
        QCOMPARE(spy.count(), 0);
    }

    void removeKey_success_emitsSecretsChanged()
    {
        SecretsBridge b{makeWallet()};
        QVERIFY(b.setMap(u"k"_s, {{u"x"_s, u"y"_s}}));
        QSignalSpy spy(&b, &SecretsBridge::secretsChanged);
        QVERIFY(b.removeKey(u"k"_s));
        QCOMPARE(spy.count(), 1);
    }

    void removeKey_absent_doesNotEmitSecretsChanged()
    {
        SecretsBridge b{makeWallet()};
        QSignalSpy spy(&b, &SecretsBridge::secretsChanged);
        QVERIFY(!b.removeKey(u"never-stored"_s));
        QCOMPARE(spy.count(), 0);
    }
};

QTEST_GUILESS_MAIN(TestSecretsBridge)
#include "tst_secretsbridge.moc"
