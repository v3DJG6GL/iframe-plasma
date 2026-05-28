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
import "./RowSchema.js" as RowSchema

KCM.SimpleKCM {
    id: page

    property alias cfg_authProfilesJson: store.json
    // Mirror of cfg_urlsJson — read for the delete-confirm preview, and
    // written back on profile delete to unlink orphan `authProfileId`
    // references. The write covers the case where ConfigUrls hasn't been
    // opened in this session, so its own `onAuthProfilesChanged` scrub
    // never fires.
    property string cfg_urlsJson: "[]"
    // Bumped on every successful secret write/remove so the widget
    // (running in a different QML engine than this dialog) re-runs
    // primeAuthProfiles + reloadAll via the KConfig change-notification
    // path. See main.xml comment on the entry.
    property int cfg_authProfilesSecretsSerial: 0

    Loader {
        id: authLoader
        source: "AuthSupport.qml"
        onStatusChanged: if (status === Loader.Error) {
            console.info("ConfigAuth: C++ plugin not built — password storage in plaintext fallback.");
        }
    }
    readonly property var authSupport: authLoader.item
    readonly property bool kwalletAvailable: authLoader.status === Loader.Ready

    // See the matching block in ConfigUrls.qml for the rationale: this gate
    // suppresses both the self-write path (serialize) and the loading path
    // (repopulate) so onJsonChanged doesn't recursively rebuild listModel
    // and silently lose any uncommitted text in sibling TextFields.
    property bool _reloading: false

    QtObject {
        id: store
        property string json: "[]"

        // Re-sync listModel when authProfilesJson changes from outside this
        // page — the Backup KCM page's Import path writes the cfg_*
        // backing value through KCM's cross-page kcfg mirror. Without this,
        // listModel still carries the pre-import rows and any subsequent
        // edit's serialize() would clobber the imported value.
        onJsonChanged: if (!page._reloading) page.repopulate()

        function serialize() {
            if (page._reloading) return;
            const arr = [];
            for (let i = 0; i < listModel.count; i++) {
                const row = listModel.get(i);
                arr.push({
                    id: row.id,
                    name: row.name,
                    authType: row.authType,
                    username: row.username || "",
                    autheliaHost: row.autheliaHost || "",
                    preempt: row.preempt === true
                });
            }
            // Gate the self-write so onJsonChanged doesn't re-enter
            // repopulate() and recycle every delegate on each keystroke
            // commit (per the ConfigUrls fix).
            page._reloading = true;
            try {
                json = JSON.stringify(arr);
            } finally {
                page._reloading = false;
            }
        }
    }

    ListModel { id: listModel }

    function repopulate() {
        _reloading = true;
        try {
            listModel.clear();
            const arr = JSON.parse(store.json || "[]");
            if (!Array.isArray(arr)) return;
            let synthesized = false;
            for (const entry of arr) {
                const norm = RowSchema.normaliseAuthProfileRow(entry, newUuid);
                // Re-persist when sanitize actually mutates a stored value,
                // otherwise an on-disk autheliaHost carrying a ZWSP/bidi byte
                // (legacy config, backup import, manual edit) is displayed
                // sanitized in the KCM but kept unsanitized in cfg_*JSON;
                // Apply rewrites the unsanitized form back to disk and the
                // runtime literal comparison silently fails (see comment
                // block on sanitizeAutheliaHost below).
                const beforeAH = norm.row.autheliaHost;
                norm.row.autheliaHost = sanitizeAutheliaHost(beforeAH);
                if (norm.synthesized || beforeAH !== norm.row.autheliaHost) synthesized = true;
                listModel.append(norm.row);
            }
            // Persist synthesized UUIDs immediately — otherwise the next
            // load generates fresh UUIDs, orphaning any wallet entry
            // written this session under the prior synthesized id. Done
            // here (not in serialize) because synthesis is a load-time
            // concern and must run regardless of which load path fired.
            if (synthesized) {
                // Drop the gate just for the inner serialize so the JSON
                // write actually happens, then re-raise it. The outer
                // finally still resets it cleanly.
                _reloading = false;
                store.serialize();
                _reloading = true;
            }
        } catch (e) {
            console.warn("ConfigAuth: parse error", e.message);
        } finally {
            _reloading = false;
        }
    }

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

    Component.onCompleted: page.repopulate()

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
            text: i18n("Define named authentication profiles here, then pick one per URL on the URLs tab. Multiple URLs can share a profile — rotate a password once, all tabs update. Choose type \"None\" for pages that handle their own login (form-based, cookies, OAuth).")
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
            text: i18n("Secrets stored in KDE Wallet under folder \"io.github.v3DJG6GL.iframe-plasma\". Open kwalletmanager6 to inspect.")
        }
        QQC.Button {
            text: i18n("Add profile")
            icon.name: "list-add"
            onClicked: page.createNewProfile()
        }
    }

    // `none` is a named passthrough profile: no Authorization header is
    // injected. Use it for pages that handle their own login (form-based
    // auth, cookies/sessions, OAuth interactive, browser 401 dialog).
    // Keeps the profile in the assignment dropdown so multiple URLs can
    // share it semantically (e.g. all SSO-fronted pages → "Authelia SSO"
    // profile) without needing a stored secret.
    readonly property var authTypePresets: [
        { value: "none",   display: i18n("None (page handles its own login — no header injected)"),
          secretLabel: "",                    fieldName: "",            hasUsername: false },
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
        // Default authType is "basic" → preempt=false (the safe-default).
        // If the user switches to bearer/raw via the combo, the
        // onActivated handler below promotes preempt to true.
        listModel.append({
            id: id,
            name: i18n("New profile"),
            authType: "basic",
            username: "",
            autheliaHost: "",
            preempt: false
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

            // See ConfigUrls.qml — wheel over any widget / gap / empty space
            // must scroll the surrounding ScrollView's wrapper Flickable.
            ScrollForwardingWheelHandler {}

            delegate: Kirigami.AbstractCard {
                id: card
                required property int index
                required property string id
                required property string name
                required property string authType
                required property string username
                required property string autheliaHost
                required property bool preempt

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
                            onActivated: _ => {
                                const newType = page.authTypePresets[currentIndex].value;
                                page.setField(card.index, "authType", newType);
                                // Bearer / Raw cannot fall back on Qt's basic-auth
                                // dialog (it can only collect user+password, not a
                                // token). Force preempt=true when switching to those
                                // types so the C++ URL-interceptor sends the header
                                // on the first request. Leave basic/none alone.
                                if (newType === "bearer" || newType === "raw") {
                                    if (card.preempt !== true) page.setField(card.index, "preempt", true);
                                }
                            }
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

                    // Secret field — label depends on authType. Hidden
                    // entirely for `none` (passthrough profile has no
                    // credential to capture; `fieldName` is "" and the
                    // KWallet write below would be a no-op).
                    RowLayout {
                        Layout.fillWidth: true
                        visible: page.authSpec(card.authType).fieldName.length > 0
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
                                    // Tell main.qml (different QML engine — direct
                                    // QML signals won't cross) that secrets changed,
                                    // via the KConfig change-notification path.
                                    page.cfg_authProfilesSecretsSerial = page.cfg_authProfilesSecretsSerial + 1;
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
                        // Transient capture-confirmation pill (success path)
                        // and its red mirror for setMap()==false (failure
                        // path) — without the latter, a wallet write failure
                        // would be silent (field clears identically on success
                        // and failure).
                        HintPill {
                            id: savedHint
                            iconSource: "emblem-success"
                            tint: Kirigami.Theme.positiveTextColor
                            text: i18n("Saved")
                        }
                        HintPill {
                            id: failedHint
                            iconSource: "dialog-error"
                            tint: Kirigami.Theme.negativeTextColor
                            text: i18n("Wallet write failed")
                            holdMs: 4000
                        }
                    }

                    // Pre-emption flag. Default per type: basic=off (the 401
                    // dialog auto-fill in main.qml handleBasicAuth still works
                    // and avoids leaking the header to cross-origin sub-
                    // requests); bearer/raw=on and locked (Qt's dialog can't
                    // collect a token, so the only working path is pre-emption).
                    RowLayout {
                        Layout.fillWidth: true
                        visible: card.authType !== "none"
                        QQC.Label { text: ""; Layout.preferredWidth: Kirigami.Units.gridUnit * 8 }
                        QQC.CheckBox {
                            id: preemptBox
                            Layout.fillWidth: true
                            text: i18n("Send credentials with the first request")
                            checked: card.preempt
                            enabled: page.kwalletAvailable
                                  && card.authType !== "bearer"
                                  && card.authType !== "raw"
                            onToggled: page.setField(card.index, "preempt", checked)
                            QQC.ToolTip.visible: hovered
                            QQC.ToolTip.delay: 600
                            QQC.ToolTip.text: (card.authType === "bearer" || card.authType === "raw")
                                ? i18n("Required for this profile type — the server's challenge dialog cannot accept a token.")
                                : i18n("Otherwise the server is asked first, then credentials are sent on the retry. Leave off to avoid sending the header to cross-origin sub-requests.")
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        // Authelia re-auth overlay only makes sense when the
                        // profile carries credentials worth re-presenting on
                        // a redirect. `none` profiles let the page handle
                        // its own login end-to-end.
                        visible: card.authType !== "none"
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
                                    page.cfg_authProfilesSecretsSerial = page.cfg_authProfilesSecretsSerial + 1;
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
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
            }
        }

        onAccepted: {
            if (page.authSupport) page.authSupport.removeKey(page.authSupport.profileKey(deleteConfirm.profileId));
            page.cfg_authProfilesSecretsSerial = page.cfg_authProfilesSecretsSerial + 1;
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
