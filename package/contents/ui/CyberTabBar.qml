/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Tabs strip — Tokyo Night Storm + Hack monospace headers.
 * Inactive labels stay fully readable (the previous TabBar applied opacity to
 * the rectangle root which killed label legibility). Active tab is signalled
 * by colour + weight + an accent-glow underline.
 *
 * Per-tab live status is read from `statuses[index]`; values: "loading", "ok",
 * "err", "auth", anything-else → muted dot. The parent (main.qml) keeps that
 * array in sync from per-WebTab load events.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import QtQuick.Effects
import org.kde.kirigami as Kirigami

Rectangle {
    id: bar
    property var tabs: []
    property int currentIndex: 0
    property var statuses: []
    signal tabSelected(int index)
    signal reloadRequested(int index)

    implicitHeight: Theme.tabHeight
    color: Theme.bgAlt

    // 1px hairline under the tab strip
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.fgMute
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s2
        anchors.rightMargin: Theme.s2
        spacing: 0

        Repeater {
            model: bar.tabs
            delegate: Item {
                id: tabDel
                required property var modelData
                required property int index
                readonly property bool active: index === bar.currentIndex
                readonly property string status: (bar.statuses && bar.statuses[index]) || ""
                readonly property color statusColor: {
                    switch (status) {
                        case "loading": return Theme.warning
                        case "ok":      return Theme.success
                        case "err":     return Theme.error
                        case "auth":    return Theme.magenta
                        default:        return Theme.fgMute
                    }
                }

                Layout.fillHeight: true
                Layout.preferredWidth: contentRow.implicitWidth + Theme.s4 * 2
                Layout.minimumWidth: Kirigami.Units.gridUnit * 5

                // Hover wash
                Rectangle {
                    anchors.fill: parent
                    anchors.bottomMargin: 2
                    color: Theme.surface
                    opacity: hoverArea.containsMouse && !tabDel.active ? 0.45 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    radius: 2
                }

                Row {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: Theme.s2

                    // Status dot
                    QQC.Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "●"   // ●
                        font.family: Theme.fontHeader
                        font.pixelSize: 9
                        color: tabDel.statusColor
                        // Pulsing dot when the tab is loading
                        SequentialAnimation on opacity {
                            running: tabDel.status === "loading"
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.3; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 1.0; to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                        }
                    }

                    QQC.Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tabDel.modelData.label || tabDel.modelData.url || i18n("Tab %1", tabDel.index + 1)
                        elide: Text.ElideRight
                        font.family: Theme.fontHeader
                        font.pixelSize: 11
                        font.letterSpacing: 0.8
                        font.weight: tabDel.active ? Font.Bold : Font.Medium
                        color: tabDel.active ? Theme.fg : Theme.fgDim
                    }
                }

                // Active-tab accent underline + soft pulse glow
                Rectangle {
                    id: accentBar
                    visible: tabDel.active
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - Theme.s3 * 2
                    height: 2
                    color: Theme.accent
                    radius: 1
                }
                MultiEffect {
                    source: accentBar
                    anchors.fill: accentBar
                    visible: tabDel.active
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 16
                    brightness: 0.15
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: tabDel.active
                        NumberAnimation { from: 0.55; to: 0.95; duration: 1200; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.95; to: 0.55; duration: 1200; easing.type: Easing.InOutSine }
                    }
                }

                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.MiddleButton) {
                            bar.reloadRequested(tabDel.index);
                        } else {
                            bar.tabSelected(tabDel.index);
                        }
                    }
                }
            }
        }
        Item { Layout.fillWidth: true }
    }
}
