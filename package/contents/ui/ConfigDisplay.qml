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
    property alias cfg_zoomFactor: zoom.value
    property alias cfg_themeMode: themeStore.value
    property alias cfg_showTabBar: tabBarSwitch.checked
    property alias cfg_compactPreviewEnabled: compactSwitch.checked
    property alias cfg_compactPreviewLongAxisPx: longAxisSpin.value
    property alias cfg_autoCycleEnabled: cycleBox.checked
    property alias cfg_autoCycleIntervalSec: cycleSpin.value

    QtObject { id: themeStore; property string value: "auto" }

    Kirigami.FormLayout {
        UnitSpinBox {
            id: zoom
            Kirigami.FormData.label: i18n("Zoom:")
            from: 25; to: 500; stepSize: 5
            value: 100
            suffix: " %"
        }
        QQC.ComboBox {
            id: themeCombo
            Kirigami.FormData.label: i18n("Theme:")
            model: [
                { value: "auto",  display: i18n("Match KDE color scheme") },
                { value: "light", display: i18n("Force light") },
                { value: "dark",  display: i18n("Force dark") }
            ]
            textRole: "display"
            valueRole: "value"
            currentIndex: model.findIndex(x => x.value === themeStore.value)
            onActivated: themeStore.value = model[currentIndex].value
            NoWheel {}
        }
        QQC.Label {
            Layout.fillWidth: true
            text: i18n("URLs may contain ${theme} as a placeholder — useful for Grafana's ?theme= parameter.")
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
        }

        Item { Kirigami.FormData.isSection: true }

        QQC.CheckBox {
            id: tabBarSwitch
            Kirigami.FormData.label: i18n("Tab bar:")
            text: i18n("Show tab bar when multiple URLs are configured")
            checked: true
        }
        FormHintLabel {
            text: i18n("Tip: drag the popup's edges to resize it. The size is remembered across sessions.")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC.CheckBox {
            id: compactSwitch
            Kirigami.FormData.label: i18n("Panel preview:")
            text: i18n("Render a live mini-preview in the Plasma panel slot")
            checked: true
        }
        UnitSpinBox {
            id: longAxisSpin
            Kirigami.FormData.label: i18n("Preview size:")
            enabled: compactSwitch.checked
            from: 16; to: 4000; stepSize: 1
            value: 160
            suffix: " px"
            QQC.ToolTip.visible: hovered
            QQC.ToolTip.delay: 600
            QQC.ToolTip.text: i18n("Long-axis size of the panel slot. Horizontal panel → slot width; vertical panel → slot height. The other axis is fixed by the Plasma panel's thickness. Type any value; the field accepts integers from 16 to 4000.")
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Rotate preview:")
            enabled: compactSwitch.checked
            QQC.CheckBox {
                id: cycleBox
                text: i18n("Cycle through tabs every")
                checked: false
            }
            UnitSpinBox {
                id: cycleSpin
                from: 5; to: 3600
                value: 30
                enabled: cycleBox.checked
                suffix: " s"
            }
        }
        FormHintLabel {
            text: i18n("Rotation only runs while the widget popup is closed — opening the popup pauses the cycle on whichever tab is currently shown. Requires at least two tabs.")
            visible: cycleBox.checked
        }
        FormHintLabel {
            text: i18n("The panel slot mirrors whichever tab is active in the popup. Per-URL settings on the URLs tab control how each tab is rendered in the slot (Grafana crop, custom CSS selector, plain text, an icon, or excluded from the slot entirely).")
        }
    }
}
