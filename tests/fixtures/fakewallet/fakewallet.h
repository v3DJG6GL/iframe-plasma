/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * In-memory IWallet for SecretsBridge unit tests. Designed to be drop-in
 * compatible with the production KWalletAdapter, with extra knobs to
 * simulate failure modes that the real wallet would only surface under
 * specific user / kwalletd6 state (disabled wallet, locked wallet, read
 * errors, write errors).
 */
#pragma once

#include "iwallet.h"

#include <QHash>
#include <QMap>
#include <QSet>
#include <QString>

class FakeWallet final : public IWallet
{
public:
    bool isEnabled() const override { return m_enabled; }
    bool open() override
    {
        if (!m_enabled || m_openWillFail) {
            return false;
        }
        m_open = true;
        return true;
    }
    bool isOpen() const override { return m_open; }
    QString currentFolder() const override { return m_folder; }
    bool setFolder(const QString &f) override
    {
        if (!m_folders.contains(f)) {
            return false;
        }
        m_folder = f;
        return true;
    }
    bool hasFolder(const QString &f) override { return m_folders.contains(f); }
    bool createFolder(const QString &f) override
    {
        m_folders.insert(f);
        return true;
    }
    bool hasEntry(const QString &key) override
    {
        return m_passwords.contains(qual(key)) || m_maps.contains(qual(key));
    }
    int readMap(const QString &key, QMap<QString, QString> &value) override
    {
        if (m_readWillFail) {
            return 1;
        }
        const auto it = m_maps.constFind(qual(key));
        if (it == m_maps.cend()) {
            value.clear();
            return 1;
        }
        value = *it;
        return 0;
    }
    int writeMap(const QString &key, const QMap<QString, QString> &value) override
    {
        if (m_writeWillFail) {
            return 1;
        }
        m_maps.insert(qual(key), value);
        return 0;
    }
    int removeEntry(const QString &key) override
    {
        if (m_writeWillFail) {
            return 1;
        }
        const auto k = qual(key);
        bool removed = m_passwords.remove(k) > 0;
        removed = m_maps.remove(k) > 0 || removed;
        return removed ? 0 : 1;
    }

    // Test-only knobs ------------------------------------------------------
    void setEnabled(bool e) { m_enabled = e; }
    void setOpenWillFail(bool b) { m_openWillFail = b; }
    void setReadWillFail(bool b) { m_readWillFail = b; }
    void setWriteWillFail(bool b) { m_writeWillFail = b; }
    void closeForTest() { m_open = false; }
    // Seed entries directly (bypasses ensureOpen).
    void seedPassword(const QString &folder, const QString &key, const QString &v)
    {
        m_folders.insert(folder);
        m_passwords.insert(folder + QLatin1Char('/') + key, v);
    }
    void seedMap(const QString &folder, const QString &key,
                 const QMap<QString, QString> &v)
    {
        m_folders.insert(folder);
        m_maps.insert(folder + QLatin1Char('/') + key, v);
    }
    bool hasFolderForTest(const QString &f) const { return m_folders.contains(f); }
    int totalEntries() const { return m_passwords.size() + m_maps.size(); }
    // Simulate out-of-band folder deletion (kwalletmanager removing the
    // folder while the SecretsBridge instance still has the wallet open).
    // setFolder(f) will now return false until createFolder(f) is called
    // — exercising the warm-path recovery branch in
    // SecretsBridge::ensureOpen.
    void removeFolderForTest(const QString &f) { m_folders.remove(f); }

private:
    QString qual(const QString &key) const { return m_folder + QLatin1Char('/') + key; }

    bool m_enabled = true;
    bool m_open = false;
    bool m_openWillFail = false;
    bool m_readWillFail = false;
    bool m_writeWillFail = false;
    QString m_folder;
    QSet<QString> m_folders;
    QHash<QString, QString> m_passwords;          // folder/key -> password
    QHash<QString, QMap<QString, QString>> m_maps; // folder/key -> field map
};
