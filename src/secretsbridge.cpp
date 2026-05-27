/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
#include "secretsbridge.h"

#include "iwallet.h"

#include <KWallet>
#include <QDebug>

namespace {

// Production adapter wrapping the real KWallet::Wallet. Defined in the
// translation unit so the only thing exposed to tests is the IWallet
// interface — fakewallet doesn't link KWallet.
class KWalletAdapter final : public IWallet
{
public:
    ~KWalletAdapter() override
    {
        if (m_wallet) {
            m_wallet->deleteLater();
            m_wallet = nullptr;
        }
    }

    bool isEnabled() const override { return KWallet::Wallet::isEnabled(); }

    bool open() override
    {
        // Synchronous open — kwallet prompts the user once if needed; subsequent calls reuse.
        m_wallet = KWallet::Wallet::openWallet(
            KWallet::Wallet::NetworkWallet(), 0, KWallet::Wallet::Synchronous);
        return m_wallet && m_wallet->isOpen();
    }

    bool isOpen() const override { return m_wallet && m_wallet->isOpen(); }

    QString currentFolder() const override
    {
        return m_wallet ? m_wallet->currentFolder() : QString();
    }
    bool setFolder(const QString &f) override { return m_wallet && m_wallet->setFolder(f); }
    bool hasFolder(const QString &f) override { return m_wallet && m_wallet->hasFolder(f); }
    bool createFolder(const QString &f) override { return m_wallet && m_wallet->createFolder(f); }

    bool hasEntry(const QString &key) override
    {
        return m_wallet && m_wallet->hasEntry(key);
    }
    int readPassword(const QString &key, QString &value) override
    {
        return m_wallet ? m_wallet->readPassword(key, value) : -1;
    }
    int readMap(const QString &key, QMap<QString, QString> &value) override
    {
        return m_wallet ? m_wallet->readMap(key, value) : -1;
    }
    int writeMap(const QString &key, const QMap<QString, QString> &value) override
    {
        return m_wallet ? m_wallet->writeMap(key, value) : -1;
    }
    int removeEntry(const QString &key) override
    {
        return m_wallet ? m_wallet->removeEntry(key) : -1;
    }

private:
    KWallet::Wallet *m_wallet = nullptr;
};

} // namespace

const QString SecretsBridge::kFolder = QStringLiteral("io.github.v3DJG6GL.iframe-plasma");

SecretsBridge::SecretsBridge(QObject *parent)
    : QObject(parent)
    , m_wallet(std::make_unique<KWalletAdapter>())
{
}

SecretsBridge::SecretsBridge(std::unique_ptr<IWallet> wallet, QObject *parent)
    : QObject(parent)
    , m_wallet(std::move(wallet))
{
}

SecretsBridge::~SecretsBridge() = default;

bool SecretsBridge::ensureOpen()
{
    if (m_wallet->isOpen()) {
        // Wallet may have been used by another caller on a different folder
        // since our last call — always re-pin so the per-op guards downstream
        // can be dropped. If our folder was deleted externally (e.g. via
        // kwalletmanager) setFolder returns false; recreate it the same
        // way the cold-open branch does so reads/writes don't silently
        // target whatever folder the wallet was previously in.
        if (m_wallet->currentFolder() != kFolder && !m_wallet->setFolder(kFolder)) {
            if (!m_wallet->hasFolder(kFolder)) {
                m_wallet->createFolder(kFolder);
            }
            if (!m_wallet->setFolder(kFolder)) {
                return false;
            }
        }
        return true;
    }
    if (!m_wallet->isEnabled()) {
        Q_EMIT error(tr("KDE Wallet is not enabled."));
        return false;
    }
    if (!m_wallet->open()) {
        Q_EMIT error(tr("Failed to open the network wallet."));
        return false;
    }
    if (!m_wallet->hasFolder(kFolder)) {
        m_wallet->createFolder(kFolder);
    }
    m_wallet->setFolder(kFolder);
    return true;
}

QString SecretsBridge::get(const QString &key)
{
    if (key.isEmpty() || !ensureOpen()) {
        return QString();
    }
    QString value;
    if (m_wallet->readPassword(key, value) == 0) {
        return value;
    }
    return QString();
}

bool SecretsBridge::has(const QString &key)
{
    if (key.isEmpty() || !ensureOpen()) {
        return false;
    }
    return m_wallet->hasEntry(key);
}

QVariantMap SecretsBridge::getMap(const QString &key)
{
    if (key.isEmpty() || !ensureOpen()) {
        return {};
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
    if (key.isEmpty() || !ensureOpen()) {
        return false;
    }
    QMap<QString, QString> raw;
    for (auto it = fields.constBegin(); it != fields.constEnd(); ++it) {
        raw.insert(it.key(), it.value().toString());
    }
    if (m_wallet->writeMap(key, raw) != 0) {
        return false;
    }
    Q_EMIT secretsChanged();
    return true;
}

bool SecretsBridge::removeKey(const QString &key)
{
    if (key.isEmpty() || !ensureOpen()) {
        return false;
    }
    if (m_wallet->removeEntry(key) != 0) {
        return false;
    }
    Q_EMIT secretsChanged();
    return true;
}

bool SecretsBridge::isWalletReady() const
{
    return m_wallet && m_wallet->isOpen();
}
