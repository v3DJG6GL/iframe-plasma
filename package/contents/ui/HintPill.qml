// SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Transient confirmation pill. Hidden by default (opacity 0); show() ramps
// it to 1 over 250 ms, holds for `holdMs`, then fades back to 0. Used in
// ConfigAuth to acknowledge wallet write success/failure inline next to
// the secret field.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC

RowLayout {
    id: pill
    property alias text: label.text
    property color tint
    property string iconSource
    property int holdMs: 1500

    opacity: 0
    spacing: 2
    visible: opacity > 0   // skip hit-testing when hidden
    Behavior on opacity { NumberAnimation { duration: 250 } }

    function show() {
        fadeTimer.stop();
        opacity = 1;
        fadeTimer.start();
    }

    Timer {
        id: fadeTimer
        interval: pill.holdMs
        onTriggered: pill.opacity = 0
    }
    Kirigami.Icon {
        source: pill.iconSource
        color: pill.tint
        implicitWidth:  Kirigami.Units.iconSizes.small
        implicitHeight: Kirigami.Units.iconSizes.small
    }
    QQC.Label {
        id: label
        color: pill.tint
        font.italic: true
    }
}
