/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Richer replacement for the bare org.kde.iconthemes.IconDialog. Three
 * sources in one tabbed dialog:
 *
 *   Theme    — opens KDE's own icon picker (whichever theme is active).
 *              Stores the bare theme name (e.g. "applications-internet").
 *   Bundled  — grid of monitoring-flavoured Phosphor SVGs shipped under
 *              package/contents/icons/bundled/. Stores "bundled:<name>".
 *   File     — any SVG/PNG on disk via FileDialog. Stores "file:///...".
 *
 * Output: emits `iconNameChanged(string)` (matches the original
 * KIconThemes.IconDialog contract; call sites swap with no behaviour churn).
 * Render-time resolution of the three prefixes lives in main.qml's
 * `resolveIconSource` so callers don't need to dispatch themselves.
 */
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes

Kirigami.Dialog {
    id: dialog

    // Matches the existing KIconThemes.IconDialog signal so call sites can
    // be swapped with a one-line `iconDialog → iconPicker` rename.
    signal iconNameChanged(string iconName)

    title: i18n("Pick an icon")
    preferredWidth: Kirigami.Units.gridUnit * 32
    preferredHeight: Kirigami.Units.gridUnit * 22
    standardButtons: Kirigami.Dialog.Cancel

    // Hand-picked monitoring/dashboard set from Phosphor Icons (MIT). One
    // file per name under package/contents/icons/bundled/<name>.svg.
    readonly property var bundledIcons: [
        "chart-line", "chart-bar", "chart-pie", "chart-donut",
        "gauge", "speedometer", "pulse", "wave-sine", "heartbeat",
        "database", "hard-drive", "hard-drives", "cpu", "desktop-tower", "monitor",
        "network", "wifi-high", "cloud", "cloud-arrow-up", "globe-hemisphere-west",
        "lock", "shield-check",
        "warning", "warning-octagon", "bell", "bell-ringing", "siren",
        "check-circle", "x-circle", "info"
    ]

    function _emit(iconName) {
        dialog.iconNameChanged(iconName);
        dialog.close();
    }

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        QQC.TabBar {
            id: tabBar
            Layout.fillWidth: true
            QQC.TabButton { text: i18n("Theme icons") }
            QQC.TabButton { text: i18n("Bundled") }
            QQC.TabButton { text: i18n("From file…") }
        }

        StackLayout {
            id: pages
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // -------- Theme tab --------
            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing
                QQC.Label {
                    Layout.fillWidth: true
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 26
                    text: i18n("Browse the active KDE icon theme (currently respects your System Settings → Icons choice). Tip: install <i>papirus-icon-theme</i> for ~10k extra icons including brand glyphs.")
                    wrapMode: Text.WordWrap
                    color: Kirigami.Theme.disabledTextColor
                }
                QQC.Button {
                    text: i18n("Open theme picker…")
                    icon.name: "preferences-desktop-icons"
                    onClicked: themePicker.open()
                }
                Item { Layout.fillHeight: true }   // pin content top
            }

            // -------- Bundled tab --------
            QQC.ScrollView {
                clip: true
                GridView {
                    id: bundledGrid
                    model: dialog.bundledIcons
                    cellWidth: Kirigami.Units.gridUnit * 6
                    cellHeight: Kirigami.Units.gridUnit * 6
                    delegate: ColumnLayout {
                        width: bundledGrid.cellWidth
                        height: bundledGrid.cellHeight
                        spacing: 2
                        required property string modelData
                        Kirigami.Icon {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Kirigami.Units.iconSizes.large
                            Layout.preferredHeight: Kirigami.Units.iconSizes.large
                            source: Qt.resolvedUrl("../icons/bundled/" + parent.modelData + ".svg")
                            // Bundled Phosphor SVGs use fill="currentColor" which
                            // QSvgRenderer resolves to black (no CSS context). The
                            // `color:` tint only fires when isMask:true triggers
                            // Kirigami's QPainter::CompositionMode_SourceIn pass.
                            // Bundled-only context here — unconditional isMask.
                            isMask: true
                            color: Kirigami.Theme.textColor
                        }
                        QQC.Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: parent.modelData
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 2
                            color: Kirigami.Theme.disabledTextColor
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dialog._emit("bundled:" + parent.modelData)
                        }
                    }
                }
            }

            // -------- File tab --------
            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing
                QQC.Label {
                    Layout.fillWidth: true
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 26
                    text: i18n("Pick any SVG or PNG from your filesystem. The absolute path is stored; if you move the file the icon will fall back to a placeholder. For dark-mode adaptive icons, prefer SVGs that use <tt>currentColor</tt>.")
                    wrapMode: Text.WordWrap
                    color: Kirigami.Theme.disabledTextColor
                }
                QQC.Button {
                    text: i18n("Choose file…")
                    icon.name: "document-open"
                    onClicked: fileDialog.open()
                }
                Item { Layout.fillHeight: true }
            }
        }
    }

    // Wrapped KDE picker — instantiated inside the dialog so its signal
    // can be forwarded as our own iconNameChanged. Stores the bare theme
    // name with no prefix.
    KIconThemes.IconDialog {
        id: themePicker
        onIconNameChanged: (picked) => {
            if (picked && picked.length > 0) dialog._emit(picked);
        }
    }

    FileDialog {
        id: fileDialog
        title: i18n("Choose an icon file")
        nameFilters: [
            i18n("Images") + " (*.svg *.svgz *.png)",
            i18n("All files") + " (*)"
        ]
        onAccepted: dialog._emit(String(selectedFile))
    }
}
