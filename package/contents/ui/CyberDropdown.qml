/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Cyberpunk-style single-select dropdown.
 *
 * Replaces QQC.Menu + checkable MenuItem, which had two problems:
 *   1) Bug: a `checkable` MenuItem becomes user-toggleable, so the
 *      `checked: val === currentValue` binding broke after the first
 *      click — multiple rows could appear "checked" at once.
 *   2) Style: native checkbox squares clashed with the chip aesthetic.
 *
 * Here the active row is shown via accent text colour + a 2px left
 * accent bar + a soft tinted background — no checkbox UI at all.
 */
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts

QQC.Popup {
    id: dd

    // model: [ { val: "...", label: "..." }, ... ]
    property var model: []
    property string currentValue: ""
    signal valueSelected(string value)

    padding: 1
    modal: false
    focus: true
    closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside | QQC.Popup.CloseOnReleaseOutside

    background: Rectangle {
        color: Theme.bgAlt
        border.color: Theme.accent
        border.width: 1
        radius: 2
    }

    contentItem: ColumnLayout {
        spacing: 0
        Repeater {
            model: dd.model
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool active: modelData.val === dd.currentValue
                Layout.fillWidth: true
                Layout.minimumWidth: Math.max(180, rowLabel.implicitWidth + 28)
                implicitHeight: rowLabel.implicitHeight + 10
                color: ma.containsMouse ? Theme.surfaceHi
                       : active ? Qt.rgba(0.478, 0.635, 0.969, 0.08)  // accent @ 8 %
                       : "transparent"

                // 2 px accent strip on the left edge of the active row
                Rectangle {
                    width: 2
                    height: parent.height - 4
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.accent
                    visible: row.active
                    radius: 1
                }

                QQC.Label {
                    id: rowLabel
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    text: row.modelData.label
                    font.family: Theme.fontBody
                    font.pixelSize: 11
                    font.letterSpacing: 0.3
                    font.weight: row.active ? Font.Bold : Font.Normal
                    color: row.active ? Theme.accent
                           : ma.containsMouse ? Theme.fg
                           : Theme.fgDim
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        dd.valueSelected(row.modelData.val);
                        dd.close();
                    }
                }
            }
        }
    }
}
