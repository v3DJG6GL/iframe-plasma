/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <qqmlregistration.h>

// QML-exposed helper for the Backup KCM page. Round-trips the applet's
// non-deprecated configuration through a versioned JSON file so a user
// can move tabs/profiles/display settings between machines (or, in our
// own case, across the plugin-ID rename in Phase 4). Secrets in KWallet
// are deliberately omitted — the user re-enters them after import.
class BackupBridge : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit BackupBridge(QObject *parent = nullptr);

    // Write `config` (a flat key->value map collected from kcfg_*
    // aliases) to `path` as a versioned JSON document. Only keys in the
    // export schema are written; any other key the QML caller passes is
    // dropped (allow-list, as defence-in-depth). Returns "" on success or
    // a human-readable error message on failure (file already gone,
    // permissions, disk full, …).
    Q_INVOKABLE QString exportToFile(const QString &path,
                                     const QVariantMap &config);

    // Read `path`, validate the envelope, snapshot `currentConfig` to a
    // timestamped file in XDG_CONFIG_HOME (only on validation success),
    // and return the to-be-applied map for the QML caller to write
    // through kcfg_* aliases.
    //
    // Result keys:
    //   ok       : bool — true iff the import file was valid
    //   error    : QString — empty on success, message otherwise
    //   config   : QVariantMap — flat key->value, schema-filtered
    //   skipped  : QStringList — keys present in the file but not in
    //              the current schema (forward-compat reporting)
    //
    // After ok==true, lastBackupPath() returns the location of the
    // pre-import snapshot, suitable for showing in the UI.
    Q_INVOKABLE QVariantMap importFromFile(const QString &path,
                                           const QVariantMap &currentConfig);

    Q_INVOKABLE QString lastBackupPath() const;

    // The backup schema's kcfg keys, in main.xml order. Exposed so a
    // regression test can assert this set equals main.xml's entry set
    // minus the documented exclusions (authProfilesSecretsSerial) — the
    // guard that keeps kSchema from silently drifting away from main.xml.
    // Returns raw key strings only (no i18n), so it is safe on a
    // QML_SINGLETON despite the KCM engine's missing KLocalizedContext.
    Q_INVOKABLE QStringList schemaKeys() const;

    // Set by the most recent exportToFile() call when the write itself
    // succeeded but a non-fatal post-condition didn't — currently only
    // setPermissions() returning false on FAT/exFAT/SMB filesystems that
    // don't honour POSIX perms. Empty string means "clean success".
    // Callers should check this AFTER exportToFile() returns "", not
    // instead of the return value.
    Q_INVOKABLE QString lastExportWarning() const;

    // Default filename for the save dialog (e.g.
    // "iframe-plasma-config-2026-05-27.json"). Date-stamped so multiple
    // exports on the same day still differ once the user adds a suffix.
    Q_INVOKABLE QString suggestedExportName() const;

    // Test-only seeder for m_lastExportWarning. The setPermissions
    // failure that legitimately populates this in production only
    // triggers on FAT/exFAT/SMB targets and can't be reproduced on a
    // tmpfs; this hook lets us verify that exportToFile()'s reset at
    // the top of each call actually clears a prior warning so a stale
    // FAT-target message doesn't leak into a later clean ext4 export.
    void setLastExportWarningForTest(const QString &warning);

    // Test-only seeder for m_lastBackupPath. Lets a regression test
    // seed a "prior successful import" path, drive an import whose
    // snapshot write fails, and assert importFromFile()'s clear() on
    // the snapshot-failure branch fires — otherwise the QML caller's
    // "Previous configuration saved to %1" hint would invite the
    // operator to revert from a STALE backup. Parallels the
    // setLastExportWarningForTest hook above.
    void setLastBackupPathForTest(const QString &path);

private:
    QString m_lastBackupPath;
    QString m_lastExportWarning;
};
