/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property alias cfg_privateBrowsing: privateSwitch.checked
    property alias cfg_userAgentOverride: uaField.text
    property alias cfg_remoteDebuggingPort: debugPortBox.value

    Kirigami.FormLayout {
        QQC.CheckBox {
            id: privateSwitch
            Kirigami.FormData.label: i18n("Private browsing:")
            text: i18n("Discard cookies and storage on widget close")
        }
        QQC.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Warning: breaks Authelia session persistence. Use only for one-shot pages.")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC.TextField {
            id: uaField
            Kirigami.FormData.label: i18n("User-Agent override:")
            Layout.fillWidth: true
            placeholderText: i18n("(default: QtWebEngine UA)")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC.SpinBox {
            id: debugPortBox
            Kirigami.FormData.label: i18n("Remote DevTools port:")
            from: 0; to: 65535; value: 0
            textFromValue: (v) => v === 0 ? i18n("disabled") : String(v)
            NoWheel {}
        }
        QQC.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Set a non-zero port (e.g. 9222) and start plasmashell with QTWEBENGINE_REMOTE_DEBUGGING=&lt;port&gt;. Then open http://localhost:&lt;port&gt; in any browser to inspect the embedded view.")
        }
    }
}
