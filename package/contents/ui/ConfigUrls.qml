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
                    thumbTimeRange: row.thumbTimeRange || ""
                });
            }
            json = JSON.stringify(arr);
        }
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
                listModel.append({
                    label: entry.label || "",
                    url: entry.url || "",
                    authProfileId: entry.authProfileId || "",
                    thumbMode: mode,
                    thumbSelector: sel,
                    thumbTimeRange: entry.thumbTimeRange || ""
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
                    listModel.append({ label: "", url: "https://", authProfileId: "", thumbMode: "chartOnly", thumbSelector: "", thumbTimeRange: "" });
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
            delegate: Kirigami.AbstractCard {
                required property int index
                required property string label
                required property string url
                required property string authProfileId
                required property string thumbMode
                required property string thumbSelector
                required property string thumbTimeRange

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
                            onEditingFinished: { listModel.setProperty(index, "url", text); store.serialize() }
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
                        }

                        // Thumbnail mode. Applied ONLY to the panel-slot
                        // mini-view, NOT the popup. The presets target
                        // Grafana TimeSeries (uPlot) panels — for Stat /
                        // Gauge / table panels pick `Full panel`, or use
                        // `Custom CSS selector…` with the stable test-contract
                        // [data-testid='data-testid panel content'].
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            QQC.Label {
                                text: i18n("Thumbnail:")
                                color: Kirigami.Theme.disabledTextColor
                            }
                            QQC.ComboBox {
                                id: thumbModeCombo
                                Layout.fillWidth: true
                                readonly property var presets: [
                                    { value: "chartOnly",     display: i18n("Chart only (recommended for Grafana)") },
                                    { value: "chartWithAxes", display: i18n("Chart + axes") },
                                    { value: "fullPanel",     display: i18n("Full panel (no crop)") },
                                    { value: "custom",        display: i18n("Custom CSS selector…") }
                                ]
                                model: presets
                                textRole: "display"
                                valueRole: "value"
                                currentIndex: {
                                    const idx = presets.findIndex(x => x.value === thumbMode);
                                    return idx >= 0 ? idx : 0;
                                }
                                // Arrow form names the signal param `_` so it
                                // doesn't shadow the delegate's `index` —
                                // ComboBox.activated(int index) would otherwise
                                // capture `index` and we'd write to the wrong
                                // listModel row (the activated combo item
                                // index, not the URL-row index).
                                onActivated: _ => {
                                    const v = presets[currentIndex].value;
                                    listModel.setProperty(index, "thumbMode", v);
                                    store.serialize();
                                }
                                QQC.ToolTip.visible: hovered
                                QQC.ToolTip.delay: 600
                                QQC.ToolTip.text: i18n(
                                    "How the panel-slot mini-view crops the page.\n\n"
                                  + "  • Chart only      — uPlot's painted canvas (no axes, no title).\n"
                                  + "  • Chart + axes    — chart plus tick labels.\n"
                                  + "  • Full panel      — entire d-solo view.\n"
                                  + "  • Custom selector — any CSS selector you provide.\n\n"
                                  + "Note: .u-over and .u-under are uPlot's TRANSPARENT overlay layers — they render blank.")
                                NoWheel {}
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

                        // Thumbnail time-range. Empty = "Same as widget"
                        // (use URL's own from/to); a preset like "24h"
                        // rewrites the URL's from/to params for the panel-
                        // slot view ONLY. The popup tab is unaffected.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            QQC.Label {
                                text: i18n("Time range:")
                                color: Kirigami.Theme.disabledTextColor
                            }
                            QQC.ComboBox {
                                id: thumbTimeRangeCombo
                                Layout.fillWidth: true
                                readonly property var presets: [
                                    { value: "auto", display: i18n("Same as widget (use URL's range)") },
                                    { value: "5m",   display: i18n("Last 5 minutes") },
                                    { value: "15m",  display: i18n("Last 15 minutes") },
                                    { value: "30m",  display: i18n("Last 30 minutes") },
                                    { value: "1h",   display: i18n("Last 1 hour") },
                                    { value: "6h",   display: i18n("Last 6 hours") },
                                    { value: "12h",  display: i18n("Last 12 hours") },
                                    { value: "24h",  display: i18n("Last 24 hours") },
                                    { value: "7d",   display: i18n("Last 7 days") },
                                    { value: "30d",  display: i18n("Last 30 days") },
                                    { value: "90d",  display: i18n("Last 90 days") }
                                ]
                                model: presets
                                textRole: "display"
                                valueRole: "value"
                                // Empty string in saved JSON = "auto" (back-compat).
                                currentIndex: {
                                    const v = thumbTimeRange || "auto";
                                    const idx = presets.findIndex(x => x.value === v);
                                    return idx >= 0 ? idx : 0;
                                }
                                // Arrow form avoids signal-param `index`
                                // shadowing the delegate's `index` property
                                // (same trap as the thumbMode combo above).
                                onActivated: _ => {
                                    const v = presets[currentIndex].value;
                                    listModel.setProperty(index, "thumbTimeRange", v);
                                    store.serialize();
                                }
                                QQC.ToolTip.visible: hovered
                                QQC.ToolTip.delay: 600
                                QQC.ToolTip.text: i18n("Override the time range for the panel-slot thumbnail. `Same as widget` keeps the URL's own from/to (popup and thumbnail show the same range). Picking a preset rewrites from=now-<range>&to=now ONLY for the thumbnail's WebEngineView — the popup is unaffected.")
                                NoWheel {}
                            }
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
    QQC.Dialog {
        id: grafanaHelper
        title: i18n("Add from Grafana URL")
        anchors.centerIn: parent
        modal: true
        standardButtons: QQC.Dialog.Cancel | QQC.Dialog.Ok
        width: Math.min(parent.width * 0.9, Kirigami.Units.gridUnit * 42)

        // Time-range presets — see https://grafana.com/docs/grafana/latest/dashboards/time-range-controls/
        readonly property var timeRangePresets: [
            { label: i18n("(keep URL's range)"), value: "" },
            { label: "Last 5 minutes",   value: "5m"  },
            { label: "Last 15 minutes",  value: "15m" },
            { label: "Last 30 minutes",  value: "30m" },
            { label: "Last 1 hour",      value: "1h"  },
            { label: "Last 6 hours",     value: "6h"  },
            { label: "Last 12 hours",    value: "12h" },
            { label: "Last 24 hours",    value: "24h" },
            { label: "Last 7 days",      value: "7d"  },
            { label: "Last 30 days",     value: "30d" },
            { label: "Last 90 days",     value: "90d" }
        ]

        // Don't use `anchors.fill: parent` here — that zeros out the layout's
        // implicitHeight which QQC.Dialog needs to size the content area
        // (otherwise the footer buttons overlap the form).
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Paste any Grafana URL — either a full dashboard `/d/...` URL (with viewPanel=panel-N) or a `/goto/<id>` short link. The helper applies the embedding parameters you select below.")
            }
            QQC.TextField {
                id: pastedUrl
                Layout.fillWidth: true
                placeholderText: "https://grafana.example.com/d/abc/dash?…&viewPanel=panel-5"
            }
            QQC.TextField {
                id: pastedLabel
                Layout.fillWidth: true
                placeholderText: i18n("Label (optional — falls back to panel id)")
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing

                QQC.CheckBox {
                    id: convertDSolo
                    Kirigami.FormData.label: i18n("Single panel:")
                    text: i18n("Convert /d/ to /d-solo/ (panelId from viewPanel)")
                    checked: true
                }
                QQC.ComboBox {
                    id: timeRangeCombo
                    Kirigami.FormData.label: i18n("Default time range:")
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                    model: grafanaHelper.timeRangePresets
                    textRole: "label"
                    valueRole: "value"
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
                    QQC.SpinBox {
                        id: refreshInterval
                        from: 5; to: 3600
                        value: 30
                        enabled: addRefresh.checked
                        textFromValue: (v) => v + " s"
                        NoWheel {}
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
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                type: Kirigami.MessageType.Information
                visible: pastedUrl.text.indexOf("/goto/") !== -1
                text: i18n("This is a `/goto/<id>` short URL. Kiosk / theme / refresh / time range will be appended, but `/d/` → `/d-solo/` rewrite needs the resolved dashboard URL — paste the `/d/...?...&viewPanel=panel-N` form for full conversion.")
            }
        }

        // --- URL transformation logic ----------------------------------------
        // Rewrites /d/<uid>/<slug>?…&viewPanel=panel-N → /d-solo/<uid>/<slug>?…&panelId=N
        // and appends kiosk / theme / refresh / from-to per the toggles.
        function transformUrl(input) {
            let u = (input || "").trim();
            if (!u) return "";

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
            if (addKiosk.checked && !/[?&]kiosk(=|&|$)/.test(u)) {
                u += (u.indexOf("?") === -1 ? "?" : "&") + "kiosk";
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

            return u;
        }

        // Append `key=value`, picking the right separator. Doesn't dedupe.
        function appendParam(u, key, value) {
            const sep = u.indexOf("?") === -1 ? "?" : "&";
            return u + sep + key + "=" + value;
        }
        // Remove all occurrences of &key=… or ?key=… from the query string.
        function stripParam(u, key) {
            // ?key=val&…       → ?…
            u = u.replace(new RegExp("[?]" + key + "=[^&]*(?:&|$)"), function(m) {
                return m.endsWith("&") ? "?" : "";
            });
            // &key=val
            u = u.replace(new RegExp("[&]" + key + "=[^&]*", "g"), "");
            return u;
        }

        function deriveLabel(panelId) {
            if (pastedLabel.text.trim().length > 0) return pastedLabel.text.trim();
            if (panelId) return i18n("Panel %1", panelId);
            return "";
        }

        onAccepted: {
            const out = transformUrl(pastedUrl.text);
            if (!out) return;
            const vpMatch = pastedUrl.text.match(/[?&]viewPanel=panel-(\d+)/);
            const lbl = deriveLabel(vpMatch ? vpMatch[1] : null);
            listModel.append({ label: lbl, url: out, authProfileId: "", thumbMode: "chartOnly", thumbSelector: "", thumbTimeRange: "" });
            store.serialize();
            pastedUrl.text = ""; pastedLabel.text = "";
        }
    }
}
