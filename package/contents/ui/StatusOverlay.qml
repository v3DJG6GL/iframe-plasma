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

    enum Mode { Hidden, Loading, AuthRequired, Error }
    // Avoid `property int state` — that name shadows Item.state (a
    // built-in string state-machine property), and we want the int enum.
    property int mode: StatusOverlay.Hidden
    property string message: ""

    signal reloadClicked()
    signal openExternalClicked()
    signal loginClicked()

    color: Kirigami.Theme.backgroundColor
    opacity: mode === StatusOverlay.Hidden ? 0 : 0.92
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    function showLoading() { message = ""; mode = StatusOverlay.Loading; }
    function showAuthRequired() { mode = StatusOverlay.AuthRequired; }
    // Cap the error message length: a hostile origin can craft an errorString
    // (e.g. a >100 KB host suffix or a wall of NBSPs that Text.WordWrap can't
    // break) that grows the centered ColumnLayout vertically until the Reload
    // / Open-in-browser buttons are pushed off-screen and the tab is trapped.
    // 240 chars is enough room for every real Chromium error string.
    function showError(msg) {
        const s = String(msg || "");
        message = s.length > 240 ? s.slice(0, 237) + "…" : s;
        mode = StatusOverlay.Error;
    }
    function hide() { mode = StatusOverlay.Hidden; }

    MouseArea {
        anchors.fill: parent
        // Block ALL pointer events from reaching the webview while overlay is
        // visible. The default acceptedButtons is Qt.LeftButton — right-click
        // and middle-click would fall through to the page below (middle-click
        // opens links / pastes selection on X11, right-click hits the
        // pre-suppressed context-menu path but is still a behavioural channel
        // to attacker JS via mousedown/auxclick listeners). hoverEnabled +
        // onWheel: wheel.accepted=true swallows scroll so an Auth-Required
        // overlay over an autoscroll exploit can't drive the page off-screen.
        enabled: parent.visible
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: function(wheel) { wheel.accepted = true; }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Kirigami.Units.largeSpacing
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 24)

        // Loading state
        QQC.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: overlay.mode === StatusOverlay.Loading
            running: visible
        }
        QQC.Label {
            Layout.alignment: Qt.AlignHCenter
            visible: overlay.mode === StatusOverlay.Loading
            text: i18n("Loading…")
            color: Kirigami.Theme.textColor
        }

        // Auth required state
        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
            source: "dialog-password"
            visible: overlay.mode === StatusOverlay.AuthRequired
        }
        QQC.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: overlay.mode === StatusOverlay.AuthRequired
            text: i18n("Authentication required")
            font.bold: true
            color: Kirigami.Theme.textColor
        }
        QQC.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: overlay.mode === StatusOverlay.AuthRequired
            text: i18n("Your session has expired or you are not logged in. Open the widget and complete login; the session will be remembered.")
            color: Kirigami.Theme.disabledTextColor
        }

        // Error state
        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
            source: "dialog-error"
            visible: overlay.mode === StatusOverlay.Error
        }
        QQC.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: overlay.mode === StatusOverlay.Error
            text: i18n("Failed to load")
            font.bold: true
            color: Kirigami.Theme.textColor
        }
        QQC.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: overlay.mode === StatusOverlay.Error && overlay.message.length > 0
            text: overlay.message
            color: Kirigami.Theme.disabledTextColor
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing
            visible: overlay.mode === StatusOverlay.Error || overlay.mode === StatusOverlay.AuthRequired

            QQC.Button {
                text: i18n("Log in here")
                icon.name: "go-next"
                visible: overlay.mode === StatusOverlay.AuthRequired
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
