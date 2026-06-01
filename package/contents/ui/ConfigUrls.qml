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
import "./GrafanaUrl.js" as GrafanaUrl
import "./RowSchema.js" as RowSchema
import "./UrlUtils.js" as UrlUtils

KCM.SimpleKCM {
    id: page

    property alias cfg_urlsJson: store.json
    // No cfg_currentTabIndex alias — the kcfg key is written exclusively
    // by main.qml's setCurrentTab on every tab activation, and this page
    // has no UI for the active tab. The previous alias was dead code,
    // round-tripping the value through this page for no purpose.

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

    // Install the popupWheelForwarder on `combo`'s popup the first time it
    // opens. Per-combo `_popupWheelHooked` is required on the ComboBox itself
    // so the user's `property bool _popupWheelHooked: false` declaration owns
    // the one-shot gate; this helper centralises the connect/create plumbing
    // so each ComboBox only needs the property + a Component.onCompleted call.
    //
    // We connect to `openedChanged` (not `opened`) because in Qt 6.10
    // `QQuickPopup::opened` is a bool PROPERTY, not a signal — calling
    // `.connect(...)` on the boolean value throws
    // `TypeError: Property 'connect' of object false is not a function`
    // on every dialog open. Gate the handler body on `combo.popup.opened`
    // so we only act on the false→true transition and skip the closing
    // edge.
    function _hookComboPopupWheel(combo, scrollTarget) {
        if (!combo || !combo.popup) return
        combo.popup.openedChanged.connect(function() {
            if (!combo.popup.opened) return
            if (combo._popupWheelHooked) return
            popupWheelForwarder.createObject(combo.popup.contentItem,
                                             { combo: combo, scrollTarget: scrollTarget })
            combo._popupWheelHooked = true
        })
    }

    // Write one field on a row and persist. Centralises the
    // setProperty(...)+serialize() two-step that otherwise repeats at every
    // per-field editor below; bulk loops (e.g. onAuthProfilesChanged) still
    // call setProperty directly to amortise a single serialize().
    function _setRowField(idx, field, val) {
        listModel.setProperty(idx, field, val);
        store.serialize();
    }

    // Keyword chip-list helpers. The on-row field stores a JSON-string
    // (see delegate's thumbExcludeKeywords required-property comment),
    // so add/remove parse-mutate-stringify. Duplicate entries are
    // silently dropped (matches the chip-list intuition — adding the
    // same banner text twice does nothing).
    function _parseKeywordsAt(idx) {
        try {
            const v = JSON.parse(listModel.get(idx).thumbExcludeKeywords || "[]");
            return Array.isArray(v) ? v.slice() : [];
        } catch (e) { return []; }
    }
    function _addKeyword(idx, raw) {
        const text = String(raw || "").trim();
        if (text.length === 0) return;
        const cur = _parseKeywordsAt(idx);
        if (cur.indexOf(text) >= 0) return;
        cur.push(text);
        _setRowField(idx, "thumbExcludeKeywords", JSON.stringify(cur));
    }
    function _removeKeyword(idx, text) {
        const cur = _parseKeywordsAt(idx);
        const pos = cur.indexOf(text);
        if (pos < 0) return;
        cur.splice(pos, 1);
        _setRowField(idx, "thumbExcludeKeywords", JSON.stringify(cur));
    }

    // Raised in two situations, both of which must suppress the
    // onJsonChanged → repopulate path:
    //   * repopulate() is loading listModel from store.json (without the
    //     gate, per-row append would re-enter serialize() and clobber the
    //     JSON we're loading FROM).
    //   * serialize() is writing store.json (our own write would otherwise
    //     trigger an immediate clear+append cycle, destroying any
    //     uncommitted text in sibling TextFields whose delegate gets
    //     recycled — see ListModel.clear() semantics).
    // Reset is in a finally so an exception during append/JSON.stringify
    // can't strand the gate at true and silence the page permanently.
    property bool _reloading: false

    // Rebuild listModel from store.json. Used both at startup (in
    // Component.onCompleted) and when store.json changes underneath us —
    // the Backup KCM page writes cfg_urlsJson directly (via a different
    // page-local alias), and without this handler listModel would still
    // carry the pre-import rows; any subsequent edit's serialize() would
    // write the stale model back over the imported value.
    function repopulate() {
        _reloading = true;
        try {
            listModel.clear();
            const arr = JSON.parse(store.json || "[]");
            let mutated = false;
            if (Array.isArray(arr)) {
                for (const entry of arr) {
                    const row = RowSchema.normaliseTabRow(entry);
                    // Detect load-time legacy inference (thumbMode /
                    // popupMode synthesised from selector presence) so the
                    // sanitised display is also persisted. Mirror of
                    // ConfigAuth's synthesized-UUID / autheliaHost gate-
                    // drop pattern: without this, a pre-0.5.0 entry
                    // carrying `thumbSelector` but no `thumbMode` is shown
                    // as "custom" in this KCM, but main.qml:520 + L2076
                    // both fall back to `entry.thumbMode || "chartOnly"`
                    // and `popupMode === "custom"` checks raw, so the
                    // popup slot renders chartOnly and ignores the user's
                    // selector until any other field is touched.
                    if ((entry && entry.thumbMode || "") !== row.thumbMode
                     || (entry && entry.popupMode || "") !== row.popupMode) {
                        mutated = true;
                    }
                    // Adapt the keywords array → JSON string for
                    // ListModel storage (see delegate's required-
                    // property comment); serialize() reverses this.
                    const stored = Object.assign({}, row);
                    stored.thumbExcludeKeywords =
                        JSON.stringify(row.thumbExcludeKeywords || []);
                    listModel.append(stored);
                }
            }
            if (mutated) {
                // Drop the gate just for the inner serialize so the JSON
                // write actually happens, then re-raise it. The outer
                // finally still resets it cleanly.
                _reloading = false;
                store.serialize();
                _reloading = true;
            }
        } catch (e) {
            console.warn("ConfigUrls: parse error", e.message);
        } finally {
            _reloading = false;
        }
    }

    QtObject {
        id: store
        property string json: "[]"

        // Re-sync listModel when the underlying kcfg JSON changes from
        // outside this page (Backup import on the sibling KCM page, or
        // another applet instance writing the same key).
        onJsonChanged: if (!page._reloading) page.repopulate()

        function serialize() {
            if (page._reloading) return;
            const arr = [];
            for (let i = 0; i < listModel.count; i++) {
                const row = listModel.get(i);
                // Keywords ride through the ListModel as a JSON string
                // (see required-property comment in the delegate); decode
                // them to a plain Array here so serialiseTabRow — which owns
                // the canonical on-disk field shape and the keyword/icon/
                // scale-mode sanitisers — receives the contract it expects.
                let kw = [];
                try {
                    const parsed = JSON.parse(row.thumbExcludeKeywords || "[]");
                    if (Array.isArray(parsed)) {
                        kw = parsed;  // _normaliseKeywords filters inside the pure fn
                    }
                } catch (e) { /* corrupt → empty */ }
                // Explicit field copy: listModel.get(i) returns a model
                // object, not a plain JS object, so spread/Object.assign is
                // unreliable. serialiseTabRow re-applies the same defaults
                // and sanitisers as normaliseTabRow, so the two directions
                // cannot drift (tst_serialize_urls.qml pins the parity).
                arr.push(RowSchema.serialiseTabRow({
                    label: row.label,
                    url: row.url,
                    authProfileId: row.authProfileId,
                    thumbMode: row.thumbMode,
                    thumbSelector: row.thumbSelector,
                    thumbText: row.thumbText,
                    thumbIconName: row.thumbIconName,
                    thumbTimeRange: row.thumbTimeRange,
                    thumbScaleMode: row.thumbScaleMode,
                    thumbExcludeKeywords: kw,
                    thumbShowLabel: row.thumbShowLabel,
                    popupMode: row.popupMode,
                    popupSelector: row.popupSelector
                }));
            }
            // Gate the self-write: onJsonChanged would otherwise fire
            // repopulate() against the same data we just serialized,
            // recycling every delegate and wiping any uncommitted text
            // in sibling TextFields on every editingFinished.
            page._reloading = true;
            try {
                json = JSON.stringify(arr);
            } finally {
                page._reloading = false;
            }
        }
    }

    // Heuristic: does this URL look like a Grafana embed? Matches
    // `/d/<uid>/...` (full dashboard) or `/d-solo/<uid>/...` (single
    // panel embed) — both are stable since Grafana 8.x and are what the
    // helper dialog produces or accepts. Used to gate the per-card
    // "Edit Grafana settings…" button so it doesn't appear on non-
    // Grafana tabs (e.g., a Home Assistant dashboard URL).
    // One-line forwarder to UrlUtils.isGrafanaEmbed — keeps the KCM's
    // affordance-gating in lockstep with main.qml's toolbar gating so the
    // two cannot silently diverge (e.g. the fragment-bleed fix at Run #20
    // only had to land in one place).
    function isGrafanaEmbed(u) {
        return UrlUtils.isGrafanaEmbed(u);
    }

    // Human display name for a stored thumbMode token, used by the card
    // header + the Thumbnail section's collapsed summary. `presets` is the
    // delegate-scoped, Grafana-aware `thumbModePresets` array (already i18n'd
    // in QML scope — the lookup MUST stay here, not in a .js singleton, since
    // KCM's engine context has no KLocalizedContext for i18n()). Falls back to
    // the raw token if it isn't in the filtered set (a Grafana-only preset
    // shown on a non-Grafana URL) — same edge the combo's currentIndex handles.
    function _displayForThumbMode(presets, value) {
        for (const p of presets) if (p.value === value) return p.display;
        return value;
    }
    // Human display name for a popupMode token. Static two-entry set mirroring
    // the delegate's popupModePresets; kept as a QML function so the i18n()
    // calls evaluate in KCM's KLocalizedContext.
    function _displayForPopupMode(value) {
        return value === "custom" ? i18n("Custom CSS selector…")
                                  : i18n("Full page (no crop)");
    }

    // Mirror of main.qml's resolveIconSource for the per-card preview.
    // Kept local to the config page so the picker preview renders the
    // right source without requiring a round-trip through Plasmoid.
    // Plain name → theme icon; "bundled:foo" → shipped SVG; "file://..."
    // → straight file URL.
    function resolveIconPreview(name) {
        // DiD allow-list — mirror of main.qml's resolveIconSource. Catches
        // an imported-JSON thumbIconName before the per-card Kirigami.Icon
        // preview can issue an outbound HTTP request for an attacker URL.
        const safe = RowSchema.sanitizeIconName(name);
        if (!safe) return "image-missing";
        if (safe.startsWith("bundled:"))
            return Qt.resolvedUrl("../icons/bundled/" + safe.substring(8) + ".svg");
        return safe;
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
        let changed = false;
        for (let i = 0; i < listModel.count; i++) {
            const apid = listModel.get(i).authProfileId;
            if (apid && !validIds.has(apid)) {
                listModel.setProperty(i, "authProfileId", "");
                changed = true;
            }
        }
        // Flush so the unlinked id doesn't reappear if the user clicks
        // Apply without touching another field on this page.
        if (changed) store.serialize();
    }

    ListModel { id: listModel }

    Component.onCompleted: page.repopulate()

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
                    listModel.append({ label: "", url: "https://", authProfileId: "", thumbMode: "chartOnly", thumbSelector: "", thumbText: "", thumbIconName: "", thumbTimeRange: "", thumbScaleMode: "fit", thumbExcludeKeywords: "[]", thumbShowLabel: false, popupMode: "fullPanel", popupSelector: "" });
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
            // content height to). Attaching at the ListView catches the
            // whole subtree; a per-delegate handler would miss the spacing
            // gaps and any unfilled tail.
            ScrollForwardingWheelHandler {}

            delegate: Kirigami.AbstractCard {
                id: urlRow
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
                // Per-row scale mode for the panel-slot thumbnail —
                // engaged only when thumbMode === "custom". Values:
                // "fit" (aspect-preserving upscale of intrinsically
                // small content), "original" (no size override), or
                // "stretch" (legacy outer-box-fills-viewport).
                required property string thumbScaleMode
                // Live keyword exclusion list (substring or /regex/).
                // CropEngine scans the thumbnail's scope (selector
                // subtree or <body>) and emits hit transitions; the
                // auto-cycle skips this URL while a keyword is on
                // screen. Stored as a JSON-stringified array of strings
                // INSIDE the ListModel because QML's default ListModel
                // (no dynamicRoles) cannot round-trip nested arrays
                // cleanly. parseKeywords()/stringifyKeywords() do the
                // adapter dance at the load/save boundary.
                required property string thumbExcludeKeywords
                // Per-URL opt-IN for the panel-slot label overlay. Each
                // row decides on its own whether to paint the URL's label
                // as a semi-transparent bar across the top of the
                // thumbnail. Default false → no overlay.
                required property bool thumbShowLabel
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

                // Popup-mode presets, hoisted to delegate scope so BOTH the
                // collapsed card-header summary and the popup ComboBox read
                // one source. i18n() lives in QML scope (KCM lacks
                // KLocalizedContext, so it cannot move to a .js singleton).
                readonly property var popupModePresets: [
                    { value: "fullPanel", display: i18n("Full page (no crop)") },
                    { value: "custom",    display: i18n("Custom CSS selector…") }
                ]

                // Concise host+path subtitle for the card header — scheme,
                // query string and fragment stripped (the query is the long,
                // low-signal part that ran off the card). The Thumbnail/Popup
                // mode names are NOT repeated here: they show in their own
                // section rows just below. `url` is attacker-controllable from
                // imported JSON, so the painting Label pins Text.PlainText.
                readonly property string cardSummary: UrlUtils.displayUrl(url)

                width: ListView.view.width

                // Rich card header: index, the tab's label (bold, elided), a
                // muted one-line summary, and the reorder/delete actions. Frees
                // the contentItem to be a single grouped column. `label`/`url`
                // are attacker-controllable → PlainText on every sink (beacon
                // class 0137f84/5388f75/b50b83f).
                header: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    QQC.Label {
                        text: "#" + (index + 1)
                        color: Kirigami.Theme.disabledTextColor
                        Layout.alignment: Qt.AlignTop
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Kirigami.Heading {
                            Layout.fillWidth: true
                            level: 4
                            text: label.length > 0 ? label : i18n("(untitled)")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.italic: label.length === 0
                        }
                        QQC.Label {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: cardSummary
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Kirigami.Theme.disabledTextColor
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 1
                        }
                    }
                    QQC.ToolButton {
                        icon.name: "go-up"
                        enabled: index > 0
                        onClicked: { listModel.move(index, index - 1, 1); store.serialize() }
                        QQC.ToolTip.visible: hovered
                        QQC.ToolTip.delay: 400
                        QQC.ToolTip.text: i18n("Move up")
                    }
                    QQC.ToolButton {
                        icon.name: "go-down"
                        enabled: index < listModel.count - 1
                        onClicked: { listModel.move(index, index + 1, 1); store.serialize() }
                        QQC.ToolTip.visible: hovered
                        QQC.ToolTip.delay: 400
                        QQC.ToolTip.text: i18n("Move down")
                    }
                    QQC.ToolButton {
                        icon.name: "edit-delete"
                        onClicked: { listModel.remove(index); store.serialize() }
                        QQC.ToolTip.visible: hovered
                        QQC.ToolTip.delay: 400
                        QQC.ToolTip.text: i18n("Remove this URL")
                    }
                }

                // Wrap the grouped column in a plain Item. A QtQuick.Layouts
                // ColumnLayout used DIRECTLY as a Card/Control contentItem races
                // the Card's own sizing of its contentItem, producing an
                // implicitHeight binding loop. The loop "settles" by dropping a
                // child's height — which is exactly why expanding one card's
                // section made OTHER cards clip their last (Widget) section. The
                // Item decouples them: Item.implicitHeight follows the column
                // one-way, the Card sizes the Item, and the column sizes itself
                // by width-anchors only. (KDE's AbstractCard docs recommend this
                // very wrap.)
                contentItem: Item {
                    implicitHeight: contentCol.implicitHeight

                    ColumnLayout {
                        id: contentCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: Kirigami.Units.smallSpacing

                    // ---- Source group (always visible) ----
                    Kirigami.Heading {
                        Layout.fillWidth: true
                        level: 5
                        text: i18n("Source")
                    }
                        QQC.TextField {
                            Layout.fillWidth: true
                            placeholderText: i18n("Label (e.g. CPU load)")
                            text: label
                            onEditingFinished: page._setRowField(index, "label", text)
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
                                page._setRowField(index, "url", cleaned);
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
                                onActivated: _ => page._setRowField(index, "authProfileId", rows[currentIndex].id)
                                QQC.ToolTip.visible: hovered && page.authProfiles.length === 0
                                QQC.ToolTip.delay: 400
                                QQC.ToolTip.text: i18n("Create auth profiles on the Authentication tab, then pick one here.")
                                NoWheel {}
                                property bool _popupWheelHooked: false
                                Component.onCompleted: page._hookComboPopupWheel(profileCombo, urlList)
                                // Only the popup delegate Label needs the
                                // explicit Text.PlainText: it defaults to
                                // Text.AutoText, and `rows[].display`
                                // interpolates raw `p.name` + `p.username` from
                                // imported JSON, so AutoText would auto-promote
                                // `<img src=…>` to StyledText → QQmlEngine NAM
                                // beacon (same class as
                                // 0137f84/5388f75/b50b83f/3705728).
                                // The closed-combo display is painted natively
                                // by the org.kde.desktop StyleItem background as
                                // a plain QString (no HTML engine, no beacon),
                                // so a custom contentItem Label is unnecessary —
                                // and an always-visible one draws a second text
                                // layer over the native paint (doubled/blurry
                                // selected text).
                                delegate: QQC.ItemDelegate {
                                    width: profileCombo.width
                                    highlighted: profileCombo.highlightedIndex === index
                                    contentItem: QQC.Label {
                                        text: modelData.display
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
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

                    Kirigami.Separator {
                        Layout.fillWidth: true
                        // Between-group rhythm (KDE FormHeader): more air above
                        // (separating from the previous group), tighter below
                        // (the separator belongs to the section header under it).
                        Layout.topMargin: Kirigami.Units.largeSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                    }

                    // ---- Thumbnail group (collapsible, collapsed by default).
                    // Applied ONLY to the panel-slot mini-view, NOT the popup.
                    // Preset list comes from the delegate-scoped
                    // `thumbModePresets` binding, which filters out the
                    // uPlot-specific chartOnly / chartWithAxes presets when the
                    // URL doesn't look like a Grafana embed. ----
                    CollapsibleSection {
                        Layout.fillWidth: true
                        title: i18n("Thumbnail (panel slot)")
                        summary: page._displayForThumbMode(thumbModePresets, thumbMode)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
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
                                onActivated: _ => page._setRowField(index, "thumbMode", thumbModePresets[currentIndex].value)
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
                                Component.onCompleted: page._hookComboPopupWheel(thumbModeCombo, urlList)
                            }
                        }
                        QQC.TextField {
                            id: customThumbSelector
                            Layout.fillWidth: true
                            visible: thumbMode === "custom"
                            placeholderText: i18n("e.g. .u-wrap, canvas, [data-testid='data-testid panel content']")
                            text: thumbSelector
                            onEditingFinished: page._setRowField(index, "thumbSelector", text)
                            // Swallow Return/Enter so the KCM dialog's
                            // default-button (Apply + Close) doesn't
                            // dismiss the window mid-edit. Same fix as
                            // newKeywordField; numpad Enter raises
                            // Qt.Key_Enter separately from the main
                            // Return key, so both must be handled.
                            Keys.onReturnPressed: (event) => {
                                page._setRowField(index, "thumbSelector", text);
                                event.accepted = true;
                            }
                            Keys.onEnterPressed: (event) => {
                                page._setRowField(index, "thumbSelector", text);
                                event.accepted = true;
                            }
                        }

                        // Scale mode for the matched element. Engaged
                        // only for custom-selector mode; the Grafana
                        // canvas-blit and fullPanel paths handle sizing
                        // implicitly and would be broken by a transform
                        // (uPlot redraw + blurry-pixel artefacts).
                        // See main.qml:applyThumbCrop for the
                        // mode-gated forwarding.
                        RowLayout {
                            Layout.fillWidth: true
                            visible: thumbMode === "custom"
                            spacing: Kirigami.Units.smallSpacing
                            QQC.Label {
                                text: i18n("Scale:")
                                color: Kirigami.Theme.disabledTextColor
                            }
                            QQC.ComboBox {
                                id: scaleModeCombo
                                Layout.fillWidth: true
                                readonly property var presets: [
                                    { value: "fit",      display: i18n("Fit (contain) — upscale smaller content") },
                                    { value: "original", display: i18n("Original size — show element at natural size") },
                                    { value: "stretch",  display: i18n("Stretch (fill) — outer box fills the slot") }
                                ]
                                model: presets
                                textRole: "display"
                                valueRole: "value"
                                currentIndex: {
                                    const idx = presets.findIndex(x => x.value === thumbScaleMode);
                                    return idx >= 0 ? idx : 0;
                                }
                                onActivated: _ => page._setRowField(index, "thumbScaleMode", presets[currentIndex].value)
                                QQC.ToolTip.visible: hovered
                                QQC.ToolTip.delay: 600
                                QQC.ToolTip.text: i18n(
                                    "How the matched element is sized in the panel slot.\n\n"
                                  + "  • Fit       — measure intrinsic size; upscale aspect-preserved\n"
                                  + "                until it fills the slot. Skipped when content\n"
                                  + "                already overflows (let overflow:auto scroll).\n"
                                  + "  • Original  — element rendered at its natural size, top-left\n"
                                  + "                anchored. Siblings still hidden.\n"
                                  + "  • Stretch   — element's outer box sized 100vw × 100vh. Best\n"
                                  + "                for responsive widgets like Grafana panels.")
                                NoWheel {}
                                property bool _popupWheelHooked: false
                                Component.onCompleted: page._hookComboPopupWheel(scaleModeCombo, urlList)
                            }
                        }

                        // Live keyword-exclusion chip list. CropEngine
                        // scans the thumbnail's scope on every observer
                        // tick + 3s safety poll and emits hit transitions
                        // (main.qml setRuntimeExcluded). The cycle skips
                        // this URL while a chip's pattern is on screen.
                        // Visible whenever the row renders live content;
                        // hidden for text / icon / excluded.
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: thumbMode === "chartOnly"
                                  || thumbMode === "chartWithAxes"
                                  || thumbMode === "custom"
                                  || thumbMode === "fullPanel"
                            spacing: Kirigami.Units.smallSpacing
                            QQC.Label {
                                text: i18n("Exclude from rotation when present:")
                                color: Kirigami.Theme.disabledTextColor
                            }
                            // Parsed JS array from the JSON-stringified
                            // ListModel field. Recomputed on every
                            // thumbExcludeKeywords write so add/remove
                            // re-renders the chip list immediately.
                            readonly property var parsedKeywords: {
                                try {
                                    const v = JSON.parse(thumbExcludeKeywords || "[]");
                                    return Array.isArray(v) ? v : [];
                                } catch (e) { return []; }
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.largeSpacing
                                Repeater {
                                    model: parent.parent.parsedKeywords
                                    delegate: Rectangle {
                                        id: chip
                                        // The chip-repeater's index shadows
                                        // urlRow.index, so anything that
                                        // needs the URL-row index must use
                                        // `urlRow.index` explicitly. Without
                                        // that, _removeKeyword/_addKeyword
                                        // operate on the WRONG row (the
                                        // chip's position in the array).
                                        required property int index
                                        required property string modelData
                                        readonly property bool editHover: bodyMA.containsMouse
                                        readonly property bool deleteHover: deleteMA.containsMouse
                                        radius: Kirigami.Units.smallSpacing
                                        color: deleteHover
                                            ? Qt.rgba(Kirigami.Theme.negativeTextColor.r,
                                                      Kirigami.Theme.negativeTextColor.g,
                                                      Kirigami.Theme.negativeTextColor.b, 0.18)
                                            : editHover
                                              ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                        Kirigami.Theme.highlightColor.g,
                                                        Kirigami.Theme.highlightColor.b, 0.32)
                                              : Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                        Kirigami.Theme.highlightColor.g,
                                                        Kirigami.Theme.highlightColor.b, 0.18)
                                        border.color: Kirigami.Theme.highlightColor
                                        border.width: 1
                                        // Height pinned to chipLabel's font line plus ~6px of
                                        // vertical padding each side, so the chip reads as a
                                        // comfortable pill rather than a tight outline. Width =
                                        // label + × box + (8px left pad, ~8px gap before the ×,
                                        // 4px right pad).
                                        implicitHeight: chipLabel.implicitHeight
                                                      + Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
                                        implicitWidth: chipLabel.implicitWidth
                                                     + deleteBtn.implicitWidth
                                                     + Kirigami.Units.largeSpacing * 2
                                                     + Kirigami.Units.smallSpacing
                                        // Edit hint
                                        QQC.ToolTip.visible: bodyMA.containsMouse && !deleteHover
                                        QQC.ToolTip.delay: 600
                                        QQC.ToolTip.text: i18n("Click to edit (loads the pattern into the input below); click × to delete.")
                                        // Edit-zone hit target: covers the
                                        // label, NOT the × button. Clicking
                                        // copies the chip's text into the
                                        // sibling input field and removes
                                        // the chip — the user types over
                                        // their edit and re-adds.
                                        MouseArea {
                                            id: bodyMA
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.right: deleteBtn.left
                                            hoverEnabled: true
                                            cursorShape: Qt.IBeamCursor
                                            onClicked: {
                                                // Safety net: if the user
                                                // had typed something in
                                                // the input before
                                                // clicking, commit it
                                                // first so click-to-edit
                                                // doesn't silently drop
                                                // their work. Duplicate
                                                // entries are a no-op in
                                                // _addKeyword.
                                                if (newKeywordField.text.length > 0
                                                    && newKeywordField.text !== modelData) {
                                                    page._addKeyword(urlRow.index, newKeywordField.text);
                                                }
                                                newKeywordField.text = modelData;
                                                newKeywordField.forceActiveFocus();
                                                newKeywordField.cursorPosition = newKeywordField.text.length;
                                                page._removeKeyword(urlRow.index, modelData);
                                            }
                                        }
                                        // The label sits inside the edit
                                        // zone so its visible bounds match
                                        // the hit area.
                                        QQC.Label {
                                            id: chipLabel
                                            anchors.left: parent.left
                                            anchors.leftMargin: Kirigami.Units.largeSpacing
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData
                                            textFormat: Text.PlainText
                                            color: Kirigami.Theme.textColor
                                            font.family: "monospace"
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        // Delete-zone: a plain × glyph in
                                        // an Item with its own MouseArea.
                                        // Plain text avoids icon-theme
                                        // dependency (the prior
                                        // edit-delete-remove icon name
                                        // isn't on every theme — silent
                                        // miss = the ugly placeholder you
                                        // saw in the screenshot).
                                        Item {
                                            id: deleteBtn
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.rightMargin: Kirigami.Units.smallSpacing
                                            implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                            QQC.Label {
                                                anchors.centerIn: parent
                                                text: "×"
                                                color: chip.deleteHover
                                                    ? Kirigami.Theme.negativeTextColor
                                                    : Kirigami.Theme.disabledTextColor
                                                font.pixelSize: Math.round(chipLabel.font.pixelSize * 1.4)
                                                font.bold: chip.deleteHover
                                            }
                                            MouseArea {
                                                id: deleteMA
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: page._removeKeyword(urlRow.index, modelData)
                                            }
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                QQC.TextField {
                                    id: newKeywordField
                                    Layout.fillWidth: true
                                    placeholderText: i18n("e.g. No active streams  or  /^Error: \\d+/i")
                                    // Swallow the Return/Enter key in the
                                    // TextField scope so it adds the chip
                                    // WITHOUT propagating to the KCM dialog
                                    // (whose default button is Apply &
                                    // Close — Enter would otherwise commit
                                    // the whole dialog and dismiss the
                                    // window). `event.accepted = true`
                                    // stops the bubble. Both onReturnPressed
                                    // and onEnterPressed are needed —
                                    // numeric-keypad Enter raises Qt.Key_Enter
                                    // separately from the main Return key.
                                    Keys.onReturnPressed: (event) => {
                                        if (text.length > 0) {
                                            page._addKeyword(urlRow.index, text);
                                            text = "";
                                        }
                                        event.accepted = true;
                                    }
                                    Keys.onEnterPressed: (event) => {
                                        if (text.length > 0) {
                                            page._addKeyword(urlRow.index, text);
                                            text = "";
                                        }
                                        event.accepted = true;
                                    }
                                }
                                QQC.ToolButton {
                                    text: i18n("Add")
                                    icon.name: "list-add"
                                    display: QQC.AbstractButton.TextBesideIcon
                                    enabled: newKeywordField.text.length > 0
                                    onClicked: {
                                        page._addKeyword(urlRow.index, newKeywordField.text);
                                        newKeywordField.text = "";
                                    }
                                }
                            }
                            QQC.Label {
                                Layout.fillWidth: true
                                text: i18n("Substring match by default (case-insensitive). Wrap in /…/ for regex; trailing flags supported (e.g. /down|offline/i). Click a chip to edit it.")
                                wrapMode: Text.WordWrap
                                color: Kirigami.Theme.disabledTextColor
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 1
                            }
                        }

                        // Per-URL opt-IN for the panel-slot label overlay
                        // (replaces the old Display-tab global toggle + per-
                        // URL "Hide tab label" double-negative). Visible for
                        // every mode whose thumbnail can carry the overlay
                        // (i.e. anything except `excluded`, which has no
                        // slot content at all).
                        QQC.CheckBox {
                            Layout.fillWidth: true
                            visible: thumbMode !== "excluded"
                            text: i18n("Display tab label on this thumbnail")
                            checked: thumbShowLabel
                            onToggled: page._setRowField(index, "thumbShowLabel", checked)
                            QQC.ToolTip.visible: hovered
                            QQC.ToolTip.delay: 600
                            QQC.ToolTip.text: i18n("When enabled, the URL's label is overlaid as a small semi-transparent bar in the top-left of this tab's panel-slot thumbnail. Leave off for tabs whose visual is self-explanatory (a Grafana panel that already paints its own title, a single-icon mode, etc.).")
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
                            onEditingFinished: page._setRowField(index, "thumbText", text)
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
                                    if (picked && picked.length > 0)
                                        page._setRowField(index, "thumbIconName", picked);
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
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                        // Between-group rhythm (KDE FormHeader): more air above
                        // (separating from the previous group), tighter below
                        // (the separator belongs to the section header under it).
                        Layout.topMargin: Kirigami.Units.largeSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                    }

                    // ---- Popup group (collapsible, collapsed by default).
                    // Widget (popup) crop, independent of the thumbnail
                    // selector — same engine (CropEngine.js generic isolation
                    // path), different scope. Use for sites where the popup
                    // should show one panel/card from a larger dashboard.
                    // Grafana presets are thumbnail-only (canvas-pixel-blit
                    // doesn't help an interactive popup), so the popup combo
                    // offers just "Full page" vs "Custom CSS selector". ----
                    CollapsibleSection {
                        Layout.fillWidth: true
                        title: i18n("Widget (popup)")
                        summary: page._displayForPopupMode(popupMode)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            QQC.ComboBox {
                                id: popupModeCombo
                                Layout.fillWidth: true
                                model: popupModePresets
                                textRole: "display"
                                valueRole: "value"
                                currentIndex: {
                                    const idx = popupModePresets.findIndex(x => x.value === popupMode);
                                    return idx >= 0 ? idx : 0;
                                }
                                onActivated: _ => page._setRowField(index, "popupMode", popupModePresets[currentIndex].value)
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
                                Component.onCompleted: page._hookComboPopupWheel(popupModeCombo, urlList)
                            }
                        }
                        QQC.TextField {
                            id: customPopupSelector
                            Layout.fillWidth: true
                            visible: popupMode === "custom"
                            placeholderText: i18n("e.g. .mb-8, [data-testid='dashboard'], #main")
                            text: popupSelector
                            onEditingFinished: page._setRowField(index, "popupSelector", text)
                            // See customThumbSelector for the Enter-swallow
                            // rationale — KCM dialog otherwise closes on
                            // Return.
                            Keys.onReturnPressed: (event) => {
                                page._setRowField(index, "popupSelector", text);
                                event.accepted = true;
                            }
                            Keys.onEnterPressed: (event) => {
                                page._setRowField(index, "popupSelector", text);
                                event.accepted = true;
                            }
                        }
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
        // Guard against the binding evaluating before `parent` is installed
        // — without the null check Qt fires
        // `TypeError: Cannot read property 'width' of null` during early
        // KCM layout. The fallback width matches the upper cap so the math
        // still produces a sensible value when parent isn't ready yet.
        width: Math.min((parent ? parent.width : Kirigami.Units.gridUnit * 42) * 0.9,
                        Kirigami.Units.gridUnit * 42)

        // Pin PlainText on the title-rendering Label. The default QQC.Dialog
        // header is a Label whose `textFormat` is `Text.AutoText`; `editingLabel`
        // is sourced from a tab card's `label` field (set by openForEdit:955),
        // which RowSchema.normaliseTabRow passes verbatim from imported-backup
        // JSON — same attacker-controllable beacon class closed in 0137f84,
        // 5388f75, b50b83f for sibling QQC.Label sinks.
        header: QQC.Label {
            text: grafanaHelper.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.bold: true
            padding: Kirigami.Units.largeSpacing
            visible: text.length > 0
        }

        // Reset all dialog state on any close so the next open() starts fresh.
        // Without this, OK in Edit mode would leave editingIndex set and a
        // subsequent "From Grafana URL…" click would still be in Edit mode.
        // openForEdit imperatively assigns the embed controls below (which
        // permanently breaks their declarative default bindings in QML), so a
        // subsequent Add would inherit the previous Edit's time range / kiosk /
        // theme / refresh / branding state instead of the intended defaults.
        // The paste fields likewise persist across a cancelled or
        // validation-failed Add. Restore every control to its declared default
        // and clear the paste fields here, on the single shared dialog.
        onClosed: {
            editingIndex = -1;
            editingLabel = "";
            pastedUrl.text = "";
            pastedLabel.text = "";
            convertDSolo.checked     = true;
            timeRangeCombo.currentIndex = 7;   // 24h (Last 24 hours)
            addKiosk.checked         = true;
            addTheme.checked         = true;
            addRefresh.checked       = true;
            refreshInterval.value    = 30;
            addHideLogo.checked      = true;
            addHidePanelMenu.checked = true;
        }

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
        // Thin wrappers around GrafanaUrl.js — the pure pipeline lives there
        // so tests/qml/tst_grafana_url_rewrite.qml can drive every branch
        // without instantiating this Dialog tree.
        function transformUrl(input) {
            const out = GrafanaUrl.transform(input, {
                convertDSolo:   convertDSolo.checked,
                timeRange:      timeRangeCombo.currentValue,
                kiosk:          addKiosk.checked,
                theme:          addTheme.checked,
                refresh:        addRefresh.checked,
                refreshSeconds: refreshInterval.value,
                hideLogo:       addHideLogo.checked,
                hidePanelMenu:  addHidePanelMenu.checked,
            });
            if (out === "" && (input || "").trim().length > 0
                && /[\r\n\0]/.test(input)) {
                console.warn("iframe-plasma[config-urls] rejected pasted URL with CR/LF/NUL");
            }
            return out;
        }
        function splitFragment(u) { return GrafanaUrl.splitFragment(u); }
        function appendParam(u, key, value) { return GrafanaUrl.appendParam(u, key, value); }
        function stripParam(u, key) { return GrafanaUrl.stripParam(u, key); }

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
            // Drop the fragment before any existence/value scan. A hash-routed
            // share link whose `#…` carries query-style chars (e.g.
            // `https://g/d-solo/abc?orgId=1#section=2&theme=dark&kiosk`) would
            // otherwise report theme/kiosk/from/refresh from the fragment,
            // mis-pre-fill the Edit dialog, and let onAccepted silently graft
            // those params onto the real query. Same bug-class as Run #15
            // GrafanaUrl.transform fragment-split (8ee8bcd).
            const [u, _frag] = splitFragment(String(url || ""));
            // Time range — match from=now-<X> shape (the form we emit).
            // Hand-edited URLs with absolute timestamps or now-2h-style
            // offsets that don't match any preset fall back to "no
            // override" (combo head row).
            let tr = "";
            const fromMatch = u.match(/[?&]from=now-([0-9]+(?:[smhdwMy]))(?:&|$)/);
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
            const refMatch = u.match(/[?&]refresh=([0-9]+)s(?:&|$)/);
            if (refMatch) {
                refreshOn = true;
                refreshSec = parseInt(refMatch[1], 10);
                if (refreshSec < refreshInterval.from) refreshSec = refreshInterval.from;
                if (refreshSec > refreshInterval.to)   refreshSec = refreshInterval.to;
            }
            return {
                timeRange: tr,
                kiosk:        /[?&]kiosk(=|&|$)/.test(u),
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
            // `from`/`to` are intentionally NOT stripped: when the combo
            // sits on the head row "(keep URL's range)", `transformUrl`
            // passes `timeRange: ""` to GrafanaUrl.transform which then
            // skips its own strip+append block, so any pre-existing
            // from/to MUST survive untouched. The "Last X" preset path
            // is also safe: GrafanaUrl.transform strips and re-appends
            // from/to itself when `opts.timeRange` is truthy.
            u = stripParam(u, "refresh");
            u = stripParam(u, "theme");
            u = stripParam(u, "hideLogo");
            u = stripParam(u, "_ifp_hidePanelMenu");
            // `kiosk` is a valueless flag — stripParam targets `key=val`
            // mandatorily, so handle here. Covers both bare `kiosk` and
            // legacy `kiosk=1`/`kiosk=tv` shapes. Mirrors stripParam's
            // leading-`?` rewrite so `?kiosk[=v]&other=…` collapses to
            // `?other=…` instead of dropping the leading `?`.
            const [base, frag] = splitFragment(u);
            let b = base
                .replace(/[?]kiosk(?:=[^&]*)?(?:&|$)/, function(m) {
                    return m.endsWith("&") ? "?" : "";
                })
                // Lookahead-anchor the terminator: without `(?=&|$)` the optional
                // value group succeeds at zero-length on `M` and `&kiosk` is
                // stripped as a prefix of `&kioskMode=tv`, corrupting the next
                // param's value (`?orgId=1&kioskMode=tv` → `?orgId=1Mode=tv`).
                // Lookahead (not consuming) so adjacent `&kiosk&kiosk` chains
                // both strip via the shared separator. Same regex-terminator
                // class as Runs #4/#9.
                .replace(/[&]kiosk(?:=[^&]*)?(?=&|$)/g, "");
            // Normalize stray trailing `?`/`&` or doubled `&`.
            b = b.replace(/&&+/g, "&").replace(/[?&]$/, "");
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
                page._setRowField(editingIndex, "url", out);
                return;
            }
            const out = transformUrl(pastedUrl.text);
            if (!out) return;
            // Scan post-fragment-split base only — a hash-routed share
            // link's `#…` carrying `&viewPanel=panel-N` would otherwise
            // label the card "Panel N" even though transformUrl (8ee8bcd)
            // correctly fragment-strips so the iframe never loads that
            // panel. Same bug-class as parseSettings (49bf930).
            const [vpBase, _vpFrag] = splitFragment(pastedUrl.text);
            const vpMatch = vpBase.match(/[?&]viewPanel=panel-(\d+)/);
            const lbl = deriveLabel(vpMatch ? vpMatch[1] : null);
            listModel.append({ label: lbl, url: out, authProfileId: "", thumbMode: "chartOnly", thumbSelector: "", thumbText: "", thumbIconName: "", thumbTimeRange: "", thumbScaleMode: "fit", thumbExcludeKeywords: "[]", thumbShowLabel: false, popupMode: "fullPanel", popupSelector: "" });
            store.serialize();
            // Paste fields + control defaults are reset centrally in onClosed
            // (accept() closes the dialog), covering this path and cancel alike.
        }
    }
}
