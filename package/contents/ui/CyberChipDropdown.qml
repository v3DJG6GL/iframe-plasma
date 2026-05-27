/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Compact toolbar chip with [icon, value/empty-text, ▾ caret] and a hover
 * affordance that opens an externally-provided CyberDropdown.  Used by the
 * time-range and refresh-interval chips in CyberToolbar — both share the
 * same Rectangle scaffold (Theme.surface bg, Theme.fgMute→Theme.accent
 * border on hover/open, monospace body font).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC

Rectangle {
    id: chip

    // Required: the icon char (e.g. "⏱" / "⟳"), the current value (empty
    // string = "off / default"), and the CyberDropdown to toggle.
    property string icon: ""
    property int    iconPixelSize: 9
    property color  iconColor: Theme.fgDim
    property string value: ""
    property string emptyText: "—"
    property string tooltipText: ""
    property QtObject menu: null
    // Slow opacity pulse on the icon — refresh-chip uses this as a quiet
    // "live" indicator when auto-refresh is on.
    property bool pulseEnabled: false
    // True while the full popup representation is on screen. The pulse
    // animation gates on this so it doesn't keep the QtQuick animation
    // timer ticking when the full rep is hidden (panel-mode popup
    // collapsed, OR desktop-widget mode where root.expanded stays false
    // but the full rep is rendered continuously — main.qml's
    // fullRepVisible is the only correct source). Forwarded from
    // CyberToolbar.fullRepVisible.
    property bool fullRepVisible: false

    Layout.preferredHeight: Theme.chipHeight + 2
    Layout.alignment: Qt.AlignVCenter
    // Never let a cramped toolbar squeeze this interactive chip below its
    // content — RowLayout would otherwise shrink it toward 0 and the
    // centered Row would overflow / overlap its neighbours.
    Layout.minimumWidth: implicitWidth
    implicitWidth: row.implicitWidth + Theme.chipPadding * 2
    color: ma.containsMouse || (menu && menu.opened) ? Theme.surfaceHi : Theme.surface
    border.color: ma.containsMouse || (menu && menu.opened) ? Theme.accent : Theme.fgMute
    border.width: 1
    radius: 2
    Behavior on color       { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        QQC.Label {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.icon
            font.pixelSize: chip.iconPixelSize
            color: chip.iconColor
            SequentialAnimation on opacity {
                running: chip.pulseEnabled && chip.fullRepVisible
                loops: Animation.Infinite
                NumberAnimation { from: 0.55; to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.0; to: 0.55; duration: 1400; easing.type: Easing.InOutSine }
            }
        }
        QQC.Label {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.value.length > 0 ? chip.value : chip.emptyText
            font.family: Theme.fontBody
            font.pixelSize: 9
            color: chip.value.length > 0 ? Theme.fg : Theme.fgDim
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
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (!chip.menu) return;
            if (chip.menu.opened) chip.menu.close();
            else chip.menu.open();
        }
    }

    QQC.ToolTip {
        visible: ma.containsMouse && chip.menu && !chip.menu.opened
        delay: 600
        text: chip.tooltipText
    }
}
