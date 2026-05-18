/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "sanitize.js" as Sanitize

KCM.SimpleKCM {
    id: page

    property alias cfg_authProfilesJson: store.json
    property alias cfg_useBasicAuthInjection: injectionSwitch.checked
    // Mirror of cfg_urlsJson — read for the delete-confirm preview, and
    // written back on profile delete to unlink orphan `authProfileId`
    // references. The write covers the case where ConfigUrls hasn't been
    // opened in this session, so its own `onAuthProfilesChanged` scrub
    // never fires.
    property string cfg_urlsJson: "[]"

    Loader {
        id: authLoader
        source: "AuthSupport.qml"
        onStatusChanged: if (status === Loader.Error) {
            console.info("ConfigAuth: C++ plugin not built — password storage in plaintext fallback.");
        }
    }
    readonly property var authSupport: authLoader.item
    readonly property bool kwalletAvailable: authLoader.status === Loader.Ready

    QtObject {
        id: store
        property string json: "[]"

        function serialize() {
            const arr = [];
            for (let i = 0; i < listModel.count; i++) {
                const row = listModel.get(i);
                arr.push({
                    id: row.id,
                    name: row.name,
                    authType: row.authType,
                    username: row.username || "",
                    autheliaHost: row.autheliaHost || ""
                });
            }
            json = JSON.stringify(arr);
        }
    }

    ListModel { id: listModel }

    // Strip C0/DEL/C1 controls + ALM/ZWSP/ZWNJ/ZWJ/LRM/RLM/PDF/LRE/RLE/LRO/RLO/
    // LRI/RLI/FSI/PDI/LS/PS/BOM from the Authelia-host string before persisting.
    // WebTab.onAutheliaHost compares as a literal `host === autheliaHost ||
    // host.endsWith("." + autheliaHost)` against `new URL(currentUrl).host` —
    // a leading/trailing space or stray zero-width / bidi-control byte makes
    // the comparison silently fail, the "Authentication required" overlay
    // never appears, and the operator types credentials into the real
    // upstream login page instead of the controlled Authelia flow. Shared
    // strip in sanitize.js covers bidi/format/C0+C1 control code points.
    function sanitizeAutheliaHost(h) {
        return Sanitize.strip(String(h || "").trim());
    }

    // Simple UUID v4 generator (RFC 4122 compliant for our purposes).
    function newUuid() {
        // QML doesn't expose crypto.getRandomValues; use Math.random as fallback.
        // Profile IDs are not security-critical (they identify, don't authenticate).
        function hex() { return Math.floor(Math.random() * 16).toString(16); }
        let s = "";
        for (let i = 0; i < 32; i++) {
            if (i === 8 || i === 12 || i === 16 || i === 20) s += "-";
            if (i === 12) { s += "4"; continue; }       // version 4
            if (i === 16) { s += (8 + Math.floor(Math.random() * 4)).toString(16); continue; } // variant
            s += hex();
        }
        return s;
    }

    Component.onCompleted: {
        try {
            const arr = JSON.parse(store.json || "[]");
            let synthesized = false;
            for (const entry of arr) {
                let id = entry.id;
                if (!id) { id = newUuid(); synthesized = true; }
                listModel.append({
                    id: id,
                    name: entry.name || "",
                    authType: entry.authType || "basic",
                    username: entry.username || "",
                    // Sanitise on load too — the on-edit + on-persist sanitisers
                    // (3224e0e) close the in-session input path, but legacy JSON
                    // written before 3224e0e (or hand-edited config) carries the
                    // unsanitised value through `store.serialize()` verbatim and
                    // would bypass the WebTab overlay-host comparison until the
                    // user manually re-edits the field.
                    autheliaHost: sanitizeAutheliaHost(entry.autheliaHost)
                });
            }
            // Persist synthesized UUIDs immediately — otherwise the next load
            // generates fresh UUIDs, orphaning any wallet entry written this
            // session under the prior synthesized id.
            if (synthesized) store.serialize();
        } catch (e) { console.warn("ConfigAuth: parse error", e.message); }
    }

    function profileUsageHosts(profileId) {
        // Return labels of URLs that reference the given profile id (used by
        // delete-confirmation to warn the user about orphaned references).
        try {
            const tabs = JSON.parse(cfg_urlsJson || "[]");
            const out = [];
            for (const t of tabs) {
                if (t && t.authProfileId === profileId) {
                    out.push(t.label || t.url || i18nc("Fallback label for a URL with no name and no address", "(unlabeled)"));
                }
            }
            return out;
        } catch (e) { return []; }
    }

    header: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        QQC.Label {
            Layout.fillWidth: true
            text: i18n("Define named authentication profiles here, then pick one per URL on the URLs tab. Multiple URLs can share a profile — rotate a password once, all tabs update.")
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Warning
            visible: !page.kwalletAvailable
            text: i18n("KDE Wallet integration unavailable — build the bundled C++ plugin with cmake to enable secure password storage. Without it, secrets are not persisted (you'd need to re-enter them after every plasmashell restart).")
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Information
            visible: page.kwalletAvailable
            text: i18n("Secrets stored in KDE Wallet under folder \"iframe-plasma\". Open kwalletmanager6 to inspect.")
        }
        RowLayout {
            QQC.Button {
                text: i18n("Add profile")
                icon.name: "list-add"
                onClicked: page.createNewProfile()
            }
            Item { Layout.fillWidth: true }
            QQC.CheckBox {
                id: injectionSwitch
                text: i18n("Inject Authorization header pre-emptively (no 401 round-trip)")
                enabled: page.kwalletAvailable
            }
        }
    }

    readonly property var authTypePresets: [
        { value: "basic",  display: i18n("HTTP Basic (username + password)"),
          secretLabel: i18n("Password:"),     fieldName: "password",    hasUsername: true  },
        { value: "bearer", display: i18n("Bearer token (e.g. JWT)"),
          secretLabel: i18n("Token:"),        fieldName: "bearerToken", hasUsername: false },
        { value: "raw",    display: i18n("Raw Authorization header"),
          secretLabel: i18n("Header value:"), fieldName: "rawHeader",   hasUsername: false }
    ]
    function authSpec(authType) {
        return authTypePresets.find(p => p.value === authType) || authTypePresets[0];
    }

    function setField(idx, key, value) {
        listModel.setProperty(idx, key, value);
        store.serialize();
    }

    function createNewProfile() {
        const id = newUuid();
        listModel.append({
            id: id,
            name: i18n("New profile"),
            authType: "basic",
            username: "",
            autheliaHost: ""
        });
        store.serialize();
        profileList.currentIndex = listModel.count - 1;
    }

    QQC.ScrollView {
        anchors.fill: parent
        clip: true

        ListView {
            id: profileList
            model: listModel
            spacing: Kirigami.Units.smallSpacing

            delegate: Kirigami.AbstractCard {
                id: card
                required property int index
                required property string id
                required property string name
                required property string authType
                required property string username
                required property string autheliaHost

                width: ListView.view.width

                // Secret value loaded lazily from KWallet (or set inline before save).
                // We never display the secret — only "(stored)" / "(not set)" hint.
                property bool hasStoredSecret: page.authSupport
                    ? page.authSupport.has(page.authSupport.profileKey(card.id))
                    : false

                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        QQC.Label { text: i18n("Name:"); Layout.preferredWidth: Kirigami.Units.gridUnit * 8 }
                        QQC.TextField {
                            Layout.fillWidth: true
                            placeholderText: i18n("e.g. Grafana Production")
                            text: card.name
                            onEditingFinished: page.setField(card.index, "name", text)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        QQC.Label { text: i18n("Type:"); Layout.preferredWidth: Kirigami.Units.gridUnit * 8 }
                        QQC.ComboBox {
                            id: typeCombo
                            Layout.fillWidth: true
                            model: page.authTypePresets
                            textRole: "display"
                            valueRole: "value"
                            currentIndex: {
                                const idx = page.authTypePresets.findIndex(x => x.value === card.authType);
                                return idx >= 0 ? idx : 0;
                            }
                            onActivated: _ => page.setField(card.index, "authType", page.authTypePresets[currentIndex].value)
                            NoWheel {}
                        }
                    }

                    // Username — only for Basic
                    RowLayout {
                        Layout.fillWidth: true
                        visible: page.authSpec(card.authType).hasUsername
                        QQC.Label { text: i18n("Username:"); Layout.preferredWidth: Kirigami.Units.gridUnit * 8 }
                        QQC.TextField {
                            Layout.fillWidth: true
                            placeholderText: i18n("username")
                            text: card.username
                            onEditingFinished: page.setField(card.index, "username", text)
                        }
                    }

                    // Secret field — label depends on authType.
                    // After typing and tabbing away, the masked dots STAY
                    // visible (so the user sees their input was registered)
                    // AND a transient green "✓ Saved" pill fades in/out as
                    // confirmation. On dialog REOPEN the field is empty
                    // with the "(stored)" placeholder — we never read the
                    // secret back from KWallet (security).
                    RowLayout {
                        Layout.fillWidth: true
                        QQC.Label {
                            text: page.authSpec(card.authType).secretLabel
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                        }
                        QQC.TextField {
                            id: secretField
                            Layout.fillWidth: true
                            // Disable input when KWallet integration is missing — the
                            // onEditingFinished handler silently drops the text in
                            // that case, but the masked dots would otherwise stay
                            // visible and falsely signal "captured".
                            enabled: page.kwalletAvailable
                            echoMode: showSecret.checked ? TextInput.Normal : TextInput.Password
                            // ImhSensitiveData asks IMEs/virtual-keyboards to skip
                            // predictive-text caching and not surface this input as
                            // a suggestion in subsequent fields. Pair with
                            // NoPredictiveText / NoAutoUppercase so even a non-
                            // compliant IME doesn't leak word boundaries.
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                            placeholderText: card.hasStoredSecret ? i18n("(stored — type to replace)")
                                                                  : i18n("(not set)")
                            onEditingFinished: {
                                if (text.length === 0) return;
                                if (!page.authSupport) return;
                                const map = {};
                                map[page.authSpec(card.authType).fieldName] = text;
                                if (page.authSupport.setMap(page.authSupport.profileKey(card.id), map)) {
                                    card.hasStoredSecret = true;
                                    savedHint.show();
                                    // Clear the buffer so the showSecret toggle
                                    // can't reveal a just-saved password to a
                                    // bystander; the "(stored — type to replace)"
                                    // placeholder + Saved pill signal capture.
                                    showSecret.checked = false;
                                    text = "";
                                } else {
                                    // Wallet write failed (locked / unlock
                                    // denied). Surface a red "Wallet write
                                    // failed" pill so the user isn't misled by
                                    // the cleared field into thinking the
                                    // secret was saved. Reset showSecret so
                                    // the next retype isn't cleartext to a
                                    // bystander — symmetry with the success
                                    // branch's eye-toggle reset.
                                    showSecret.checked = false;
                                    text = "";
                                    failedHint.show();
                                }
                            }
                        }
                        QQC.ToolButton {
                            id: showSecret
                            icon.name: checked ? "password-show-on" : "password-show-off"
                            checkable: true
                        }
                        // Transient saved-confirmation pill. Hidden by
                        // default (opacity 0); show() ramps it to 1 over
                        // 250 ms, holds for 1.5 s, then fades back to 0.
                        RowLayout {
                            id: savedHint
                            opacity: 0
                            spacing: 2
                            visible: opacity > 0   // skip hit-testing when hidden
                            Behavior on opacity { NumberAnimation { duration: 250 } }
                            function show() {
                                fadeOutTimer.stop();
                                opacity = 1;
                                fadeOutTimer.start();
                            }
                            Timer {
                                id: fadeOutTimer
                                interval: 1500
                                onTriggered: savedHint.opacity = 0
                            }
                            Kirigami.Icon {
                                source: "emblem-success"
                                color: Kirigami.Theme.positiveTextColor
                                implicitWidth:  Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                            }
                            QQC.Label {
                                text: i18n("Saved")
                                color: Kirigami.Theme.positiveTextColor
                                font.italic: true
                            }
                        }
                        // Mirror of savedHint with a red "Wallet write failed"
                        // message — surfaces a setMap() == false outcome that
                        // would otherwise be silent (field clears identically
                        // on success and failure).
                        RowLayout {
                            id: failedHint
                            opacity: 0
                            spacing: 2
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 250 } }
                            function show() {
                                failedFadeTimer.stop();
                                opacity = 1;
                                failedFadeTimer.start();
                            }
                            Timer {
                                id: failedFadeTimer
                                interval: 4000
                                onTriggered: failedHint.opacity = 0
                            }
                            Kirigami.Icon {
                                source: "dialog-error"
                                color: Kirigami.Theme.negativeTextColor
                                implicitWidth:  Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                            }
                            QQC.Label {
                                text: i18n("Wallet write failed")
                                color: Kirigami.Theme.negativeTextColor
                                font.italic: true
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        QQC.Label { text: i18n("Authelia host:"); Layout.preferredWidth: Kirigami.Units.gridUnit * 8 }
                        QQC.TextField {
                            Layout.fillWidth: true
                            placeholderText: i18n("e.g. auth.example.com (optional)")
                            text: card.autheliaHost
                            // Sanitise on persist — see page.sanitizeAutheliaHost.
                            onEditingFinished: page.setField(card.index, "autheliaHost",
                                page.sanitizeAutheliaHost(text))
                            QQC.ToolTip.visible: hovered && text.length === 0
                            QQC.ToolTip.delay: 600
                            QQC.ToolTip.text: i18n("When the widget detects a redirect to this host, an \"Authentication required\" overlay appears. Leave empty to disable for this profile.")
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        QQC.Button {
                            text: i18n("Delete profile")
                            icon.name: "edit-delete"
                            onClicked: {
                                const referencing = page.profileUsageHosts(card.id);
                                if (referencing.length === 0) {
                                    // No URLs to warn about — just delete.
                                    if (page.authSupport) page.authSupport.removeKey(page.authSupport.profileKey(card.id));
                                    listModel.remove(card.index);
                                    store.serialize();
                                    return;
                                }
                                deleteConfirm.referencing = referencing;
                                deleteConfirm.profileId = card.id;
                                deleteConfirm.open();
                            }
                        }
                    }
                }
            }

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: listModel.count === 0
                text: i18n("No profiles yet")
                explanation: i18n("Click \"Add profile\" to define your first set of credentials.")
                icon.name: "list-add"
            }
        }
    }

    // Delete-confirmation dialog: shown when the user tries to delete a
    // profile that is still referenced by one or more URLs.
    Kirigami.PromptDialog {
        id: deleteConfirm
        property var referencing: []
        property string profileId: ""

        title: i18n("Delete this profile?")
        subtitle: i18np(
            "This profile is used by %1 URL. It will fall back to no authentication.",
            "This profile is used by %1 URLs. They will fall back to no authentication.",
            referencing.length)
        standardButtons: QQC.Dialog.Yes | QQC.Dialog.No

        ColumnLayout {
            QQC.Label {
                Layout.fillWidth: true
                text: deleteConfirm.referencing.map(s => "• " + s).join("\n")
                wrapMode: Text.WordWrap
            }
        }

        onAccepted: {
            if (page.authSupport) page.authSupport.removeKey(page.authSupport.profileKey(deleteConfirm.profileId));
            // Patch urlsJson to unlink the orphaned references
            try {
                const tabs = JSON.parse(page.cfg_urlsJson || "[]");
                let changed = false;
                for (const t of tabs) {
                    if (t && t.authProfileId === deleteConfirm.profileId) {
                        t.authProfileId = "";
                        changed = true;
                    }
                }
                if (changed) page.cfg_urlsJson = JSON.stringify(tabs);
            } catch (e) { console.warn("ConfigAuth: failed to patch urlsJson on delete:", e.message); }
            // Look up the current row index by id at accept-time — survives
            // in-tab listModel mutations between dialog-open and accept
            // (Pass-9's a1ebf94 fixed the cross-tab half via the
            // authProfilesJson scrub; this closes the in-tab half).
            for (let i = 0; i < listModel.count; i++) {
                if (listModel.get(i).id === deleteConfirm.profileId) {
                    listModel.remove(i);
                    break;
                }
            }
            store.serialize();
        }
    }
}
