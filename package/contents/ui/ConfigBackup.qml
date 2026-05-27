/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import io.github.v3DJG6GL.iframe 1.0 as IframePlasma

// KCM page: configuration backup / restore. Round-trips the 16 active
// kcfg entries through a versioned JSON file via the C++ BackupBridge
// singleton. Secrets in KWallet are deliberately omitted — the user
// re-enters them on the Authentication page after import.
KCM.SimpleKCM {
    id: page

    // Active schema keys — kept in sync with src/backupbridge.cpp's
    // kSchema array. The aliases give us a flat, live view of every
    // non-deprecated kcfg entry so Export can pack them into a JS
    // object and Import can write the imported values straight back.
    property alias cfg_urlsJson: _urls.text
    property alias cfg_currentTabIndex: _currentTab.value
    property alias cfg_autoCycleEnabled: _autoCycle.checked
    property alias cfg_autoCycleIntervalSec: _autoCycleSec.value
    property alias cfg_zoomFactor: _zoom.value
    property alias cfg_themeMode: _themeMode.text
    property alias cfg_showTabBar: _showTabBar.checked
    property alias cfg_compactPreviewEnabled: _compactEnabled.checked
    property alias cfg_compactPreviewShowLabel: _compactLabel.checked
    property alias cfg_compactPreviewLongAxisPx: _compactAxis.value
    property alias cfg_popupPinned: _popupPinned.checked
    property alias cfg_authProfilesJson: _authProfiles.text
    property alias cfg_userAgentOverride: _ua.text
    property alias cfg_remoteDebuggingPort: _debugPort.value
    property alias cfg_webViewFreezeDelaySec: _freeze.value
    property alias cfg_webViewDiscardDelaySec: _discard.value
    // Migration flags — not in the export schema, but exposed here so
    // an Import can force-reset them to false (so any legacy-shaped
    // payload re-triggers main.qml's one-shot migrations cleanly).
    property alias cfg_compactPreviewMigrated: _previewMigrated.checked
    property alias cfg_authProfilesPreemptMigrated: _preemptMigrated.checked

    // Off-screen scratch items that own the alias backing values. Using
    // hidden controls (rather than `property var`) lets the KCM treat
    // every key as a real two-way alias with the same change semantics
    // as the other ConfigPages.
    Item {
        visible: false
        QQC.TextField    { id: _urls }
        QQC.SpinBox      { id: _currentTab;     from: 0;     to: 9999 }
        QQC.CheckBox     { id: _autoCycle }
        QQC.SpinBox      { id: _autoCycleSec;   from: 1;     to: 86400 }
        QQC.SpinBox      { id: _zoom;           from: 25;    to: 500 }
        QQC.TextField    { id: _themeMode }
        QQC.CheckBox     { id: _showTabBar }
        QQC.CheckBox     { id: _compactEnabled }
        QQC.CheckBox     { id: _compactLabel }
        QQC.SpinBox      { id: _compactAxis;    from: 16;    to: 4000 }
        QQC.CheckBox     { id: _popupPinned }
        QQC.TextField    { id: _authProfiles }
        QQC.TextField    { id: _ua }
        QQC.SpinBox      { id: _debugPort;      from: 0;     to: 65535 }
        QQC.SpinBox      { id: _freeze;         from: 1;     to: 3600 }
        QQC.SpinBox      { id: _discard;        from: 1;     to: 86400 }
        QQC.CheckBox     { id: _previewMigrated }
        QQC.CheckBox     { id: _preemptMigrated }
    }

    // Build a flat key->value map from the current alias state. This is
    // what BackupBridge filters down to the schema whitelist on export
    // and writes back into on import.
    function _collectConfig() {
        return {
            urlsJson:                  cfg_urlsJson,
            currentTabIndex:           cfg_currentTabIndex,
            autoCycleEnabled:          cfg_autoCycleEnabled,
            autoCycleIntervalSec:      cfg_autoCycleIntervalSec,
            zoomFactor:                cfg_zoomFactor,
            themeMode:                 cfg_themeMode,
            showTabBar:                cfg_showTabBar,
            compactPreviewEnabled:     cfg_compactPreviewEnabled,
            compactPreviewShowLabel:   cfg_compactPreviewShowLabel,
            compactPreviewLongAxisPx:  cfg_compactPreviewLongAxisPx,
            popupPinned:               cfg_popupPinned,
            authProfilesJson:          cfg_authProfilesJson,
            userAgentOverride:         cfg_userAgentOverride,
            remoteDebuggingPort:       cfg_remoteDebuggingPort,
            webViewFreezeDelaySec:     cfg_webViewFreezeDelaySec,
            webViewDiscardDelaySec:    cfg_webViewDiscardDelaySec
        };
    }

    function _applyConfig(m) {
        // Assign each known key back into its alias. KCM sees the
        // property writes, marks the page dirty, and enables Apply.
        for (const k in m) {
            const cfgKey = "cfg_" + k;
            if (page.hasOwnProperty(cfgKey)) {
                page[cfgKey] = m[k];
            }
        }
        // Reset migration flags so any legacy-shaped payload re-runs
        // main.qml's one-shot migrations on next widget load.
        page.cfg_compactPreviewMigrated = false;
        page.cfg_authProfilesPreemptMigrated = false;
    }

    FileDialog {
        id: exportDialog
        title: i18n("Save configuration backup")
        fileMode: FileDialog.SaveFile
        nameFilters: [i18n("iframe-plasma config (*.iframeplasma.json *.json)"),
                      i18n("All files (*)")]
        defaultSuffix: "json"
        currentFile: "file://" + IframePlasma.BackupBridge.suggestedExportName()
        onAccepted: {
            const path = page._urlToPath(selectedFile);
            const err = IframePlasma.BackupBridge.exportToFile(path, page._collectConfig());
            if (err === "") {
                // A non-fatal perm-restriction warning from a FAT/SMB
                // target lands in lastExportWarning() — the file IS
                // written, so the banner stays Positive but appends the
                // warning so the user can choose a safer destination.
                let msg = i18n("Configuration exported to %1.", path);
                const warn = IframePlasma.BackupBridge.lastExportWarning();
                if (warn) {
                    msg += " " + i18n("(Warning: %1)", warn);
                }
                page._showResult(msg, false);
            } else {
                page._showResult(i18n("Export failed: %1", err), true);
            }
        }
    }

    FileDialog {
        id: importDialog
        title: i18n("Open configuration backup")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("iframe-plasma config (*.iframeplasma.json *.json)"),
                      i18n("All files (*)")]
        onAccepted: {
            const path = page._urlToPath(selectedFile);
            const result = IframePlasma.BackupBridge.importFromFile(path, page._collectConfig());
            if (result.ok) {
                page._applyConfig(result.config);
                const backup = IframePlasma.BackupBridge.lastBackupPath();
                let msg = i18n("Configuration imported. Click Apply to persist.");
                if (backup) {
                    msg += " " + i18n("Previous configuration saved to %1.", backup);
                }
                if (result.skipped && result.skipped.length) {
                    msg += " " + i18np("%1 unknown key skipped.", "%1 unknown keys skipped.",
                                       result.skipped.length);
                }
                if (result.warning) {
                    // Non-fatal snapshot caveat (e.g. FAT-target perms).
                    msg += " " + i18n("(Warning: %1)", result.warning);
                }
                if (result.error) {
                    // Non-fatal: backup write failed but import proceeded.
                    msg += " " + i18n("(Warning: %1)", result.error);
                }
                page._showResult(msg, false);
            } else {
                page._showResult(i18n("Import failed: %1", result.error), true);
            }
        }
    }

    // FileDialog.selectedFile is a QUrl; String(url) emits the percent-
    // encoded form (e.g. "file:///home/foo%20bar/x.json"). Stripping the
    // scheme without decoding hands that verbatim to QFile, which then
    // fails to open any path containing a space or non-ASCII byte.
    function _urlToPath(u) {
        const s = String(u).replace(/^file:\/\//, "");
        try { return decodeURIComponent(s); } catch (e) { return s; }
    }

    function _showResult(text, isError) {
        resultMsg.text = text;
        resultMsg.type = isError ? Kirigami.MessageType.Error
                                 : Kirigami.MessageType.Positive;
        resultMsg.visible = true;
    }

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            id: resultMsg
            Layout.fillWidth: true
            visible: false
            showCloseButton: true
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            Kirigami.Heading {
                Kirigami.FormData.isSection: true
                level: 3
                text: i18n("Export")
            }
            FormHintLabel {
                text: i18n("Save the widget's current configuration to a JSON file you can copy to another computer. Passwords and tokens stored in KDE Wallet are <b>not</b> included — you'll re-enter them after importing.")
            }
            QQC.Button {
                Kirigami.FormData.label: ""
                text: i18n("Export to file…")
                icon.name: "document-save"
                onClicked: exportDialog.open()
            }

            Item { Kirigami.FormData.isSection: true }

            Kirigami.Heading {
                Kirigami.FormData.isSection: true
                level: 3
                text: i18n("Import")
            }
            FormHintLabel {
                text: i18n("Replace the current configuration with one from a file. A snapshot of the present configuration is automatically saved to <code>$XDG_CONFIG_HOME</code> first so you can revert. Auth credentials are not restored — re-enter them on the Authentication page after Apply.")
            }
            QQC.Button {
                Kirigami.FormData.label: ""
                text: i18n("Import from file…")
                icon.name: "document-open"
                onClicked: importDialog.open()
            }
        }
    }
}
