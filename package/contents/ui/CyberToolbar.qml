/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Toolbar sitting above the tab strip. Surfaces:
 *   ↻ reload (split button — click for soft reload, dropdown for the menu)
 *   [200 OK · 47ms]      HTTP status + nav timing of the active tab
 *   🔒 host.example.com  TLS-and-host chip
 *
 * The widget owns no state — properties are bound from main.qml to the
 * currently-active tab; signals are emitted up to main.qml which knows the
 * concrete WebEngineView + cookie store.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import QtQuick.Effects
import org.kde.kirigami as Kirigami

Rectangle {
    id: tb

    // Inbound: bound from active tab in main.qml.
    property string host: ""
    property bool   tlsOk: false
    property int    httpStatus: 0       // 0 → unknown / not yet captured
    property int    latencyMs: 0
    property bool   loading: false
    // Active tab's current Grafana time range (e.g. "24h", "custom", or "")
    // and refresh interval (e.g. "30s" or ""). Drive the dropdown selection.
    property string timeRange: ""
    property string refreshInterval: ""

    signal reloadClicked()
    signal hardReloadClicked()
    signal clearCookiesClicked()
    signal openExternalClicked()
    // Emitted when user picks a value from one of the dropdowns. main.qml
    // routes these to the active tab's setTimeRange / setRefreshInterval.
    signal selectTimeRange(string range)        // "24h" / "" / "custom"
    signal selectRefreshInterval(string interval)  // "30s" / "off"

    implicitHeight: Theme.toolbarHeight
    color: Theme.bg

    // 1px hairline along the bottom — visually separates from CyberTabBar below
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.fgMute
        opacity: 0.6
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s2
        anchors.rightMargin: Theme.s2
        spacing: Theme.s2

        // --- Reload split button -------------------------------------------
        Row {
            spacing: 0
            Layout.alignment: Qt.AlignVCenter

            QQC.AbstractButton {
                id: reloadBtn
                width: 22; height: 20
                hoverEnabled: true
                onClicked: tb.reloadClicked()
                onPressAndHold: reloadMenu.popup()
                QQC.ToolTip.text: i18n("Reload (Ctrl+R) — long-press for more")
                QQC.ToolTip.visible: hovered
                QQC.ToolTip.delay: 600
                contentItem: Rectangle {
                    color: reloadBtn.hovered ? Theme.surfaceHi : Theme.surface
                    border.color: Theme.fgMute
                    border.width: 1
                    radius: 2
                    QQC.Label {
                        anchors.centerIn: parent
                        text: tb.loading ? "◠" : "↻"
                        color: Theme.accent
                        font.family: Theme.fontHeader
                        font.pixelSize: 13
                        font.bold: true
                        RotationAnimation on rotation {
                            running: tb.loading
                            loops: Animation.Infinite
                            from: 0; to: 360; duration: 900
                        }
                    }
                }
            }

            QQC.AbstractButton {
                id: caretBtn
                width: 14; height: 20
                hoverEnabled: true
                onClicked: reloadMenu.popup()
                contentItem: Rectangle {
                    color: caretBtn.hovered ? Theme.surfaceHi : Theme.surface
                    border.color: Theme.fgMute
                    border.width: 1
                    radius: 2
                    QQC.Label {
                        anchors.centerIn: parent
                        text: "▾"
                        color: Theme.fgDim
                        font.family: Theme.fontHeader
                        font.pixelSize: 10
                    }
                }
            }
        }

        QQC.Menu {
            id: reloadMenu
            QQC.MenuItem {
                text: i18n("Reload   (Ctrl+R)")
                icon.name: "view-refresh"
                onTriggered: tb.reloadClicked()
            }
            QQC.MenuItem {
                text: i18n("Hard reload — bypass cache   (Ctrl+Shift+R)")
                icon.name: "view-refresh-symbolic"
                onTriggered: tb.hardReloadClicked()
            }
            QQC.MenuItem {
                text: i18n("Clear HTTP cache && reload")
                icon.name: "edit-clear-history"
                onTriggered: tb.clearCookiesClicked()
            }
            QQC.MenuSeparator {}
            QQC.MenuItem {
                text: i18n("Open in default browser")
                icon.name: "internet-web-browser"
                onTriggered: tb.openExternalClicked()
            }
        }

        // --- Time-range chip dropdown ---------------------------------------
        // Styled to match the host/HTTP-status chips & the reload split-button:
        // Theme.surface bg, Theme.fgMute → Theme.accent border on hover,
        // monospace body font, "▾" caret. Clicking opens a Menu of presets.
        Rectangle {
            id: timeChip
            visible: tb.host.length > 0
            Layout.preferredHeight: Theme.chipHeight + 2
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: timeChipRow.implicitWidth + Theme.chipPadding * 2
            color: timeChipMa.containsMouse || timeMenu.opened ? Theme.surfaceHi : Theme.surface
            border.color: timeChipMa.containsMouse || timeMenu.opened ? Theme.accent : Theme.fgMute
            border.width: 1
            radius: 2
            Behavior on color       { ColorAnimation { duration: 100 } }
            Behavior on border.color { ColorAnimation { duration: 100 } }

            Row {
                id: timeChipRow
                anchors.centerIn: parent
                spacing: 4
                QQC.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⏱"
                    font.pixelSize: 9
                    color: Theme.fgDim
                }
                QQC.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tb.timeRange.length > 0 ? tb.timeRange : "—"
                    font.family: Theme.fontBody
                    font.pixelSize: 9
                    color: tb.timeRange.length > 0 ? Theme.fg : Theme.fgDim
                }
                QQC.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▾"
                    font.family: Theme.fontHeader
                    font.pixelSize: 8
                    color: Theme.fgDim
                }
            }

            MouseArea {
                id: timeChipMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: timeMenu.popup(timeChip, 0, timeChip.height)
            }

            QQC.ToolTip {
                visible: timeChipMa.containsMouse && !timeMenu.opened
                delay: 600
                text: i18n("Time range — overrides URL's from/to (session only)")
            }
        }

        QQC.Menu {
            id: timeMenu
            Instantiator {
                model: [
                    { val: "",    label: i18nc("time range: keep URL's existing from/to", "(URL default)") },
                    { val: "5m",  label: i18n("Last 5 minutes")  },
                    { val: "15m", label: i18n("Last 15 minutes") },
                    { val: "30m", label: i18n("Last 30 minutes") },
                    { val: "1h",  label: i18n("Last 1 hour")     },
                    { val: "6h",  label: i18n("Last 6 hours")    },
                    { val: "12h", label: i18n("Last 12 hours")   },
                    { val: "24h", label: i18n("Last 24 hours")   },
                    { val: "7d",  label: i18n("Last 7 days")     },
                    { val: "30d", label: i18n("Last 30 days")    }
                ]
                delegate: QQC.MenuItem {
                    text: modelData.label
                    checkable: true
                    checked: modelData.val === tb.timeRange
                    onTriggered: tb.selectTimeRange(modelData.val)
                }
                onObjectAdded:   (i, obj) => timeMenu.insertItem(i, obj)
                onObjectRemoved: (_, obj) => timeMenu.removeItem(obj)
            }
        }

        // --- Refresh-interval chip dropdown ---------------------------------
        Rectangle {
            id: refreshChip
            visible: tb.host.length > 0
            Layout.preferredHeight: Theme.chipHeight + 2
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: refreshChipRow.implicitWidth + Theme.chipPadding * 2
            color: refreshChipMa.containsMouse || refreshMenu.opened ? Theme.surfaceHi : Theme.surface
            border.color: refreshChipMa.containsMouse || refreshMenu.opened ? Theme.accent : Theme.fgMute
            border.width: 1
            radius: 2
            Behavior on color       { ColorAnimation { duration: 100 } }
            Behavior on border.color { ColorAnimation { duration: 100 } }

            Row {
                id: refreshChipRow
                anchors.centerIn: parent
                spacing: 4
                QQC.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⟳"   // distinct from the reload button's ↻
                    font.pixelSize: 10
                    color: tb.refreshInterval.length > 0 ? Theme.success : Theme.fgDim
                    // Slow pulse when auto-refresh is on — quietly nerdy live indicator
                    SequentialAnimation on opacity {
                        running: tb.refreshInterval.length > 0
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.55; to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.0; to: 0.55; duration: 1400; easing.type: Easing.InOutSine }
                    }
                }
                QQC.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tb.refreshInterval.length > 0 ? tb.refreshInterval : i18nc("refresh off", "off")
                    font.family: Theme.fontBody
                    font.pixelSize: 9
                    color: tb.refreshInterval.length > 0 ? Theme.fg : Theme.fgDim
                }
                QQC.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▾"
                    font.family: Theme.fontHeader
                    font.pixelSize: 8
                    color: Theme.fgDim
                }
            }

            MouseArea {
                id: refreshChipMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: refreshMenu.popup(refreshChip, 0, refreshChip.height)
            }

            QQC.ToolTip {
                visible: refreshChipMa.containsMouse && !refreshMenu.opened
                delay: 600
                text: i18n("Auto-refresh interval (session only)")
            }
        }

        QQC.Menu {
            id: refreshMenu
            Instantiator {
                model: [
                    { val: "",    label: i18nc("refresh off", "Off (no auto-refresh)") },
                    { val: "5s",  label: i18n("Every 5 seconds")   },
                    { val: "30s", label: i18n("Every 30 seconds")  },
                    { val: "1m",  label: i18n("Every 1 minute")    },
                    { val: "5m",  label: i18n("Every 5 minutes")   },
                    { val: "30m", label: i18n("Every 30 minutes")  }
                ]
                delegate: QQC.MenuItem {
                    text: modelData.label
                    checkable: true
                    checked: modelData.val === tb.refreshInterval
                    onTriggered: tb.selectRefreshInterval(modelData.val)
                }
                onObjectAdded:   (i, obj) => refreshMenu.insertItem(i, obj)
                onObjectRemoved: (_, obj) => refreshMenu.removeItem(obj)
            }
        }

        // --- HTTP status chip ----------------------------------------------
        Rectangle {
            visible: tb.httpStatus > 0
            Layout.preferredHeight: Theme.chipHeight
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: statusRow.implicitWidth + Theme.chipPadding * 2
            color: Theme.surface
            border.color: Theme.fgMute
            border.width: 1
            radius: 2
            Row {
                id: statusRow
                anchors.centerIn: parent
                spacing: 4
                QQC.Label {
                    text: "[" + tb.httpStatus + " " + (tb.httpStatus < 400 ? "OK" : "ERR")
                          + (tb.latencyMs > 0 ? " · " + tb.latencyMs + "ms" : "") + "]"
                    font.family: Theme.fontBody
                    font.pixelSize: 9
                    color: tb.httpStatus < 400 ? Theme.success : Theme.error
                }
            }
        }

        Item { Layout.fillWidth: true }

        // --- Hostname + TLS chip -------------------------------------------
        Rectangle {
            visible: tb.host.length > 0
            Layout.preferredHeight: Theme.chipHeight
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: hostRow.implicitWidth + Theme.chipPadding * 2
            color: Theme.surface
            border.color: Theme.fgMute
            border.width: 1
            radius: 2
            Row {
                id: hostRow
                anchors.centerIn: parent
                spacing: 4
                QQC.Label {
                    text: tb.tlsOk ? "🔒" : "⚠"
                    font.pixelSize: 9
                    color: tb.tlsOk ? Theme.success : Theme.warning
                }
                QQC.Label {
                    text: tb.host
                    font.family: Theme.fontBody
                    font.pixelSize: 9
                    color: Theme.fg
                }
            }
        }
    }
}
