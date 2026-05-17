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

public:
    explicit SecretsBridge(QObject *parent = nullptr);
    ~SecretsBridge() override;

    // Single-string entries — kept for legacy migration (basic:<host> entries).
    Q_INVOKABLE QString get(const QString &key);
    Q_INVOKABLE bool has(const QString &key);

    // Multi-field map entries — used by named auth profiles, where a single
    // wallet entry stores password/bearerToken/rawHeader fields together.
    // Empty map returned on miss/error.
    Q_INVOKABLE QVariantMap getMap(const QString &key);
    Q_INVOKABLE bool setMap(const QString &key, const QVariantMap &fields);
    Q_INVOKABLE bool removeKey(const QString &key);

Q_SIGNALS:
    void error(const QString &message);

private:
    bool ensureOpen();

    KWallet::Wallet *m_wallet = nullptr;
    static const QString kFolder;
};
