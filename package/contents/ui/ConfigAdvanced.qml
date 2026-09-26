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
    property alias cfg_popupDiscardDelaySec: popupDiscardBox.value
    property alias cfg_webViewDiscardDelaySec: thumbDiscardBox.value
    property alias cfg_thumbnailFreezeDelaySec: thumbFreezeBox.value
    property alias cfg_thumbnailReloadAfterSec: thumbReloadBox.value
    property alias cfg_thumbnailRecycleMin: thumbRecycleBox.value
    property alias cfg_gcIntervalSec: gcBox.value

    Kirigami.FormLayout {
        QQC.TextField {
            id: uaField
            Kirigami.FormData.label: i18n("User-Agent override:")
            Layout.fillWidth: true
            placeholderText: i18n("(default: QtWebEngine UA)")
        }

        Item { Kirigami.FormData.isSection: true }

        UnitSpinBox {
            id: debugPortBox
            Kirigami.FormData.label: i18n("Remote DevTools port:")
            from: 0; to: 65535; value: 0
            textFormatter: (v) => v === 0 ? i18n("disabled") : String(v)
        }
        FormHintLabel {
            text: i18n("Set a non-zero port (e.g. 9222) and start plasmashell with QTWEBENGINE_REMOTE_DEBUGGING=&lt;port&gt;. Then open http://localhost:&lt;port&gt; in any browser to inspect the embedded view.")
        }
        FormHintLabel {
            text: i18n("Widget logging is quiet by default. For a detailed trace, enable the \"iframe Plasma\" categories in KDebugSettings (then restart plasmashell), or start plasmashell with QT_LOGGING_RULES=\"io.github.v3djg6gl.iframe.*.debug=true\" and read the journal with: journalctl --user -f -t plasmashell")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Popup")
        }

        UnitSpinBox {
            id: freezeBox
            Kirigami.FormData.label: i18n("Freeze hidden tabs after:")
            from: 1; to: 3600; value: 30
            textFormatter: (v) => i18np("%1 second", "%1 seconds", v)
        }
        UnitSpinBox {
            id: popupDiscardBox
            Kirigami.FormData.label: i18n("Discard frozen tabs after:")
            from: 60; to: 86400; value: 900
            textFormatter: (v) => i18np("%1 second", "%1 seconds", v)
        }
        FormHintLabel {
            text: i18n("A tab you are not looking at is frozen (its JavaScript and auto-refresh suspended) after the first delay, then discarded (its renderer process shut down to reclaim memory; it reloads when shown again) after the second. A tab is only loaded the first time you open it. The popup stays in memory after closing, so the discard delay bounds how long closed tabs hold memory.")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Panel thumbnail")
        }

        UnitSpinBox {
            id: thumbFreezeBox
            Kirigami.FormData.label: i18n("Freeze hidden thumbnails after:")
            from: 1; to: 3600; value: 5
            textFormatter: (v) => i18np("%1 second", "%1 seconds", v)
        }
        UnitSpinBox {
            id: thumbDiscardBox
            Kirigami.FormData.label: i18n("Discard frozen thumbnails after:")
            from: 1; to: 86400; value: 600
            textFormatter: (v) => i18np("%1 second", "%1 seconds", v)
        }
        UnitSpinBox {
            id: thumbReloadBox
            Kirigami.FormData.label: i18n("Reload on return if frozen for:")
            from: 0; to: 86400; value: 0
            textFormatter: (v) => v === 0 ? i18n("never") : i18np("%1 second", "%1 seconds", v)
        }
        UnitSpinBox {
            id: thumbRecycleBox
            Kirigami.FormData.label: i18n("Recycle renderers after:")
            from: 0; to: 1440; value: 120
            textFormatter: (v) => v === 0 ? i18n("never") : i18np("%1 minute", "%1 minutes", v)
        }
        FormHintLabel {
            text: i18n("With the auto-cycle, each thumbnail is frozen shortly after it rotates out and resumes where it left off when it comes back; Grafana refreshes itself when shown. Keep the freeze delay below the auto-cycle interval, or thumbnails never freeze. Set a reload time only for pages that do not refresh on their own. A thumbnail that failed to load always reloads. Recycling restarts a thumbnail's renderer process once it is that old, the next time it rotates out, which caps memory that a long-running page accumulates.")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Memory")
        }

        UnitSpinBox {
            id: gcBox
            Kirigami.FormData.label: i18n("Force garbage collection every:")
            from: 0; to: 300; value: 20
            textFormatter: (v) => v === 0 ? i18n("disabled") : i18np("%1 second", "%1 seconds", v)
        }
        FormHintLabel {
            text: i18n("Works around a Qt WebEngine 6.10 bug that makes constantly updating pages (such as live Grafana panels) grow toward 2 GB each. Only takes effect when plasmashell is started with QTWEBENGINE_CHROMIUM_FLAGS=\"--js-flags=--expose-gc\"; see docs/PERFORMANCE.md. Applies to pages loaded after the change.")
        }
    }
}
