// SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Muted, word-wrapped, slightly smaller form-hint Label. Capped at
// gridUnit*22 wide so long explanations don't blow out the KCM column.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC

QQC.Label {
    Layout.fillWidth: true
    Layout.maximumWidth: Kirigami.Units.gridUnit * 22
    wrapMode: Text.WordWrap
    color: Kirigami.Theme.disabledTextColor
    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 1
}
