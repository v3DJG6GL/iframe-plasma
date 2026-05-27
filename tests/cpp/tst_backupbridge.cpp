/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#include "backupbridge.h"

#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::Literals::StringLiterals;

namespace {

// Seed map covering every schema key — used by round-trip + filter tests
// so each entry is exercised at least once.
QVariantMap fullSchemaSeed()
{
    QVariantMap m;
    m.insert(u"urlsJson"_s, u"[{\"label\":\"a\",\"url\":\"https://a.example.test\"}]"_s);
    m.insert(u"currentTabIndex"_s, 2);
    m.insert(u"autoCycleEnabled"_s, true);
    m.insert(u"autoCycleIntervalSec"_s, 90);
    m.insert(u"zoomFactor"_s, 125);
    m.insert(u"themeMode"_s, u"dark"_s);
    m.insert(u"showTabBar"_s, false);
    m.insert(u"compactPreviewEnabled"_s, true);
    m.insert(u"compactPreviewShowLabel"_s, true);
    m.insert(u"compactPreviewLongAxisPx"_s, 200);
    m.insert(u"popupPinned"_s, true);
    m.insert(u"authProfilesJson"_s, u"[{\"id\":\"abc\",\"name\":\"p\",\"authType\":\"basic\"}]"_s);
    m.insert(u"userAgentOverride"_s, u"Mozilla/5.0 iframe-plasma/test"_s);
    m.insert(u"remoteDebuggingPort"_s, 9222);
    m.insert(u"webViewFreezeDelaySec"_s, 45);
    m.insert(u"webViewDiscardDelaySec"_s, 900);
    return m;
}

} // namespace

class TestBackupBridge : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_xdg;

private Q_SLOTS:
    void initTestCase()
    {
        QVERIFY(m_xdg.isValid());
        // Redirect XDG_CONFIG_HOME so the pre-import backup writes into
        // a sandbox we control + verify.
        qputenv("XDG_CONFIG_HOME", m_xdg.path().toUtf8());
        QStandardPaths::setTestModeEnabled(false); // env override is enough
    }

    // ----- exportToFile happy path ----------------------------------

    void export_writesValidEnvelope()
    {
        BackupBridge b;
        const QString path = m_xdg.filePath(u"export1.json"_s);
        QCOMPARE(b.exportToFile(path, fullSchemaSeed()), QString{});

        QFile f(path);
        QVERIFY(f.open(QIODevice::ReadOnly));
        QJsonParseError err;
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
        QCOMPARE(err.error, QJsonParseError::NoError);
        QVERIFY(doc.isObject());
        const QJsonObject root = doc.object();
        QCOMPARE(root.value(u"$schema"_s).toString(), u"iframe-plasma-config"_s);
        QCOMPARE(root.value(u"version"_s).toInt(), 1);
        QVERIFY(!root.value(u"appletVersion"_s).toString().isEmpty());
        QVERIFY(!root.value(u"exportedAt"_s).toString().isEmpty());
        QVERIFY(root.value(u"config"_s).isObject());
    }

    void export_writesAllSixteenWhitelistedKeys()
    {
        BackupBridge b;
        const QString path = m_xdg.filePath(u"export2.json"_s);
        QCOMPARE(b.exportToFile(path, fullSchemaSeed()), QString{});

        QFile f(path);
        QVERIFY(f.open(QIODevice::ReadOnly));
        const QJsonObject groups = QJsonDocument::fromJson(f.readAll())
                                       .object()
                                       .value(u"config"_s)
                                       .toObject();
        int totalKeys = 0;
        for (auto it = groups.constBegin(); it != groups.constEnd(); ++it) {
            totalKeys += it.value().toObject().size();
        }
        QCOMPARE(totalKeys, 16);
    }

    void export_groupsKeysByMainXmlGroup()
    {
        BackupBridge b;
        const QString path = m_xdg.filePath(u"export3.json"_s);
        QCOMPARE(b.exportToFile(path, fullSchemaSeed()), QString{});

        QFile f(path);
        QVERIFY(f.open(QIODevice::ReadOnly));
        const QJsonObject groups = QJsonDocument::fromJson(f.readAll())
                                       .object()
                                       .value(u"config"_s)
                                       .toObject();
        QVERIFY(groups.value(u"General"_s).toObject().contains(u"urlsJson"_s));
        QVERIFY(groups.value(u"Display"_s).toObject().contains(u"zoomFactor"_s));
        QVERIFY(groups.value(u"Auth"_s).toObject().contains(u"authProfilesJson"_s));
        QVERIFY(groups.value(u"Advanced"_s).toObject().contains(u"userAgentOverride"_s));
        // Cross-group leak check
        QVERIFY(!groups.value(u"General"_s).toObject().contains(u"zoomFactor"_s));
    }

    void export_stripsDeprecatedAndMigrationFlagKeys()
    {
        // Caller passes deprecated + migration-flag entries; export must
        // not include them even though they're valid in main.xml.
        QVariantMap seed = fullSchemaSeed();
        seed.insert(u"compactPreviewMode"_s, u"fixed"_s);
        seed.insert(u"compactPreviewTabIndex"_s, 2);
        seed.insert(u"compactPreviewMigrated"_s, true);
        seed.insert(u"autheliaHost"_s, u"auth.example.test"_s);
        seed.insert(u"useBasicAuthInjection"_s, true);
        seed.insert(u"authProfilesPreemptMigrated"_s, true);

        BackupBridge b;
        const QString path = m_xdg.filePath(u"export4.json"_s);
        QCOMPARE(b.exportToFile(path, seed), QString{});

        QFile f(path);
        QVERIFY(f.open(QIODevice::ReadOnly));
        const QJsonObject groups = QJsonDocument::fromJson(f.readAll())
                                       .object()
                                       .value(u"config"_s)
                                       .toObject();
        for (auto it = groups.constBegin(); it != groups.constEnd(); ++it) {
            const QJsonObject g = it.value().toObject();
            QVERIFY(!g.contains(u"compactPreviewMode"_s));
            QVERIFY(!g.contains(u"compactPreviewTabIndex"_s));
            QVERIFY(!g.contains(u"compactPreviewMigrated"_s));
            QVERIFY(!g.contains(u"autheliaHost"_s));
            QVERIFY(!g.contains(u"useBasicAuthInjection"_s));
            QVERIFY(!g.contains(u"authProfilesPreemptMigrated"_s));
        }
    }

    void export_tolerantOfPartialInput()
    {
        // Caller passes only a handful of keys; export writes only those.
        QVariantMap partial;
        partial.insert(u"zoomFactor"_s, 150);
        partial.insert(u"themeMode"_s, u"light"_s);

        BackupBridge b;
        const QString path = m_xdg.filePath(u"export5.json"_s);
        QCOMPARE(b.exportToFile(path, partial), QString{});

        QFile f(path);
        QVERIFY(f.open(QIODevice::ReadOnly));
        const QJsonObject groups = QJsonDocument::fromJson(f.readAll())
                                       .object()
                                       .value(u"config"_s)
                                       .toObject();
        QCOMPARE(groups.size(), 1);
        const QJsonObject display = groups.value(u"Display"_s).toObject();
        QCOMPARE(display.size(), 2);
        QCOMPARE(display.value(u"zoomFactor"_s).toInt(), 150);
        QCOMPARE(display.value(u"themeMode"_s).toString(), u"light"_s);
    }

    void export_setsOwnerOnlyPermissions()
    {
        BackupBridge b;
        const QString path = m_xdg.filePath(u"export6.json"_s);
        QCOMPARE(b.exportToFile(path, fullSchemaSeed()), QString{});

        const QFileDevice::Permissions p = QFile::permissions(path);
        QVERIFY(p & QFileDevice::ReadOwner);
        QVERIFY(p & QFileDevice::WriteOwner);
        QVERIFY(!(p & QFileDevice::ReadGroup));
        QVERIFY(!(p & QFileDevice::ReadOther));
    }

    // ----- exportToFile failure paths -------------------------------

    void export_unwritablePath_returnsError()
    {
        BackupBridge b;
        // A directory path that doesn't exist and can't be created here.
        const QString path = u"/nonexistent-dir-for-tests-42/x.json"_s;
        const QString err = b.exportToFile(path, fullSchemaSeed());
        QVERIFY(!err.isEmpty());
    }

    // ----- exportToFile: warning-vs-error contract ------------------

    void export_cleanSuccess_lastExportWarningEmpty()
    {
        // Happy path on a POSIX-permissioned tmpfs MUST leave
        // lastExportWarning() empty — callers gate UI behaviour on this.
        BackupBridge b;
        const QString path = m_xdg.filePath(u"export_warn_clean.json"_s);
        QCOMPARE(b.exportToFile(path, fullSchemaSeed()), QString{});
        QCOMPARE(b.lastExportWarning(), QString{});
    }

    void export_warningIsReset_betweenCalls()
    {
        // A subsequent successful export must clear any previously
        // set warning so the accessor always reflects the latest call.
        // Seed via the test hook because setPermissions only fails on
        // FAT/exFAT/SMB targets (not reproducible on tmpfs); without
        // the seed, exportToFile()'s top-of-function clear() would be
        // untested and a regression removing it would slip through.
        BackupBridge b;
        b.setLastExportWarningForTest(
            u"Wrote /old/path but could not restrict permissions to 0600."_s);
        QCOMPARE(b.lastExportWarning().isEmpty(), false);
        const QString p = m_xdg.filePath(u"export_warn_reset.json"_s);
        QCOMPARE(b.exportToFile(p, fullSchemaSeed()), QString{});
        QCOMPARE(b.lastExportWarning(), QString{});
    }

    // ----- importFromFile happy path --------------------------------

    void roundTrip_preservesAllSchemaValues()
    {
        const QVariantMap seed = fullSchemaSeed();
        BackupBridge b;
        const QString path = m_xdg.filePath(u"rt.json"_s);
        QCOMPARE(b.exportToFile(path, seed), QString{});

        // Use a deliberately different "current" map so the pre-import
        // backup is verifiable as the old (not the imported) state.
        QVariantMap currentBefore;
        currentBefore.insert(u"zoomFactor"_s, 100);

        const QVariantMap result = b.importFromFile(path, currentBefore);
        QCOMPARE(result.value(u"ok"_s).toBool(), true);
        QCOMPARE(result.value(u"error"_s).toString(), QString{});
        QCOMPARE(result.value(u"warning"_s).toString(), QString{});
        QVERIFY(result.value(u"skipped"_s).toStringList().isEmpty());

        const QVariantMap applied = result.value(u"config"_s).toMap();
        QCOMPARE(applied.size(), seed.size());
        // Spot-check several types: string, int, bool, JSON-blob string.
        QCOMPARE(applied.value(u"themeMode"_s).toString(), u"dark"_s);
        QCOMPARE(applied.value(u"zoomFactor"_s).toInt(), 125);
        QCOMPARE(applied.value(u"showTabBar"_s).toBool(), false);
        QCOMPARE(applied.value(u"urlsJson"_s).toString(), seed.value(u"urlsJson"_s).toString());
    }

    void import_writesPreImportBackup()
    {
        BackupBridge b;
        const QString src = m_xdg.filePath(u"src.json"_s);
        QCOMPARE(b.exportToFile(src, fullSchemaSeed()), QString{});

        QVariantMap currentBefore;
        currentBefore.insert(u"zoomFactor"_s, 75);
        currentBefore.insert(u"themeMode"_s, u"auto"_s);

        const QVariantMap result = b.importFromFile(src, currentBefore);
        QCOMPARE(result.value(u"ok"_s).toBool(), true);

        const QString backup = b.lastBackupPath();
        QVERIFY(!backup.isEmpty());
        QVERIFY(QFile::exists(backup));
        QVERIFY(backup.startsWith(m_xdg.path()));
        QVERIFY(QFileInfo(backup).fileName().startsWith(u"iframe-plasma-backup-"_s));

        // Backup contents = the "before" state, NOT the imported state.
        QFile f(backup);
        QVERIFY(f.open(QIODevice::ReadOnly));
        const QJsonObject groups = QJsonDocument::fromJson(f.readAll())
                                       .object()
                                       .value(u"config"_s)
                                       .toObject();
        QCOMPARE(groups.value(u"Display"_s).toObject().value(u"zoomFactor"_s).toInt(), 75);
    }

    void import_lastBackupPath_clearedOnSnapshotFailure()
    {
        // backupbridge.cpp:243 — m_lastBackupPath.clear() in the
        // snapshot-failure branch guards the QML caller's "Previous
        // configuration saved to %1" hint (ConfigBackup.qml reads
        // lastBackupPath() unconditionally on the ok branch). Without
        // the clear, an operator who ran a successful import and then
        // a second import whose snapshot write failed would be invited
        // to revert from the STALE prior path. Seed via the test hook
        // because driving a real prior success inline would need an
        // XDG flip mid-flight; mirrors the export_warningIsReset
        // pattern at the top of this section.
        BackupBridge b;
        const QString stale = m_xdg.filePath(u"stale-prior-backup.json"_s);
        b.setLastBackupPathForTest(stale);
        QCOMPARE(b.lastBackupPath(), stale);

        // Build a valid source file under the still-writable XDG dir.
        const QString src = m_xdg.filePath(u"src_snapfail.json"_s);
        QCOMPARE(b.exportToFile(src, fullSchemaSeed()), QString{});

        // Force the snapshot write to fail by redirecting XDG_CONFIG_HOME
        // at a path that can't be mkpath'd: a child of /dev/null, which
        // is a character device — not a directory. QSaveFile.open() in
        // exportToFile() then fails with EISDIR/ENOTDIR.
        const QByteArray prevXdg = qgetenv("XDG_CONFIG_HOME");
        qputenv("XDG_CONFIG_HOME", "/dev/null/iframe-plasma-snapfail");
        const QVariantMap result = b.importFromFile(src, QVariantMap{});
        qputenv("XDG_CONFIG_HOME", prevXdg);

        // ok=true with config payload (the import body succeeded), but
        // error is populated with the snapshot-failure message and the
        // stale path was cleared so the QML hint can't be rendered.
        QCOMPARE(result.value(u"ok"_s).toBool(), true);
        QVERIFY(result.value(u"error"_s).toString().contains(u"Pre-import backup failed"_s));
        QCOMPARE(b.lastBackupPath(), QString{});
    }

    // ----- importFromFile failure paths -----------------------------

    void import_missingFile_returnsError()
    {
        BackupBridge b;
        const QVariantMap result = b.importFromFile(m_xdg.filePath(u"nope.json"_s), {});
        QCOMPARE(result.value(u"ok"_s).toBool(), false);
        QVERIFY(!result.value(u"error"_s).toString().isEmpty());
    }

    void import_malformedJson_returnsError()
    {
        const QString path = m_xdg.filePath(u"bad.json"_s);
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("not json at all { [ }");
        f.close();

        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QCOMPARE(result.value(u"ok"_s).toBool(), false);
        QVERIFY(result.value(u"error"_s).toString().contains(u"Parse error"_s));
    }

    void import_wrongVersion_returnsError()
    {
        const QString path = m_xdg.filePath(u"v99.json"_s);
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("{\"version\":99,\"config\":{}}");
        f.close();

        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QCOMPARE(result.value(u"ok"_s).toBool(), false);
        QVERIFY(result.value(u"error"_s).toString().contains(u"Unsupported export version"_s));
    }

    void import_missingConfigObject_returnsError()
    {
        const QString path = m_xdg.filePath(u"nocfg.json"_s);
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("{\"version\":1}");
        f.close();

        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QCOMPARE(result.value(u"ok"_s).toBool(), false);
        QVERIFY(result.value(u"error"_s).toString().contains(u"`config` object"_s));
    }

    void import_nonObjectRoot_returnsError()
    {
        const QString path = m_xdg.filePath(u"arr.json"_s);
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("[]");
        f.close();

        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QCOMPARE(result.value(u"ok"_s).toBool(), false);
        QVERIFY(result.value(u"error"_s).toString().contains(u"not a JSON object"_s));
    }

    // ----- import forward-compat: unknown keys -----------------------

    void import_unknownKeys_reportedInSkipped()
    {
        // Hand-craft a file with a key that's not in the schema.
        const QString path = m_xdg.filePath(u"future.json"_s);
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(R"({
            "version": 1,
            "config": {
                "General": { "urlsJson": "[]", "futureKnob": true },
                "NewGroup": { "anotherFutureKnob": 42 }
            }
        })");
        f.close();

        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QCOMPARE(result.value(u"ok"_s).toBool(), true);
        const QStringList skipped = result.value(u"skipped"_s).toStringList();
        QVERIFY(skipped.contains(u"futureKnob"_s));
        QVERIFY(skipped.contains(u"anotherFutureKnob"_s));
        // The known key still applies.
        QCOMPARE(result.value(u"config"_s).toMap().value(u"urlsJson"_s).toString(), u"[]"_s);
    }

    // ----- import: deprecated keys in file are silently dropped ------
    // (same path as unknown keys — they're outside the schema).

    void import_deprecatedKeysInFile_excludedFromApply()
    {
        // A file from a hypothetical "older but same version" export
        // that still carries the deprecated entries. We never apply
        // them, and they're not in the schema so they're reported as
        // skipped (which is fine — they're forward-incompatible).
        const QString path = m_xdg.filePath(u"legacy.json"_s);
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(R"({
            "version": 1,
            "config": {
                "Display": { "compactPreviewMode": "fixed", "themeMode": "dark" },
                "Auth": { "useBasicAuthInjection": true }
            }
        })");
        f.close();

        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QCOMPARE(result.value(u"ok"_s).toBool(), true);
        const QVariantMap applied = result.value(u"config"_s).toMap();
        QVERIFY(!applied.contains(u"compactPreviewMode"_s));
        QVERIFY(!applied.contains(u"useBasicAuthInjection"_s));
        QCOMPARE(applied.value(u"themeMode"_s).toString(), u"dark"_s);
    }

    // ----- import: JSON null/undefined values surfaced as skipped ---

    void import_nullValueOnSchemaKey_reportedInSkippedAndExcluded()
    {
        // A schema-recognised key whose value is JSON null would convert
        // to an invalid QVariant; the QML _applyConfig loop would blindly
        // write it back to the kcfg_* alias and blank the live property.
        // The fix routes such keys to `skipped` (forward-compat
        // partial-import reporting) and excludes them from `config`.
        const QString path = m_xdg.filePath(u"nullval.json"_s);
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(R"({
            "version": 1,
            "config": {
                "General": { "urlsJson": null, "currentTabIndex": 3 }
            }
        })");
        f.close();

        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QCOMPARE(result.value(u"ok"_s).toBool(), true);
        const QStringList skipped = result.value(u"skipped"_s).toStringList();
        QVERIFY(skipped.contains(u"urlsJson"_s));
        const QVariantMap applied = result.value(u"config"_s).toMap();
        // Null-valued key MUST NOT appear in the apply map.
        QVERIFY(!applied.contains(u"urlsJson"_s));
        // Sibling non-null key still applies.
        QCOMPARE(applied.value(u"currentTabIndex"_s).toInt(), 3);
    }

    // ----- suggestedExportName --------------------------------------

    void suggestedExportName_hasExpectedShape()
    {
        BackupBridge b;
        const QString name = b.suggestedExportName();
        QVERIFY(name.startsWith(u"iframe-plasma-config-"_s));
        QVERIFY(name.endsWith(u".json"_s));
    }
};

QTEST_GUILESS_MAIN(TestBackupBridge)
#include "tst_backupbridge.moc"
