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
    property alias cfg_userAgentOverride: uaField.text
    property alias cfg_remoteDebuggingPort: debugPortBox.value
    property alias cfg_webViewFreezeDelaySec: freezeBox.value
    property alias cfg_webViewDiscardDelaySec: discardBox.value

    Kirigami.FormLayout {
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
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 1
            text: i18n("Set a non-zero port (e.g. 9222) and start plasmashell with QTWEBENGINE_REMOTE_DEBUGGING=&lt;port&gt;. Then open http://localhost:&lt;port&gt; in any browser to inspect the embedded view.")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC.SpinBox {
            id: freezeBox
            Kirigami.FormData.label: i18n("Freeze hidden views after:")
            from: 1; to: 3600; value: 30
            textFromValue: (v) => i18np("%1 second", "%1 seconds", v)
            NoWheel {}
        }
        QQC.SpinBox {
            id: discardBox
            Kirigami.FormData.label: i18n("Discard frozen views after:")
            from: 1; to: 86400; value: 600
            textFromValue: (v) => i18np("%1 second", "%1 seconds", v)
            NoWheel {}
        }
        QQC.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 1
            text: i18n("A tab you are not looking at is frozen (its JavaScript and auto-refresh suspended) after the first delay, then discarded (its renderer process shut down to reclaim memory; it reloads when shown again) after the second. Set the discard delay very high to only ever freeze.")
        }
    }
}
