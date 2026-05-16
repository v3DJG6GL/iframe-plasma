/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#include "secretsbridge.h"

#include <KWallet>
#include <QDebug>

SecretsBridge::SecretsBridge(QObject *parent)
    : QObject(parent)
{
}

SecretsBridge::~SecretsBridge()
{
    if (m_wallet) {
        m_wallet->deleteLater();
        m_wallet = nullptr;
    }
}

bool SecretsBridge::walletAvailable() const
{
    return KWallet::Wallet::isEnabled();
}

bool SecretsBridge::walletOpen() const
{
    return m_wallet && m_wallet->isOpen();
}

bool SecretsBridge::ensureOpen()
{
    if (m_wallet && m_wallet->isOpen()) {
        return true;
    }
    if (!KWallet::Wallet::isEnabled()) {
        Q_EMIT error(tr("KDE Wallet is not enabled."));
        return false;
    }
    // Synchronous open — kwallet prompts the user once if needed; subsequent calls reuse.
    m_wallet = KWallet::Wallet::openWallet(
        KWallet::Wallet::NetworkWallet(), 0, KWallet::Wallet::Synchronous);
    if (!m_wallet || !m_wallet->isOpen()) {
        Q_EMIT error(tr("Failed to open the network wallet."));
        return false;
    }
    if (!m_wallet->hasFolder(QString::fromLatin1(kFolder))) {
        m_wallet->createFolder(QString::fromLatin1(kFolder));
    }
    m_wallet->setFolder(QString::fromLatin1(kFolder));
    Q_EMIT walletOpenChanged();
    return true;
}

QString SecretsBridge::get(const QString &key)
{
    if (!ensureOpen()) {
        return QString();
    }
    if (m_wallet->currentFolder() != QString::fromLatin1(kFolder)) {
        m_wallet->setFolder(QString::fromLatin1(kFolder));
    }
    QString value;
    if (m_wallet->readPassword(key, value) == 0) {
        return value;
    }
    return QString();
}

bool SecretsBridge::set(const QString &key, const QString &value)
{
    if (!ensureOpen()) {
        return false;
    }
    if (m_wallet->currentFolder() != QString::fromLatin1(kFolder)) {
        m_wallet->setFolder(QString::fromLatin1(kFolder));
    }
    return m_wallet->writePassword(key, value) == 0;
}

bool SecretsBridge::remove(const QString &key)
{
    if (!ensureOpen()) {
        return false;
    }
    if (m_wallet->currentFolder() != QString::fromLatin1(kFolder)) {
        m_wallet->setFolder(QString::fromLatin1(kFolder));
    }
    return m_wallet->removeEntry(key) == 0;
}

bool SecretsBridge::has(const QString &key)
{
    if (!ensureOpen()) {
        return false;
    }
    if (m_wallet->currentFolder() != QString::fromLatin1(kFolder)) {
        m_wallet->setFolder(QString::fromLatin1(kFolder));
    }
    return m_wallet->hasEntry(key);
}

QVariantMap SecretsBridge::getMap(const QString &key)
{
    if (!ensureOpen()) {
        return {};
    }
    if (m_wallet->currentFolder() != QString::fromLatin1(kFolder)) {
        m_wallet->setFolder(QString::fromLatin1(kFolder));
    }
    QMap<QString, QString> raw;
    if (m_wallet->readMap(key, raw) != 0) {
        return {};
    }
    QVariantMap out;
    for (auto it = raw.constBegin(); it != raw.constEnd(); ++it) {
        out.insert(it.key(), it.value());
    }
    return out;
}

bool SecretsBridge::setMap(const QString &key, const QVariantMap &fields)
{
    if (!ensureOpen()) {
        return false;
    }
    if (m_wallet->currentFolder() != QString::fromLatin1(kFolder)) {
        m_wallet->setFolder(QString::fromLatin1(kFolder));
    }
    QMap<QString, QString> raw;
    for (auto it = fields.constBegin(); it != fields.constEnd(); ++it) {
        raw.insert(it.key(), it.value().toString());
    }
    return m_wallet->writeMap(key, raw) == 0;
}

bool SecretsBridge::removeKey(const QString &key)
{
    return remove(key);
}
