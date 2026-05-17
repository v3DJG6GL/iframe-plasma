/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <qqmlregistration.h>

namespace KWallet { class Wallet; }

class SecretsBridge : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool walletAvailable READ walletAvailable NOTIFY walletAvailableChanged)
    Q_PROPERTY(bool walletOpen READ walletOpen NOTIFY walletOpenChanged)

public:
    explicit SecretsBridge(QObject *parent = nullptr);
    ~SecretsBridge() override;

    bool walletAvailable() const;
    bool walletOpen() const;

    // Single-string entries — kept for legacy migration (basic:<host> entries).
    Q_INVOKABLE QString get(const QString &key);
    Q_INVOKABLE bool set(const QString &key, const QString &value);
    Q_INVOKABLE bool remove(const QString &key);
    Q_INVOKABLE bool has(const QString &key);

    // Multi-field map entries — used by named auth profiles, where a single
    // wallet entry stores password/bearerToken/rawHeader fields together.
    // Empty map returned on miss/error.
    Q_INVOKABLE QVariantMap getMap(const QString &key);
    Q_INVOKABLE bool setMap(const QString &key, const QVariantMap &fields);
    Q_INVOKABLE bool removeKey(const QString &key);   // alias for remove() — clearer intent

Q_SIGNALS:
    void walletAvailableChanged();
    void walletOpenChanged();
    void error(const QString &message);

private:
    bool ensureOpen();

    KWallet::Wallet *m_wallet = nullptr;
    static const QString kFolder;
};
