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
    property alias cfg_preferredWidth: widthBox.value
    property alias cfg_preferredHeight: heightBox.value
    property alias cfg_showTabBar: tabBarSwitch.checked
    property alias cfg_compactPreviewEnabled: compactSwitch.checked
    property alias cfg_compactPreviewMode: modeStore.value
    property alias cfg_compactPreviewTabIndex: compactStore.tabIndex
    property alias cfg_compactPreviewLongAxisPx: longAxisSpin.value
    property alias cfg_compactPreviewShowLabel: showLabelSwitch.checked
    property alias cfg_autoCycleEnabled: cycleBox.checked
    property alias cfg_autoCycleIntervalSec: cycleSpin.value

    QtObject { id: themeStore;    property string value: "auto" }
    QtObject { id: modeStore;     property string value: "auto" }  // "auto" | "fixed"
    QtObject { id: compactStore;  property int    tabIndex: 0 }

    // Parsed URL list — used to populate the "show preview from" combo
    property var urlList: {
        try {
            const j = Plasmoid.configuration ? Plasmoid.configuration.urlsJson : "[]";
            const arr = JSON.parse(j || "[]");
            return Array.isArray(arr) ? arr : [];
        } catch (e) { return []; }
    }

    Kirigami.FormLayout {
        QQC.SpinBox {
            id: zoom
            Kirigami.FormData.label: i18n("Zoom:")
            from: 25; to: 500; stepSize: 5
            value: 100
            textFromValue: (v) => v + " %"
            NoWheel {}
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

        QQC.SpinBox {
            id: widthBox
            Kirigami.FormData.label: i18n("Preferred width:")
            from: 200; to: 4000; stepSize: 50; value: 800
            editable: true
            textFromValue: (v) => v + " px"
            valueFromText: (text) => {
                const n = parseInt(String(text).replace(/[^0-9-]/g, ''), 10);
                return isNaN(n) ? value : Math.max(from, Math.min(to, n));
            }
            NoWheel {}
        }
        QQC.SpinBox {
            id: heightBox
            Kirigami.FormData.label: i18n("Preferred height:")
            from: 150; to: 4000; stepSize: 50; value: 500
            editable: true
            textFromValue: (v) => v + " px"
            valueFromText: (text) => {
                const n = parseInt(String(text).replace(/[^0-9-]/g, ''), 10);
                return isNaN(n) ? value : Math.max(from, Math.min(to, n));
            }
            NoWheel {}
        }
        QQC.CheckBox {
            id: tabBarSwitch
            Kirigami.FormData.label: i18n("Tab bar:")
            text: i18n("Show tab bar when multiple URLs are configured")
            checked: true
        }

        Item { Kirigami.FormData.isSection: true }

        QQC.CheckBox {
            id: compactSwitch
            Kirigami.FormData.label: i18n("Panel preview:")
            text: i18n("Render a live mini-preview in the Plasma panel slot")
            checked: true
        }
        QQC.ComboBox {
            id: compactTabCombo
            Kirigami.FormData.label: i18n("Preview source:")
            enabled: compactSwitch.checked
            // Item 0 is the auto-follow sentinel; items 1..N are the configured URLs.
            // Storing the mode in a separate kcfg key (compactPreviewMode) keeps
            // compactPreviewTabIndex usable as a simple int when mode=fixed.
            readonly property var rows: {
                const base = [{ id: "__auto__",
                                display: i18n("Active popup tab (auto)") }];
                for (let i = 0; i < urlList.length; i++) {
                    const u = urlList[i];
                    base.push({
                        id: String(i),
                        display: (u && u.label && u.label.length > 0)
                            ? u.label
                            : ((u && u.url) ? u.url : i18n("Tab %1", i + 1))
                    });
                }
                return base;
            }
            model: rows
            textRole: "display"
            valueRole: "id"
            currentIndex: {
                if (modeStore.value === "auto") return 0;
                const idx = compactStore.tabIndex + 1;  // shift to 1-based
                return Math.max(1, Math.min(rows.length - 1, idx));
            }
            // Arrow form: avoids the `currentIndex` shadowing / binding-fight
            // bug we hit with the previous `onActivated: compactStore.tabIndex = currentIndex`.
            // `idx` is the freshly-clicked row index from the signal.
            onActivated: idx => {
                if (idx === 0) {
                    modeStore.value = "auto";
                } else {
                    modeStore.value = "fixed";
                    compactStore.tabIndex = idx - 1;  // shift back to 0-based
                }
            }
            displayText: rows[currentIndex] ? rows[currentIndex].display : ""
            NoWheel {}
        }
        QQC.SpinBox {
            id: longAxisSpin
            Kirigami.FormData.label: i18n("Preview size:")
            enabled: compactSwitch.checked
            // Wider range + step=1 + custom value parser so users can type
            // ANY integer (e.g. 250) directly. Previously stepSize=8 limited
            // valid values to multiples of 8, AND the default valueFromText
            // (Number.fromLocaleString) couldn't parse "200 px" so SpinBox
            // snapped to the min (32) for any non-numeric input.
            from: 16; to: 4000; stepSize: 1
            value: 160
            editable: true
            textFromValue: (v) => v + " px"
            valueFromText: (text) => {
                const n = parseInt(String(text).replace(/[^0-9-]/g, ''), 10);
                return isNaN(n) ? value : Math.max(from, Math.min(to, n));
            }
            QQC.ToolTip.visible: hovered
            QQC.ToolTip.delay: 600
            QQC.ToolTip.text: i18n("Long-axis size of the panel slot. Horizontal panel → slot width; vertical panel → slot height. The other axis is fixed by the Plasma panel's thickness. Type any value; the field accepts integers from 16 to 4000.")
            NoWheel {}
        }
        QQC.CheckBox {
            id: showLabelSwitch
            Kirigami.FormData.label: i18n("Show URL label:")
            text: i18n("Overlay the tab's label on the panel-slot thumbnail")
            enabled: compactSwitch.checked
            QQC.ToolTip.visible: hovered
            QQC.ToolTip.delay: 600
            QQC.ToolTip.text: i18n("When enabled, a small semi-transparent bar in the top-left of the thumbnail shows the URL's label (only if the label field is non-empty on the URLs tab).")
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Rotate preview:")
            enabled: compactSwitch.checked
            QQC.CheckBox {
                id: cycleBox
                text: i18n("Cycle through tabs every")
                checked: false
            }
            QQC.SpinBox {
                id: cycleSpin
                from: 5; to: 3600
                value: 30
                enabled: cycleBox.checked
                textFromValue: (v) => v + " s"
                NoWheel {}
            }
        }
        QQC.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            text: i18n("Rotation only runs while the widget popup is closed — opening the popup pauses the cycle on whichever tab is currently shown. Requires at least two tabs.")
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 1
            visible: cycleBox.checked
        }
        QQC.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            text: i18n("The panel slot renders a live mini-view of the selected tab. Per-tab `Panel-slot CSS selector` (URLs tab) crops the thumbnail to just one element — pick `canvas` for the chart pixels, `.u-wrap` for chart + axes. Note: `.u-over` is uPlot's transparent overlay layer — picking it shows nothing.")
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 1
        }
    }
}
