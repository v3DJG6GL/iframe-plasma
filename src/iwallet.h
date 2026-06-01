/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#pragma once

#include <QMap>
#include <QString>

// Minimal interface SecretsBridge uses to talk to a wallet implementation.
// Production wraps KWallet::Wallet (KWalletAdapter in secretsbridge.cpp);
// tests/fixtures/fakewallet/ provides an in-memory FakeWallet so unit tests
// never touch the user's real KWallet or the kwalletd6 DBus service.
//
// Status codes follow KWallet's int convention (0 = success, non-zero = error)
// to keep the production adapter a straight pass-through.
class IWallet
{
public:
    virtual ~IWallet() = default;

    // True if the wallet subsystem is available on this host (kwalletd6
    // installed and enabled). Cheap to call; analogous to KWallet::Wallet::isEnabled().
    virtual bool isEnabled() const = 0;

    // Synchronously open the network wallet. Returns true if the wallet is
    // now open() == true (user accepted any unlock prompt). Idempotent.
    virtual bool open() = 0;

    virtual bool isOpen() const = 0;
    virtual QString currentFolder() const = 0;
    virtual bool setFolder(const QString &folder) = 0;
    virtual bool hasFolder(const QString &folder) = 0;
    virtual bool createFolder(const QString &folder) = 0;
    virtual bool hasEntry(const QString &key) = 0;
    virtual int readMap(const QString &key, QMap<QString, QString> &value) = 0;
    virtual int writeMap(const QString &key, const QMap<QString, QString> &value) = 0;
    virtual int removeEntry(const QString &key) = 0;
};
