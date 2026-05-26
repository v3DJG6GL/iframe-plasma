/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: page

    property alias cfg_urlsJson: store.json
    property alias cfg_currentTabIndex: store.currentIndex

    // Wheel forwarder for open ComboBox popups. By default, a wheel landing
    // on an expanded dropdown goes to the popup's internal ListView; if the
    // option list isn't long enough to scroll, the wheel is eaten and the
    // page beneath refuses to move. This Component is instantiated as a
    // WheelHandler inside each ComboBox's popup contentItem on first
    // open: it lets the popup keep scrolling when it actually overflows,
    // but otherwise closes the popup and forwards the wheel to the URL
    // list's surrounding scroller.
    Component {
        id: popupWheelForwarder
        WheelHandler {
            property QtObject combo
            property Item scrollTarget
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y
                                                    : event.angleDelta.y / 8
                const list = parent
                if (list && list.contentHeight !== undefined
                         && list.height !== undefined
                         && list.contentHeight > list.height) {
                    // Popup itself is scrollable — scroll its ListView
                    // directly. We cannot rely on `event.accepted = false`
                    // to propagate to the underlying Flickable: WheelHandler
                    // runs at the post-delivery handler layer, so the
                    // sibling/parent Flickable does not re-process the
                    // event. Move contentY ourselves.
                    list.contentY = Math.max(0,
                        Math.min(list.contentHeight - list.height,
                                 list.contentY - dy))
                    event.accepted = true
                    return
                }
                if (combo && combo.popup) combo.popup.close()
                let p = scrollTarget
                while (p) {
                    if (typeof p.returnToBounds === "function"
                        && p.contentY !== undefined
                        && p.contentHeight !== undefined
                        && p.height !== undefined
                        && p.contentHeight > p.height) {
                        p.contentY = Math.max(0,
                            Math.min(p.contentHeight - p.height,
                                     p.contentY - dy))
                        break
                    }
                    p = p.parent
                }
                event.accepted = true
            }
        }
    }

    QtObject {
        id: store
        property string json: "[]"
        property int currentIndex: 0

        function serialize() {
            const arr = [];
            for (let i = 0; i < listModel.count; i++) {
                const row = listModel.get(i);
                arr.push({
                    label: row.label,
                    url: row.url,
                    authProfileId: row.authProfileId || "",
                    thumbMode: row.thumbMode || "chartOnly",
                    thumbSelector: row.thumbSelector || "",
                    thumbText: row.thumbText || "",
                    thumbIconName: row.thumbIconName || "",
                    thumbTimeRange: row.thumbTimeRange || "",
                    popupMode: row.popupMode || "fullPanel",
                    popupSelector: row.popupSelector || ""
                });
            }
            json = JSON.stringify(arr);
        }
    }

    // Heuristic: does this URL look like a Grafana embed? Matches
    // `/d/<uid>/...` (full dashboard) or `/d-solo/<uid>/...` (single
    // panel embed) — both are stable since Grafana 8.x and are what the
    // helper dialog produces or accepts. Used to gate the per-card
    // "Edit Grafana settings…" button so it doesn't appear on non-
    // Grafana tabs (e.g., a Home Assistant dashboard URL).
    function isGrafanaEmbed(u) {
        if (!u) return false;
        return /\/d(-solo)?\/[A-Za-z0-9_-]+\//.test(u);
    }

    // Mirror of main.qml's resolveIconSource for the per-card preview.
    // Kept local to the config page so the picker preview renders the
    // right source without requiring a round-trip through Plasmoid.
    // Plain name → theme icon; "bundled:foo" → shipped SVG; "file://..."
    // → straight file URL.
    function resolveIconPreview(name) {
        if (!name) return "image-missing";
        if (String(name).startsWith("bundled:"))
            return Qt.resolvedUrl("../icons/bundled/" + String(name).substring(8) + ".svg");
        return name;
    }

    // Read-only mirror of the Auth tab's profile list. KCM auto-binds
    // any `cfg_*` property to the matching kcfg key bidirectionally, so
    // changes made on the Authentication tab are visible HERE LIVE — no
    // close+reopen of the config dialog needed.
    //
    // (Previously read via `Plasmoid.configuration.authProfilesJson`, but
    // `Plasmoid` isn't imported in this file, so the access threw a silent
    // ReferenceError and the dropdown was always empty.)
    property string cfg_authProfilesJson: "[]"
    property var authProfiles: parseAuthProfiles(cfg_authProfilesJson)
    function parseAuthProfiles(jsonStr) {
        try {
            const arr = JSON.parse(jsonStr || "[]");
            return Array.isArray(arr) ? arr : [];
        } catch (e) { return []; }
    }
    // When the Authentication tab deletes a profile, cfg_urlsJson is
    // patched there to unlink references. Our listModel was populated
    // once in Component.onCompleted, so it still carries the now-orphaned
    // authProfileId — the next serialize() (any user edit on this tab)
    // would write the stale value back and clobber the unlink. Scrub
    // here whenever the auth profile set changes.
    onAuthProfilesChanged: {
        const validIds = new Set();
        for (const p of authProfiles) if (p.id) validIds.add(p.id);
        for (let i = 0; i < listModel.count; i++) {
            const apid = listModel.get(i).authProfileId;
            if (apid && !validIds.has(apid)) {
                listModel.setProperty(i, "authProfileId", "");
            }
        }
    }

    ListModel { id: listModel }

    Component.onCompleted: {
        try {
            const arr = JSON.parse(store.json || "[]");
            for (const entry of arr) {
                // Migration: legacy configs only have `thumbSelector`. If a
                // selector is set but no `thumbMode`, this was a power-user
                // tab — preserve the value by switching to `custom`.
                let mode = entry.thumbMode || "";
                const sel = entry.thumbSelector || "";
                if (!mode) mode = sel.length > 0 ? "custom" : "chartOnly";
                // Legacy auth fields (basicAuthUser, basicAuthPasswordPlaintext,
                // rawAuthHeader) are migrated to auth profiles in main.qml at
                // widget startup. Here on the config page we just read
                // `authProfileId` which is set after migration.
                // popupMode legacy migration: a tab with no popupMode but a
                // popupSelector set is a hand-edited config — treat as custom.
                let pmode = entry.popupMode || "";
                const psel = entry.popupSelector || "";
                if (!pmode) pmode = psel.length > 0 ? "custom" : "fullPanel";
                listModel.append({
                    label: entry.label || "",
                    url: entry.url || "",
                    authProfileId: entry.authProfileId || "",
                    thumbMode: mode,
                    thumbSelector: sel,
                    thumbText: entry.thumbText || "",
                    thumbIconName: entry.thumbIconName || "",
                    thumbTimeRange: entry.thumbTimeRange || "",
                    popupMode: pmode,
                    popupSelector: psel
                });
            }
        } catch (e) { console.warn("ConfigUrls: parse error", e.message); }
    }

    header: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        QQC.Label {
            Layout.fillWidth: true
            text: i18n("Each URL becomes a tab in the widget. Use ${theme} as a placeholder for the Grafana theme.")
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
        }
        RowLayout {
            QQC.Button {
                text: i18n("Add URL")
                icon.name: "list-add"
                onClicked: {
                    listModel.append({ label: "", url: "https://", authProfileId: "", thumbMode: "chartOnly", thumbSelector: "", thumbText: "", thumbIconName: "", thumbTimeRange: "", popupMode: "fullPanel", popupSelector: "" });
                    store.serialize();
                    urlList.currentIndex = listModel.count - 1;
                }
            }
            QQC.Button {
                text: i18n("From Grafana URL…")
                icon.name: "go-jump"
                onClicked: grafanaHelper.open()
            }
            Item { Layout.fillWidth: true }
        }
    }

    QQC.ScrollView {
        anchors.fill: parent
        clip: true

        ListView {
            id: urlList
            model: listModel
            spacing: Kirigami.Units.smallSpacing

            // Forward any wheel landing anywhere inside the list — over a
            // card, over the gap between cards, over empty trailing space —
            // up to the outer scroller (the wrapper Flickable that
            // QQC.ScrollView puts around this ListView and gives full
            // content height to). Attaching a WheelHandler at the ListView
            // catches the whole subtree; a per-delegate handler would miss
            // the spacing gaps and any unfilled tail. The walk skips this
            // ListView (its contentH == h, since the ScrollView expanded it
            // to fit) and lands on the actual scrolling Flickable.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y
                             : event.angleDelta.y / 8
                    let p = parent
                    while (p) {
                        if (typeof p.returnToBounds === "function"
                            && p.contentY !== undefined
                            && p.contentHeight !== undefined
                            && p.height !== undefined
                            && p.contentHeight > p.height) {
                            p.contentY = Math.max(0,
                                Math.min(p.contentHeight - p.height,
                                         p.contentY - dy))
                            break
                        }
                        p = p.parent
                    }
                    event.accepted = true
                }
            }

            delegate: Kirigami.AbstractCard {
                required property int index
                required property string label
                required property string url
                required property string authProfileId
                required property string thumbMode
                required property string thumbSelector
                required property string thumbText
                required property string thumbIconName
                required property string popupMode
                required property string popupSelector
                // Thumbnail-mode presets shown in the combo. Grafana embeds
                // get the uPlot-specific chartOnly/chartWithAxes presets in
                // addition to the generic options; non-Grafana URLs see only
                // the generic ones. `text`, `icon`, and `excluded` skip the
                // WebEngineView render path entirely — cheap stand-ins for
                // tabs whose live preview is uninteresting or unwanted.
                readonly property var thumbModePresets: {
                    const generic = [
                        { value: "fullPanel", display: i18n("Full page (no crop)") },
                        { value: "custom",    display: i18n("Custom CSS selector…") },
                        { value: "text",      display: i18n("Text label") },
                        { value: "icon",      display: i18n("Icon") },
                        { value: "excluded",  display: i18n("Hide from panel slot") }
                    ];
                    if (!page.isGrafanaEmbed(url)) return generic;
                    return [
                        { value: "chartOnly",     display: i18n("Chart only") },
                        { value: "chartWithAxes", display: i18n("Chart + axes") }
                    ].concat(generic);
                }

                width: ListView.view.width

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.ListSectionHeader {
                        text: "#" + (index + 1)
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        QQC.TextField {
                            Layout.fillWidth: true
                            placeholderText: i18n("Label (e.g. CPU load)")
                            text: label
                            onEditingFinished: { listModel.setProperty(index, "label", text); store.serialize() }
                        }
                        QQC.TextField {
                            Layout.fillWidth: true
                            placeholderText: "https://grafana.example.com/d-solo/..."
                            text: url
                            // Strip CR/LF/NUL on save. The Grafana-helper paste
                            // path already rejects these (c4886a4), but this
                            // direct URL field would otherwise persist them
                            // straight into urlsJson — bypassing the helper's
                            // check. parseTabs in main.qml only screens the
                            // scheme prefix (/^https?:\/\//), so a typed/
                            // pasted URL containing \r\n\0 survives the
                            // round-trip and reaches WebEngineView navigation.
                            // Same threat-class as the helper reject + the
                            // auth-interceptor C0-byte reject + the userAgent
                            // CR/LF strip.
                            onEditingFinished: {
                                const cleaned = String(text).replace(/[\r\n\0]/g, "");
                                if (cleaned !== text) text = cleaned;
                                listModel.setProperty(index, "url", cleaned);
                                store.serialize();
                            }
                        }
                        // Auth profile selector. Profiles are managed on the
                        // Authentication tab — pick one (or "None") here.
                        // The `+ New profile…` option is a hint; the user must
                        // create profiles on the Authentication tab.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            QQC.Label {
                                text: i18n("Auth:")
                                color: Kirigami.Theme.disabledTextColor
                            }
                            QQC.ComboBox {
                                id: profileCombo
                                Layout.fillWidth: true
                                readonly property var rows: {
                                    const base = [{ id: "", display: i18n("None (public URL)") }];
                                    for (const p of page.authProfiles) {
                                        const sub = p.username ? " (" + p.username + ")" : "";
                                        base.push({ id: p.id, display: (p.name || i18n("Untitled")) + sub });
                                    }
                                    return base;
                                }
                                model: rows
                                textRole: "display"
                                valueRole: "id"
                                onActivated: _ => {
                                    const v = rows[currentIndex].id;
                                    listModel.setProperty(index, "authProfileId", v);
                                    store.serialize();
                                }
                                QQC.ToolTip.visible: hovered && page.authProfiles.length === 0
                                QQC.ToolTip.delay: 400
                                QQC.ToolTip.text: i18n("Create auth profiles on the Authentication tab, then pick one here.")
                                NoWheel {}
                                property bool _popupWheelHooked: false
                                Connections {
                                    target: profileCombo.popup
                                    function onOpened() {
                                        if (profileCombo._popupWheelHooked) return
                                        popupWheelForwarder.createObject(
                                            profileCombo.popup.contentItem,
                                            { combo: profileCombo, scrollTarget: urlList })
                                        profileCombo._popupWheelHooked = true
                                    }
                                }
                            }
                            // currentIndex via Binding so it survives the
                            // ComboBox's internal write on user click —
                            // otherwise the onAuthProfilesChanged scrub
                            // (clearing authProfileId after a profile is
                            // deleted on the Auth tab) wouldn't propagate
                            // to the visible combo.
                            Binding {
                                target: profileCombo
                                property: "currentIndex"
                                value: {
                                    const idx = profileCombo.rows.findIndex(x => x.id === authProfileId);
                                    return idx >= 0 ? idx : 0;
                                }
                            }
                            // Edit Grafana settings — only shown on cards
                            // whose URL looks like a Grafana embed (/d/
                            // or /d-solo/). Opens the helper dialog in
                            // Edit mode with checkboxes/combos pre-filled
                            // from the current URL. Hides on non-Grafana
                            // tabs (e.g., a Home Assistant dashboard) so
                            // the card UI stays uncluttered there.
                            QQC.ToolButton {
                                visible: page.isGrafanaEmbed(url)
                                text: i18n("Edit Grafana settings…")
                                icon.name: "configure"
                                display: QQC.AbstractButton.TextBesideIcon
                                onClicked: grafanaHelper.openForEdit(index, url, label)
                                QQC.ToolTip.visible: hovered
                                QQC.ToolTip.delay: 400
                                QQC.ToolTip.text: i18n("Edit the Grafana embed parameters (time range, kiosk, theme, auto-refresh, branding, panel menu) on this tab without re-pasting the URL.")
                            }
                        }

                        // Thumbnail mode. Applied ONLY to the panel-slot
                        // mini-view, NOT the popup. Preset list comes from
                        // the delegate-scoped `thumbModePresets` binding,
                        // which filters out the uPlot-specific chartOnly /
                        // chartWithAxes presets when the URL doesn't look
                        // like a Grafana embed.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            QQC.Label {
                                text: i18n("Thumbnail (panel slot):")
                                color: Kirigami.Theme.disabledTextColor
                            }
                            QQC.ComboBox {
                                id: thumbModeCombo
                                Layout.fillWidth: true
                                model: thumbModePresets
                                textRole: "display"
                                valueRole: "value"
                                currentIndex: {
                                    const idx = thumbModePresets.findIndex(x => x.value === thumbMode);
                                    // Stored thumbMode might be a Grafana-only
                                    // preset (chartOnly / chartWithAxes) on a
                                    // non-Grafana URL — those aren't in the
                                    // filtered list, so fall back to the
                                    // fullPanel index. We don't auto-rewrite
                                    // the JSON; switching the URL back to
                                    // Grafana later should restore the value.
                                    if (idx >= 0) return idx;
                                    const fp = thumbModePresets.findIndex(x => x.value === "fullPanel");
                                    return fp >= 0 ? fp : 0;
                                }
                                // Arrow form names the signal param `_` so it
                                // doesn't shadow the delegate's `index` —
                                // ComboBox.activated(int index) would otherwise
                                // capture `index` and we'd write to the wrong
                                // listModel row (the activated combo item
                                // index, not the URL-row index).
                                onActivated: _ => {
                                    const v = thumbModePresets[currentIndex].value;
                                    listModel.setProperty(index, "thumbMode", v);
                                    store.serialize();
                                }
                                QQC.ToolTip.visible: hovered
                                QQC.ToolTip.delay: 600
                                QQC.ToolTip.text: page.isGrafanaEmbed(url)
                                    ? i18n(
                                        "How the panel slot renders this tab.\n\n"
                                      + "  • Chart only      — uPlot's painted canvas (no axes, no title).\n"
                                      + "  • Chart + axes    — chart plus tick labels.\n"
                                      + "  • Full page       — entire view, no crop.\n"
                                      + "  • Custom selector — any CSS selector you provide.\n"
                                      + "  • Text label      — plain text (no live render). Cheap.\n"
                                      + "  • Icon            — a KDE theme icon. Cheap.\n"
                                      + "  • Hide            — never show this tab in the slot; skipped during rotation.")
                                    : i18n(
                                        "How the panel slot renders this tab.\n\n"
                                      + "  • Full page       — entire view, no crop.\n"
                                      + "  • Custom selector — any CSS selector you provide (the\n"
                                      + "                      sibling DOM is hidden and the target is\n"
                                      + "                      sized to fill the slot).\n"
                                      + "  • Text label      — plain text (no live render). Cheap.\n"
                                      + "  • Icon            — a KDE theme icon. Cheap.\n"
                                      + "  • Hide            — never show this tab in the slot; skipped during rotation.")
                                NoWheel {}
                                property bool _popupWheelHooked: false
                                Connections {
                                    target: thumbModeCombo.popup
                                    function onOpened() {
                                        if (thumbModeCombo._popupWheelHooked) return
                                        popupWheelForwarder.createObject(
                                            thumbModeCombo.popup.contentItem,
                                            { combo: thumbModeCombo, scrollTarget: urlList })
                                        thumbModeCombo._popupWheelHooked = true
                                    }
                                }
                            }
                        }
                        QQC.TextField {
                            id: customThumbSelector
                            Layout.fillWidth: true
                            visible: thumbMode === "custom"
                            placeholderText: i18n("e.g. .u-wrap, canvas, [data-testid='data-testid panel content']")
                            text: thumbSelector
                            onEditingFinished: { listModel.setProperty(index, "thumbSelector", text); store.serialize() }
                        }

                        // `text` mode follow-up: the panel slot renders this
                        // string centered (no WebEngineView, no renderer
                        // process). Falls back to the tab's `label` field
                        // when empty, so a tab can show its name without an
                        // extra config step.
                        QQC.TextField {
                            id: thumbTextField
                            Layout.fillWidth: true
                            visible: thumbMode === "text"
                            placeholderText: i18n("e.g. DEV, PROD, server-01 (defaults to the tab label)")
                            text: thumbText
                            onEditingFinished: { listModel.setProperty(index, "thumbText", text); store.serialize() }
                        }

                        // `icon` mode follow-up: button opens our tabbed
                        // picker (Theme / Bundled monitoring SVGs / From
                        // file). thumbIconName uses prefixes:
                        //   plain name → KDE theme icon
                        //   "bundled:<name>" → shipped Phosphor SVG
                        //   "file:///..." → user-picked file
                        // main.qml's resolveIconSource() dispatches at the
                        // render site.
                        RowLayout {
                            Layout.fillWidth: true
                            visible: thumbMode === "icon"
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: page.resolveIconPreview(thumbIconName)
                                // isMask only for bundled SVGs (currentColor
                                // fill needs Kirigami's tint pass); theme
                                // icons and user-picked files stay full-color.
                                isMask: String(thumbIconName).startsWith("bundled:")
                                color: Kirigami.Theme.textColor
                                implicitWidth:  Kirigami.Units.iconSizes.medium
                                implicitHeight: Kirigami.Units.iconSizes.medium
                            }
                            QQC.Label {
                                Layout.fillWidth: true
                                text: thumbIconName.length > 0 ? thumbIconName : i18n("(no icon picked)")
                                color: thumbIconName.length > 0
                                    ? Kirigami.Theme.textColor
                                    : Kirigami.Theme.disabledTextColor
                                elide: Text.ElideRight
                            }
                            QQC.Button {
                                text: thumbIconName.length > 0 ? i18n("Change…") : i18n("Pick icon…")
                                icon.name: "preferences-desktop-icons"
                                onClicked: iconPicker.open()
                            }
                            IconPickerDialog {
                                id: iconPicker
                                onIconNameChanged: (picked) => {
                                    if (picked && picked.length > 0) {
                                        listModel.setProperty(index, "thumbIconName", picked);
                                        store.serialize();
                                    }
                                }
                            }
                        }

                        // `excluded` mode follow-up: explainer label, no input.
                        QQC.Label {
                            Layout.fillWidth: true
                            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
                            visible: thumbMode === "excluded"
                            text: i18n("This URL is hidden from the panel-slot preview and skipped during rotation.")
                            wrapMode: Text.WordWrap
                            color: Kirigami.Theme.disabledTextColor
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 1
                        }

                        // Widget (popup) crop. Independent of the thumbnail
                        // selector — same engine (CropEngine.js generic
                        // isolation path), different scope. Use for sites
                        // where the popup should show one panel/card from a
                        // larger dashboard. Grafana presets are thumbnail-
                        // only (canvas-pixel-blit doesn't help an
                        // interactive popup), so the popup combo offers just
                        // "Full page" vs "Custom CSS selector".
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            QQC.Label {
                                text: i18n("Widget (popup):")
                                color: Kirigami.Theme.disabledTextColor
                            }
                            QQC.ComboBox {
                                id: popupModeCombo
                                Layout.fillWidth: true
                                readonly property var presets: [
                                    { value: "fullPanel", display: i18n("Full page (no crop)") },
                                    { value: "custom",    display: i18n("Custom CSS selector…") }
                                ]
                                model: presets
                                textRole: "display"
                                valueRole: "value"
                                currentIndex: {
                                    const idx = presets.findIndex(x => x.value === popupMode);
                                    return idx >= 0 ? idx : 0;
                                }
                                onActivated: _ => {
                                    const v = presets[currentIndex].value;
                                    listModel.setProperty(index, "popupMode", v);
                                    store.serialize();
                                }
                                QQC.ToolTip.visible: hovered
                                QQC.ToolTip.delay: 600
                                QQC.ToolTip.text: i18n(
                                    "How the full popup view renders the page.\n\n"
                                  + "  • Full page       — entire URL, unchanged.\n"
                                  + "  • Custom selector — hide everything except the matched element\n"
                                  + "                       (e.g. one card from a SaaS dashboard).\n\n"
                                  + "Survives SPA re-renders and works on any tag, not just Grafana canvases.")
                                NoWheel {}
                                property bool _popupWheelHooked: false
                                Connections {
                                    target: popupModeCombo.popup
                                    function onOpened() {
                                        if (popupModeCombo._popupWheelHooked) return
                                        popupWheelForwarder.createObject(
                                            popupModeCombo.popup.contentItem,
                                            { combo: popupModeCombo, scrollTarget: urlList })
                                        popupModeCombo._popupWheelHooked = true
                                    }
                                }
                            }
                        }
                        QQC.TextField {
                            id: customPopupSelector
                            Layout.fillWidth: true
                            visible: popupMode === "custom"
                            placeholderText: i18n("e.g. .mb-8, [data-testid='dashboard'], #main")
                            text: popupSelector
                            onEditingFinished: { listModel.setProperty(index, "popupSelector", text); store.serialize() }
                        }
                    }

                    ColumnLayout {
                        QQC.ToolButton {
                            icon.name: "go-up"
                            enabled: index > 0
                            onClicked: { listModel.move(index, index - 1, 1); store.serialize() }
                        }
                        QQC.ToolButton {
                            icon.name: "go-down"
                            enabled: index < listModel.count - 1
                            onClicked: { listModel.move(index, index + 1, 1); store.serialize() }
                        }
                        QQC.ToolButton {
                            icon.name: "edit-delete"
                            onClicked: { listModel.remove(index); store.serialize() }
                        }
                    }
                }
            }

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: listModel.count === 0
                text: i18n("No URLs yet")
                explanation: i18n("Click \"Add URL\" or paste a Grafana URL via the helper.")
                icon.name: "list-add"
            }
        }
    }

    // Grafana URL helper — converts /d/ or /goto/ URLs into /d-solo/ + applies
    // common embedding parameters (kiosk, theme, refresh, default time range).
    // Stable across Grafana 10/11/12 per docs at https://grafana.com/blog/
    //
    // Two modes (driven by `editingIndex`):
    //   editingIndex == -1  →  ADD mode (default): paste a URL, OK appends
    //                          a new tab to listModel.
    //   editingIndex >=  0  →  EDIT mode: pre-filled from listModel[idx]'s
    //                          URL. The paste/label/single-panel fields hide
    //                          (the URL is the card's URL, not pasted). OK
    //                          strips managed params from the existing URL
    //                          and reapplies them per the current toggles.
    QQC.Dialog {
        id: grafanaHelper
        property int editingIndex: -1
        property string editingLabel: ""
        title: editingIndex >= 0
             ? i18n("Edit Grafana settings: %1", editingLabel || i18n("(no label)"))
             : i18n("Add from Grafana URL")
        anchors.centerIn: parent
        modal: true
        standardButtons: QQC.Dialog.Cancel | QQC.Dialog.Ok
        width: Math.min(parent.width * 0.9, Kirigami.Units.gridUnit * 42)

        // Reset editingIndex on any close so the next open() starts fresh.
        // Without this, OK in Edit mode would leave editingIndex set and a
        // subsequent "From Grafana URL…" click would still be in Edit mode.
        onClosed: { editingIndex = -1; editingLabel = ""; }

        // Time-range presets — see https://grafana.com/docs/grafana/latest/dashboards/time-range-controls/
        readonly property var timeRangePresets: [
            { val: "",    label: i18n("(keep URL's range)") },
            { val: "5m",  label: i18n("Last 5 minutes")  },
            { val: "15m", label: i18n("Last 15 minutes") },
            { val: "30m", label: i18n("Last 30 minutes") },
            { val: "1h",  label: i18n("Last 1 hour")     },
            { val: "6h",  label: i18n("Last 6 hours")    },
            { val: "12h", label: i18n("Last 12 hours")   },
            { val: "24h", label: i18n("Last 24 hours")   },
            { val: "7d",  label: i18n("Last 7 days")     },
            { val: "30d", label: i18n("Last 30 days")    },
            { val: "90d", label: i18n("Last 90 days")    }
        ]

        // Don't use `anchors.fill: parent` here — that zeros out the layout's
        // implicitHeight which QQC.Dialog needs to size the content area
        // (otherwise the footer buttons overlap the form).
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            // Intro paragraph + URL paste + Label fields + Single-panel
            // toggle are Add-mode-only. In Edit mode the URL is the
            // existing card's URL (we don't show it for re-paste; the
            // user clicked Edit on a known card), and the /d/→/d-solo/
            // conversion is a one-shot transform we can't reverse, so
            // we hide its checkbox to avoid implying it can be undone.
            QQC.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: grafanaHelper.editingIndex < 0
                text: i18n("Paste any Grafana URL — either a full dashboard `/d/...` URL (with viewPanel=panel-N) or a `/goto/<id>` short link. The helper applies the embedding parameters you select below.")
            }
            QQC.TextField {
                id: pastedUrl
                Layout.fillWidth: true
                visible: grafanaHelper.editingIndex < 0
                placeholderText: "https://grafana.example.com/d/abc/dash?…&viewPanel=panel-5"
            }
            QQC.TextField {
                id: pastedLabel
                Layout.fillWidth: true
                visible: grafanaHelper.editingIndex < 0
                placeholderText: i18n("Label (optional — falls back to panel id)")
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing

                QQC.CheckBox {
                    id: convertDSolo
                    visible: grafanaHelper.editingIndex < 0
                    Kirigami.FormData.label: visible ? i18n("Single panel:") : ""
                    text: i18n("Convert /d/ to /d-solo/ (panelId from viewPanel)")
                    checked: true
                }
                QQC.ComboBox {
                    id: timeRangeCombo
                    Kirigami.FormData.label: i18n("Default time range:")
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                    model: grafanaHelper.timeRangePresets
                    textRole: "label"
                    valueRole: "val"
                    currentIndex: 7   // 24h (Last 24 hours)
                    NoWheel {}
                }
                QQC.CheckBox {
                    id: addKiosk
                    Kirigami.FormData.label: i18n("Kiosk mode:")
                    text: i18n("Hide remaining Grafana chrome")
                    checked: true
                }
                QQC.CheckBox {
                    id: addTheme
                    Kirigami.FormData.label: i18n("Theme:")
                    text: i18n("Match KDE color scheme (substitutes ${theme})")
                    checked: true
                }
                RowLayout {
                    Kirigami.FormData.label: i18n("Auto-refresh:")
                    QQC.CheckBox { id: addRefresh; text: i18n("every"); checked: true }
                    UnitSpinBox {
                        id: refreshInterval
                        from: 5; to: 3600
                        value: 30
                        enabled: addRefresh.checked
                        suffix: " s"
                    }
                }
                // hideLogo=true removes Grafana 12.4+'s "Powered by Grafana"
                // overlay (PR #115198). Harmless on older Grafana — the param
                // is silently ignored. Default on; users rarely want it.
                QQC.CheckBox {
                    id: addHideLogo
                    Kirigami.FormData.label: i18n("Branding:")
                    text: i18n("Hide \"Powered by Grafana\" badge")
                    checked: true
                }
                // Panel-menu hide is client-side: Grafana has no URL flag
                // for the per-panel 3-dot menu (issue #12019 open since
                // 2018; team-recommended workaround is CSS). We append our
                // internal sentinel `_ifp_hidePanelMenu=1` which Grafana
                // ignores (unknown query param) and a WebEngineScript in
                // WebTab.qml detects it and injects the hiding CSS.
                QQC.CheckBox {
                    id: addHidePanelMenu
                    Kirigami.FormData.label: i18n("Panel menu:")
                    text: i18n("Hide per-panel 3-dot menu (Explore / View / Inspect)")
                    checked: true
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                type: Kirigami.MessageType.Information
                visible: grafanaHelper.editingIndex < 0 && pastedUrl.text.indexOf("/goto/") !== -1
                text: i18n("This is a `/goto/<id>` short URL. Kiosk / theme / refresh / time range will be appended, but `/d/` → `/d-solo/` rewrite needs the resolved dashboard URL — paste the `/d/...?...&viewPanel=panel-N` form for full conversion.")
            }
        }

        // --- URL transformation logic ----------------------------------------
        // Rewrites /d/<uid>/<slug>?…&viewPanel=panel-N → /d-solo/<uid>/<slug>?…&panelId=N
        // and appends kiosk / theme / refresh / from-to per the toggles.
        function transformUrl(input) {
            let u = (input || "").trim();
            if (!u) return "";

            // Reject CR/LF/NUL up-front. Operator-trust applies to the KCM
            // surface, but a pasted URL containing a stray \r\n\0 (or a stray
            // `#` mid-querystring) corrupts splitFragment() — `indexOf("#")`
            // returns the first match, so a payload `?a=1\n#kiosk` lands the
            // `kiosk` flag inside the fragment, where Grafana ignores it and
            // operator chrome stays visible. Same threat-class as the
            // auth-interceptor C0-byte reject and the userAgent CR/LF strip.
            if (/[\r\n\0]/.test(u)) {
                console.warn("iframe-plasma[config-urls] rejected pasted URL with CR/LF/NUL");
                return "";
            }

            // 1) /d/ → /d-solo/ (only when we have a viewPanel to convert)
            const viewPanelMatch = u.match(/[?&]viewPanel=panel-(\d+)(?:-clone\d+)?/);
            if (convertDSolo.checked && viewPanelMatch && u.indexOf("/d/") !== -1) {
                u = u.replace("/d/", "/d-solo/");
                u = u.replace(/([?&])viewPanel=panel-\d+(-clone\d+)?(&|$)/, function(_, before, _clone, after) {
                    // Drop the param cleanly without leaving a dangling `?` or `&&`
                    return before === "?" && after === "" ? ""
                         : before === "?" ? "?"
                         : after === "" ? "" : "&";
                });
                u = appendParam(u, "panelId", viewPanelMatch[1]);
            }

            // 2) Time range — strip any existing from/to, then add our preset
            const tr = timeRangeCombo.currentValue;
            if (tr) {
                u = stripParam(u, "from");
                u = stripParam(u, "to");
                u = appendParam(u, "from", "now-" + tr);
                u = appendParam(u, "to", "now");
            }

            // 3) Kiosk — emit just `&kiosk` (no value); kiosk=1 has a Grafana
            //    11.2.x regression (issue #96595). Anchor the match to a
            //    query delimiter so a host like "kiosk.example.com" or a
            //    param like "kioskMode=1" doesn't suppress the insertion.
            //    Route insertion through splitFragment so we don't bleed
            //    the flag past a `#anchor` (appendParam wraps key=value, so
            //    we can't reuse it for a valueless flag).
            if (addKiosk.checked && !/[?&]kiosk(=|&|$)/.test(u)) {
                const [base, frag] = splitFragment(u);
                u = base + (base.indexOf("?") === -1 ? "?" : "&") + "kiosk" + frag;
            }

            // 4) Theme — let the widget runtime substitute ${theme}.
            //    Same delimiter-anchor rationale: don't be fooled by an
            //    unrelated param like "widgetTheme=dark".
            if (addTheme.checked && !/[?&]theme=/.test(u)) {
                u = appendParam(u, "theme", "${theme}");
            }

            // 5) Refresh — omit entirely when off (empty refresh= is buggy per #41329)
            if (addRefresh.checked) {
                u = stripParam(u, "refresh");
                u = appendParam(u, "refresh", refreshInterval.value + "s");
            }

            // 6) hideLogo — strip the "Powered by Grafana" overlay on 12.4+.
            //    Same delimiter-anchor rationale as kiosk/theme above.
            if (addHideLogo.checked && !/[?&]hideLogo=/.test(u)) {
                u = appendParam(u, "hideLogo", "true");
            }

            // 7) hidePanelMenu — internal sentinel (Grafana ignores unknown
            //    params). WebTab.qml's `iframe-plasma-hide-panel-menu` user
            //    script reads window.location.search and injects CSS to
            //    suppress the per-panel kebab when set.
            if (addHidePanelMenu.checked && !/[?&]_ifp_hidePanelMenu=/.test(u)) {
                u = appendParam(u, "_ifp_hidePanelMenu", "1");
            }

            return u;
        }

        // Split off the `#fragment` so the query-string ops below don't
        // bleed params into the hash (appendParam) or eat the anchor
        // (stripParam's [^&]* would consume a trailing #anchor).
        function splitFragment(u) {
            const i = u.indexOf("#");
            return i === -1 ? [u, ""] : [u.substring(0, i), u.substring(i)];
        }
        // Append `key=value`, picking the right separator. Doesn't dedupe.
        function appendParam(u, key, value) {
            const [base, frag] = splitFragment(u);
            const sep = base.indexOf("?") === -1 ? "?" : "&";
            return base + sep + key + "=" + value + frag;
        }
        // Remove all occurrences of &key=… or ?key=… from the query string.
        function stripParam(u, key) {
            let [base, frag] = splitFragment(u);
            // ?key=val&…       → ?…
            base = base.replace(new RegExp("[?]" + key + "=[^&]*(?:&|$)"), function(m) {
                return m.endsWith("&") ? "?" : "";
            });
            // &key=val
            base = base.replace(new RegExp("[&]" + key + "=[^&]*", "g"), "");
            return base + frag;
        }

        function deriveLabel(panelId) {
            if (pastedLabel.text.trim().length > 0) return pastedLabel.text.trim();
            if (panelId) return i18n("Panel %1", panelId);
            return "";
        }

        // Parse a URL's managed params back into the dialog control state.
        // Used when opening in Edit mode so the checkboxes/combos reflect
        // the card's current URL. Anything not matching a managed pattern
        // is preserved verbatim by stripManagedParams + the re-application
        // path in onAccepted.
        function parseSettings(url) {
            const u = String(url || "");
            // Time range — match from=now-<X> shape (the form we emit).
            // Hand-edited URLs with absolute timestamps or now-2h-style
            // offsets that don't match any preset fall back to "no
            // override" (combo head row).
            let tr = "";
            const fromMatch = u.match(/[?&]from=now-([0-9]+(?:[smhdwMy]))(?:&|$|#)/);
            if (fromMatch) {
                const cand = fromMatch[1];
                for (const p of grafanaHelper.timeRangePresets) {
                    if (p.val === cand) { tr = cand; break; }
                }
            }
            // Refresh — extract the seconds value if present + ending in 's'
            // (the form transformUrl emits). Anything else (1m, 30, no
            // refresh) → toggle off, keep SpinBox at last value.
            let refreshOn = false;
            let refreshSec = refreshInterval.value;
            const refMatch = u.match(/[?&]refresh=([0-9]+)s(?:&|$|#)/);
            if (refMatch) {
                refreshOn = true;
                refreshSec = parseInt(refMatch[1], 10);
                if (refreshSec < refreshInterval.from) refreshSec = refreshInterval.from;
                if (refreshSec > refreshInterval.to)   refreshSec = refreshInterval.to;
            }
            return {
                timeRange: tr,
                kiosk:        /[?&]kiosk(=|&|$|#)/.test(u),
                // Any `theme=…` value (literal `light`/`dark` or our
                // ${theme} sentinel) counts as on — saving will normalize
                // to ${theme}, overwriting hand-edited literals.
                theme:        /[?&]theme=/.test(u),
                refreshOn:    refreshOn,
                refreshSec:   refreshSec,
                hideLogo:     /[?&]hideLogo=/.test(u),
                hidePanelMenu:/[?&]_ifp_hidePanelMenu=/.test(u)
            };
        }

        // Strip every param the helper manages so onAccepted can cleanly
        // reapply them per the current toggle state. Anything else
        // (panelId, orgId, var-*, dashboard-specific flags) is preserved.
        function stripManagedParams(url) {
            let u = url;
            u = stripParam(u, "from");
            u = stripParam(u, "to");
            u = stripParam(u, "refresh");
            u = stripParam(u, "theme");
            u = stripParam(u, "hideLogo");
            u = stripParam(u, "_ifp_hidePanelMenu");
            // `kiosk` is a valueless flag — stripParam targets `key=…`,
            // so handle the bare-flag form separately (also covering
            // legacy `kiosk=1` / `kiosk=tv` values just in case).
            const [base, frag] = splitFragment(u);
            let b = base
                .replace(/[?&]kiosk(?==[^&]*)(=[^&]*)?(?=&|$)/g, "")
                .replace(/[?&]kiosk(?=&|$)/g, "");
            // Normalize stray `?&` / trailing `?`/`&` from removals.
            b = b.replace(/\?&/, "?").replace(/&&+/g, "&").replace(/[?&]$/, "");
            return b + frag;
        }

        // Open the dialog in Edit mode for an existing tab card.
        function openForEdit(idx, currentUrl, currentLabel) {
            const s = parseSettings(currentUrl);
            // Pre-fill controls from the parsed settings.
            timeRangeCombo.currentIndex = (function() {
                if (!s.timeRange) return 0;   // head row "(keep URL's range)"
                for (let i = 0; i < grafanaHelper.timeRangePresets.length; i++) {
                    if (grafanaHelper.timeRangePresets[i].val === s.timeRange) return i;
                }
                return 0;
            })();
            addKiosk.checked         = s.kiosk;
            addTheme.checked         = s.theme;
            addRefresh.checked       = s.refreshOn;
            refreshInterval.value    = s.refreshSec;
            addHideLogo.checked      = s.hideLogo;
            addHidePanelMenu.checked = s.hidePanelMenu;
            // Stash the row index + label, then open. Title binding picks
            // up editingLabel; onClosed resets both fields.
            editingLabel = currentLabel || "";
            editingIndex = idx;
            open();
        }

        onAccepted: {
            if (editingIndex >= 0) {
                // Edit mode: rebuild the URL from the row's current value
                // (NOT pastedUrl, which is hidden + empty in this path)
                // by stripping every managed param and reapplying through
                // transformUrl's append pipeline. The /d/→/d-solo/
                // conversion step in transformUrl is gated on
                // convertDSolo.checked, which is hidden+true in Edit
                // mode — but the conversion is a no-op on a URL that's
                // already /d-solo/, and a no-op on /d/ URLs without a
                // viewPanel param (the viewPanel match guards it). So the
                // existing transformUrl handles both cleanly.
                const row = listModel.get(editingIndex);
                const stripped = stripManagedParams(row.url);
                const out = transformUrl(stripped);
                if (!out) return;
                listModel.setProperty(editingIndex, "url", out);
                store.serialize();
                return;
            }
            const out = transformUrl(pastedUrl.text);
            if (!out) return;
            const vpMatch = pastedUrl.text.match(/[?&]viewPanel=panel-(\d+)/);
            const lbl = deriveLabel(vpMatch ? vpMatch[1] : null);
            listModel.append({ label: lbl, url: out, authProfileId: "", thumbMode: "chartOnly", thumbSelector: "", thumbText: "", thumbIconName: "", thumbTimeRange: "", popupMode: "fullPanel", popupSelector: "" });
            store.serialize();
            pastedUrl.text = ""; pastedLabel.text = "";
        }
    }
}
