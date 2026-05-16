/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import org.kde.kirigami as Kirigami

Rectangle {
    id: overlay

    enum State { Hidden, Loading, AuthRequired, Error }
    property int state: StatusOverlay.Hidden
    property string message: ""

    signal reloadClicked()
    signal openExternalClicked()
    signal loginClicked()

    color: Kirigami.Theme.backgroundColor
    opacity: state === StatusOverlay.Hidden ? 0 : 0.92
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    function showLoading() { message = ""; state = StatusOverlay.Loading; }
    function showAuthRequired() { state = StatusOverlay.AuthRequired; }
    function showError(msg) { message = msg; state = StatusOverlay.Error; }
    function hide() { state = StatusOverlay.Hidden; }

    MouseArea {
        anchors.fill: parent
        // Block clicks from reaching the webview while overlay is visible
        enabled: parent.visible
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Kirigami.Units.largeSpacing
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 24)

        // Loading state
        QQC.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: overlay.state === StatusOverlay.Loading
            running: visible
        }
        QQC.Label {
            Layout.alignment: Qt.AlignHCenter
            visible: overlay.state === StatusOverlay.Loading
            text: i18n("Loading…")
            color: Kirigami.Theme.textColor
        }

        // Auth required state
        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
            source: "dialog-password"
            visible: overlay.state === StatusOverlay.AuthRequired
        }
        QQC.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: overlay.state === StatusOverlay.AuthRequired
            text: i18n("Authentication required")
            font.bold: true
            color: Kirigami.Theme.textColor
        }
        QQC.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: overlay.state === StatusOverlay.AuthRequired
            text: i18n("Your session has expired or you are not logged in. Open the widget and complete login; the session will be remembered.")
            color: Kirigami.Theme.disabledTextColor
        }

        // Error state
        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
            source: "dialog-error"
            visible: overlay.state === StatusOverlay.Error
        }
        QQC.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: overlay.state === StatusOverlay.Error
            text: i18n("Failed to load")
            font.bold: true
            color: Kirigami.Theme.textColor
        }
        QQC.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: overlay.state === StatusOverlay.Error && overlay.message.length > 0
            text: overlay.message
            color: Kirigami.Theme.disabledTextColor
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing
            visible: overlay.state === StatusOverlay.Error || overlay.state === StatusOverlay.AuthRequired

            QQC.Button {
                text: i18n("Log in here")
                icon.name: "go-next"
                visible: overlay.state === StatusOverlay.AuthRequired
                highlighted: true
                onClicked: {
                    // Hide so the user can interact with the embedded Authelia
                    // login. The overlay re-appears automatically if the next
                    // load also lands on the Authelia host; otherwise stays hidden.
                    overlay.loginClicked();
                    overlay.hide();
                }
            }
            QQC.Button {
                text: i18n("Reload")
                icon.name: "view-refresh"
                onClicked: overlay.reloadClicked()
            }
            QQC.Button {
                text: i18n("Open in browser")
                icon.name: "internet-web-browser"
                onClicked: overlay.openExternalClicked()
            }
        }
    }
}
