/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <memory>
#include <qqmlregistration.h>

class IWallet;

class SecretsBridge : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    // Production: constructs a KWalletAdapter internally.
    explicit SecretsBridge(QObject *parent = nullptr);
    // Tests: inject a fake wallet (FakeWallet in tests/fixtures/fakewallet/).
    // The bridge takes ownership.
    explicit SecretsBridge(std::unique_ptr<IWallet> wallet, QObject *parent = nullptr);
    ~SecretsBridge() override;

    // Existence check for a single wallet key. Named auth profiles use it
    // (via AuthSupport.has) to show whether a secret is already stored
    // under `profile:<uuid>`.
    Q_INVOKABLE bool has(const QString &key);

    // Multi-field map entries — used by named auth profiles, where a single
    // wallet entry stores password/bearerToken/rawHeader fields together.
    // Empty map returned on miss/error.
    Q_INVOKABLE QVariantMap getMap(const QString &key);
    Q_INVOKABLE bool setMap(const QString &key, const QVariantMap &fields);
    Q_INVOKABLE bool removeKey(const QString &key);

    // Side-effect-free: did the most recent open succeed? primeAuthProfiles
    // uses this AFTER getMap to distinguish "wallet locked / disabled /
    // user-cancelled unlock" (returns false here) from "wallet open, entry
    // simply not stored" (returns true). Without this distinction every
    // failure mode logged the same generic 'no stored secret — skipping',
    // hiding the much more actionable autostart-with-locked-wallet case.
    Q_INVOKABLE bool isWalletReady() const;

Q_SIGNALS:
    void error(const QString &message);

    // Fired after a successful setMap() or removeKey(). main.qml listens
    // (via AuthSupport's mirror) so primeAuthProfiles() picks up a newly
    // entered password and registers the interceptor header. Without
    // this, re-entering a password after Backup→Import never reached
    // the interceptor unless the user also touched profile metadata
    // (which transitively retriggers primeAuthProfiles via
    // onAuthProfilesJsonChanged).
    void secretsChanged();

private:
    bool ensureOpen();

    std::unique_ptr<IWallet> m_wallet;
    static const QString kFolder;
};
