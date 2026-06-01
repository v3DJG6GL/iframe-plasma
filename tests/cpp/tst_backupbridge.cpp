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
#include <QSet>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>
#include <QXmlStreamReader>

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
    m.insert(u"compactPreviewLongAxisPx"_s, 200);
    m.insert(u"popupPinned"_s, true);
    m.insert(u"authProfilesJson"_s, u"[{\"id\":\"abc\",\"name\":\"p\",\"authType\":\"basic\"}]"_s);
    m.insert(u"userAgentOverride"_s, u"Mozilla/5.0 iframe-plasma/test"_s);
    m.insert(u"remoteDebuggingPort"_s, 9222);
    m.insert(u"webViewFreezeDelaySec"_s, 45);
    m.insert(u"webViewDiscardDelaySec"_s, 900);
    return m;
}

// Write `content` to dir/name and return the absolute path. Mirrors the
// inline open/write/close pattern the import tests already use; factored
// out so the type-validation cases below stay readable.
QString writeFile(const QTemporaryDir &dir, const QString &name, const char *content)
{
    const QString path = dir.filePath(name);
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly)) {
        return QString{}; // caller's import will fail visibly on an empty path
    }
    f.write(content);
    f.close();
    return path;
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

    void export_writesAllFifteenWhitelistedKeys()
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
        QCOMPARE(totalKeys, 15);
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

    // ----- import: strict per-key type validation -------------------
    //
    // A schema key whose JSON value kind doesn't match the kcfg type
    // (e.g. a string for an Int) would reach a typed QML alias in
    // _applyConfig and be silently coerced/clamped (a SpinBox turns
    // "abc" into 0 → clamped to `from`). importFromFile routes such
    // mismatches to `skipped` instead, exactly like the null path.

    void import_stringForIntKey_reportedInSkippedAndExcluded()
    {
        const QString path = writeFile(m_xdg, u"ti_strForInt.json"_s, R"({
            "version": 1,
            "config": { "Display": { "zoomFactor": "abc" } }
        })");
        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QCOMPARE(result.value(u"ok"_s).toBool(), true);
        QVERIFY(result.value(u"skipped"_s).toStringList().contains(u"zoomFactor"_s));
        QVERIFY(!result.value(u"config"_s).toMap().contains(u"zoomFactor"_s));
    }

    void import_boolForIntKey_reportedInSkipped()
    {
        const QString path = writeFile(m_xdg, u"ti_boolForInt.json"_s, R"({
            "version": 1,
            "config": { "General": { "currentTabIndex": true } }
        })");
        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QVERIFY(result.value(u"skipped"_s).toStringList().contains(u"currentTabIndex"_s));
        QVERIFY(!result.value(u"config"_s).toMap().contains(u"currentTabIndex"_s));
    }

    void import_numberForBoolKey_reportedInSkipped()
    {
        // Strict: 0/1 for a Bool key is rejected (never produced by our
        // own export, which always emits JSON true/false).
        const QString path = writeFile(m_xdg, u"ti_numForBool.json"_s, R"({
            "version": 1,
            "config": { "Display": { "showTabBar": 1 } }
        })");
        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QVERIFY(result.value(u"skipped"_s).toStringList().contains(u"showTabBar"_s));
        QVERIFY(!result.value(u"config"_s).toMap().contains(u"showTabBar"_s));
    }

    void import_numberForStringKey_reportedInSkipped()
    {
        const QString path = writeFile(m_xdg, u"ti_numForStr.json"_s, R"({
            "version": 1,
            "config": { "Display": { "themeMode": 5 } }
        })");
        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QVERIFY(result.value(u"skipped"_s).toStringList().contains(u"themeMode"_s));
        QVERIFY(!result.value(u"config"_s).toMap().contains(u"themeMode"_s));
    }

    void import_fractionalDoubleForIntKey_reportedInSkipped()
    {
        // Reject (do NOT floor) — flooring would silently apply a value
        // the user never wrote.
        const QString path = writeFile(m_xdg, u"ti_fracForInt.json"_s, R"({
            "version": 1,
            "config": { "Advanced": { "webViewFreezeDelaySec": 30.7 } }
        })");
        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QVERIFY(result.value(u"skipped"_s).toStringList().contains(u"webViewFreezeDelaySec"_s));
        QVERIFY(!result.value(u"config"_s).toMap().contains(u"webViewFreezeDelaySec"_s));
    }

    void import_integralDoubleForIntKey_applied()
    {
        // JSON has no int/double split; an integral double is the on-wire
        // shape of every exported Int, so it MUST round-trip cleanly.
        const QString path = writeFile(m_xdg, u"ti_intDouble.json"_s, R"({
            "version": 1,
            "config": { "Display": { "zoomFactor": 125.0 } }
        })");
        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QVERIFY(!result.value(u"skipped"_s).toStringList().contains(u"zoomFactor"_s));
        QCOMPARE(result.value(u"config"_s).toMap().value(u"zoomFactor"_s).toInt(), 125);
    }

    void import_correctlyTypedValues_allApplied()
    {
        // Guard against an over-eager validator rejecting valid input.
        const QString path = writeFile(m_xdg, u"ti_allValid.json"_s, R"({
            "version": 1,
            "config": {
                "Display": { "themeMode": "dark", "zoomFactor": 150, "showTabBar": false }
            }
        })");
        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QVERIFY(result.value(u"skipped"_s).toStringList().isEmpty());
        const QVariantMap applied = result.value(u"config"_s).toMap();
        QCOMPARE(applied.value(u"themeMode"_s).toString(), u"dark"_s);
        QCOMPARE(applied.value(u"zoomFactor"_s).toInt(), 150);
        QCOMPARE(applied.value(u"showTabBar"_s).toBool(), false);
    }

    void import_wrongTypeWithValidSibling_partialApply()
    {
        // One bad field must not poison the whole import.
        const QString path = writeFile(m_xdg, u"ti_partial.json"_s, R"({
            "version": 1,
            "config": { "Display": { "zoomFactor": "oops", "themeMode": "light" } }
        })");
        BackupBridge b;
        const QVariantMap result = b.importFromFile(path, {});
        QCOMPARE(result.value(u"ok"_s).toBool(), true);
        QVERIFY(result.value(u"skipped"_s).toStringList().contains(u"zoomFactor"_s));
        const QVariantMap applied = result.value(u"config"_s).toMap();
        QVERIFY(!applied.contains(u"zoomFactor"_s));
        QCOMPARE(applied.value(u"themeMode"_s).toString(), u"light"_s);
    }

    // ----- schema guard: kSchema == main.xml minus exclusions -------

    void schema_matchesMainXmlMinusExclusions()
    {
        // Catches a kcfg entry added to main.xml but forgotten in kSchema
        // (or vice-versa) — the drift the four-list backup design risks.
        // Keep this exclusion set in sync with the comment at
        // backupbridge.cpp's kSchema and BACKUP_EXCLUDE in
        // tests/fixtures/check_kcfg_coverage.py.
        const QSet<QString> kExcluded = {u"authProfilesSecretsSerial"_s};

        const QString xmlPath =
            QStringLiteral(IFRAME_SOURCE_DIR "/package/contents/config/main.xml");
        QFile f(xmlPath);
        QVERIFY2(f.open(QIODevice::ReadOnly), qPrintable(xmlPath));

        QSet<QString> xmlKeys;
        QXmlStreamReader xml(&f);
        while (!xml.atEnd()) {
            if (xml.readNext() == QXmlStreamReader::StartElement && xml.name() == u"entry") {
                const QString name = xml.attributes().value(u"name").toString();
                if (!name.isEmpty() && !kExcluded.contains(name)) {
                    xmlKeys.insert(name);
                }
            }
        }
        QVERIFY2(!xml.hasError(), qPrintable(xml.errorString()));

        BackupBridge b;
        const QStringList sk = b.schemaKeys();
        const QSet<QString> schema(sk.cbegin(), sk.cend());
        QCOMPARE(schema, xmlKeys);
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
