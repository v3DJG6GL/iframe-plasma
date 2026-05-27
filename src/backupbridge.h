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
    // aliases) to `path` as a versioned JSON document. Deprecated and
    // migration-flag keys are stripped here as defence-in-depth even if
    // the QML caller passes them in. Returns "" on success or a human-
    // readable error message on failure (file already gone, permissions,
    // disk full, …).
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

    // Default filename for the save dialog (e.g.
    // "iframe-plasma-config-2026-05-27.json"). Date-stamped so multiple
    // exports on the same day still differ once the user adds a suffix.
    Q_INVOKABLE QString suggestedExportName() const;

private:
    QString m_lastBackupPath;
};
