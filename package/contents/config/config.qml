/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18nc("@title:tab", "URLs")
        icon: "view-list-details"
        source: "ConfigUrls.qml"
    }
    ConfigCategory {
        name: i18nc("@title:tab", "Display")
        icon: "preferences-desktop-color"
        source: "ConfigDisplay.qml"
    }
    ConfigCategory {
        name: i18nc("@title:tab", "Authentication")
        icon: "dialog-password"
        source: "ConfigAuth.qml"
    }
    ConfigCategory {
        name: i18nc("@title:tab", "Advanced")
        icon: "configure"
        source: "ConfigAdvanced.qml"
    }
    ConfigCategory {
        name: i18nc("@title:tab", "Backup")
        icon: "document-save"
        source: "ConfigBackup.qml"
    }
}
