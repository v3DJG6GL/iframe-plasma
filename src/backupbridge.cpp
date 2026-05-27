/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#include "backupbridge.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QSaveFile>
#include <QStandardPaths>

using namespace Qt::Literals::StringLiterals;

namespace {

// Single source of truth for which kcfg entries round-trip through the
// export. Order matches main.xml so a diff between an exported file and
// main.xml is human-readable. Deliberately omitted:
//   * compactPreviewMode / compactPreviewTabIndex / autheliaHost (global)
//     / useBasicAuthInjection — deprecated; only read once by the
//     one-shot migrations in main.qml's Component.onCompleted.
//   * compactPreviewMigrated / authProfilesPreemptMigrated — migration
//     flags. On import we force-reset both to false so any legacy-shaped
//     data in the imported file re-triggers the migration cleanly.
//   * authProfilesSecretsSerial — transient session counter ConfigAuth
//     uses to notify main.qml of KWallet writes across the dialog/widget
//     engine boundary; never exported.
struct Entry
{
    const char *group;
    const char *key;
};
constexpr Entry kSchema[] = {
    {"General", "urlsJson"},
    {"General", "currentTabIndex"},
    {"General", "autoCycleEnabled"},
    {"General", "autoCycleIntervalSec"},
    {"Display", "zoomFactor"},
    {"Display", "themeMode"},
    {"Display", "showTabBar"},
    {"Display", "compactPreviewEnabled"},
    {"Display", "compactPreviewShowLabel"},
    {"Display", "compactPreviewLongAxisPx"},
    {"Display", "popupPinned"},
    {"Auth", "authProfilesJson"},
    {"Advanced", "userAgentOverride"},
    {"Advanced", "remoteDebuggingPort"},
    {"Advanced", "webViewFreezeDelaySec"},
    {"Advanced", "webViewDiscardDelaySec"},
};

constexpr int kSchemaVersion = 1;

// Mirrors package/metadata.json's KPlugin.Version. Hardcoded here rather
// than parsed at runtime because the C++ plugin .so and metadata.json
// are always shipped together; a mismatch would already be a packaging
// bug. Bump when metadata.json bumps.
constexpr auto kAppletVersion = "0.5.0";

QString iso8601Now()
{
    return QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
}

// Resolve XDG_CONFIG_HOME (respects the env override so tests can point
// it at a QTemporaryDir). Falls back to ~/.config per XDG spec.
QString configHome()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
}

} // namespace

BackupBridge::BackupBridge(QObject *parent)
    : QObject(parent)
{
}

QString BackupBridge::exportToFile(const QString &path, const QVariantMap &config)
{
    // Reset before each call so lastExportWarning() reflects only the
    // most recent export and stale warnings from a prior FAT-target
    // attempt don't leak into a subsequent ext4 export.
    m_lastExportWarning.clear();

    QJsonObject root;
    root[u"$schema"_s] = u"iframe-plasma-config"_s;
    root[u"version"_s] = kSchemaVersion;
    root[u"appletVersion"_s] = QString::fromLatin1(kAppletVersion);
    root[u"exportedAt"_s] = iso8601Now();

    // Group whitelisted keys by their main.xml group. QMap keeps groups
    // in insertion order based on schema order, which matches main.xml.
    QMap<QString, QJsonObject> byGroup;
    for (const auto &e : kSchema) {
        const QString group = QString::fromLatin1(e.group);
        const QString key = QString::fromLatin1(e.key);
        if (!config.contains(key)) {
            continue; // tolerant — caller may have a partial map
        }
        byGroup[group].insert(key, QJsonValue::fromVariant(config.value(key)));
    }
    QJsonObject groups;
    for (auto it = byGroup.cbegin(); it != byGroup.cend(); ++it) {
        groups.insert(it.key(), it.value());
    }
    root[u"config"_s] = groups;

    const QByteArray bytes = QJsonDocument(root).toJson(QJsonDocument::Indented);

    QSaveFile out(path);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return u"Cannot open file for writing: "_s + out.errorString();
    }
    if (out.write(bytes) != bytes.size()) {
        const QString err = out.errorString();
        out.cancelWriting();
        return u"Write failed: "_s + err;
    }
    if (!out.commit()) {
        return u"Commit failed: "_s + out.errorString();
    }
    // 0600 — no secrets in the file by design, but be conservative
    // anyway: the file lists every Authelia host the user touches.
    // On FAT/exFAT/SMB filesystems (a likely transport for "move tabs
    // between machines") setPermissions silently fails and the file
    // keeps default umask perms; surface that through lastExportWarning()
    // so the export is reported as successful (the file IS written and
    // usable) but the user can still see the perm-restriction warning.
    if (!QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner)) {
        m_lastExportWarning = u"Wrote %1 but could not restrict permissions to 0600 (filesystem may not honour POSIX perms)."_s.arg(path);
    }
    return {};
}

QVariantMap BackupBridge::importFromFile(const QString &path, const QVariantMap &currentConfig)
{
    QVariantMap result;
    result.insert(u"ok"_s, false);
    result.insert(u"error"_s, QString{});
    result.insert(u"warning"_s, QString{});
    result.insert(u"config"_s, QVariantMap{});
    result.insert(u"skipped"_s, QStringList{});

    QFile in(path);
    if (!in.open(QIODevice::ReadOnly)) {
        result[u"error"_s] = QString(u"Cannot open file: "_s + in.errorString());
        return result;
    }
    const QByteArray bytes = in.readAll();
    in.close();

    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(bytes, &err);
    if (err.error != QJsonParseError::NoError) {
        result[u"error"_s] = u"Parse error at offset %1: %2"_s.arg(err.offset).arg(err.errorString());
        return result;
    }
    if (!doc.isObject()) {
        result[u"error"_s] = u"Root is not a JSON object"_s;
        return result;
    }
    const QJsonObject root = doc.object();
    const int version = root.value(u"version"_s).toInt(-1);
    if (version != kSchemaVersion) {
        result[u"error"_s] = u"Unsupported export version: %1 (expected %2)"_s.arg(version).arg(
            kSchemaVersion);
        return result;
    }
    const QJsonValue configVal = root.value(u"config"_s);
    if (!configVal.isObject()) {
        result[u"error"_s] = u"Missing or invalid `config` object"_s;
        return result;
    }
    const QJsonObject groups = configVal.toObject();

    // Build the schema-filtered map. Anything in the file but not in
    // kSchema is reported in `skipped` (forward-compat for files
    // exported from a future applet version that added entries).
    QSet<QString> schemaKeys;
    for (const auto &e : kSchema) {
        schemaKeys.insert(QString::fromLatin1(e.key));
    }
    QVariantMap toApply;
    QStringList skipped;
    for (auto gIt = groups.constBegin(); gIt != groups.constEnd(); ++gIt) {
        if (!gIt.value().isObject()) {
            continue;
        }
        const QJsonObject groupObj = gIt.value().toObject();
        for (auto kIt = groupObj.constBegin(); kIt != groupObj.constEnd(); ++kIt) {
            const QString k = kIt.key();
            if (!schemaKeys.contains(k)) {
                skipped.append(k);
                continue;
            }
            // JSON null/undefined would convert to an invalid QVariant
            // which the QML _applyConfig loop blindly writes back to the
            // kcfg_* alias — blanking the live property and corrupting
            // KConfig on Apply. Surface them via `skipped` so the QML
            // side knows the import was partial.
            if (kIt.value().isNull() || kIt.value().isUndefined()) {
                skipped.append(k);
                continue;
            }
            toApply.insert(k, kIt.value().toVariant());
        }
    }

    // Snapshot the CURRENT config before signalling success — the QML
    // caller is about to overwrite live kcfg_* values with `toApply`,
    // so this is the user's last clean revert point. Skipping the
    // snapshot on validation failure keeps the file system uncluttered
    // when the import was never going to apply.
    const QString backupName = u"iframe-plasma-backup-%1.json"_s.arg(
        QDateTime::currentDateTimeUtc().toString(u"yyyyMMdd-HHmmss"_s));
    const QString backupPath = configHome() + u"/"_s + backupName;
    QDir().mkpath(configHome());
    const QString snapErr = exportToFile(backupPath, currentConfig);
    if (snapErr.isEmpty()) {
        m_lastBackupPath = backupPath;
        // A non-fatal perm-restriction warning from the snapshot write
        // (e.g. XDG_CONFIG_HOME on a FAT mount) flows through `warning`
        // rather than `error` so the QML side renders it as an info
        // banner alongside the success message instead of an Error.
        if (!m_lastExportWarning.isEmpty()) {
            result[u"warning"_s] = QString(u"Pre-import backup written but with caveat: "_s
                                           + m_lastExportWarning);
        }
    } else {
        // Don't fail the import for a snapshot write error — surface it
        // through `error` but still return ok=true with `config` so the
        // user can choose to proceed. Clear m_lastBackupPath so the QML
        // caller's "Previous configuration saved to <path>" hint doesn't
        // point at a STALE backup from a prior successful import — the
        // user would otherwise be invited to revert from the wrong file.
        m_lastBackupPath.clear();
        result[u"error"_s] = QString(u"Pre-import backup failed (continuing): "_s + snapErr);
    }

    result[u"ok"_s] = true;
    result[u"config"_s] = toApply;
    result[u"skipped"_s] = skipped;
    return result;
}

QString BackupBridge::lastBackupPath() const
{
    return m_lastBackupPath;
}

QString BackupBridge::lastExportWarning() const
{
    return m_lastExportWarning;
}

QString BackupBridge::suggestedExportName() const
{
    const QString today = QDateTime::currentDateTime().toString(u"yyyy-MM-dd"_s);
    return u"iframe-plasma-config-"_s + today + u".json"_s;
}

void BackupBridge::setLastExportWarningForTest(const QString &warning)
{
    m_lastExportWarning = warning;
}

void BackupBridge::setLastBackupPathForTest(const QString &path)
{
    m_lastBackupPath = path;
}
