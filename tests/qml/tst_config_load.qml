/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import "../../package/contents/ui" as Ui

// Load-time behaviour of the URLs and Authentication config pages, created
// the way AppletConfiguration creates them: with every cfg_* as an initial
// property.
Item {
    id: root
    width: 800
    height: 600

    // The pages call KLocalizedContext's i18n family, which a bare test
    // engine does not provide; they find these through the scope of the
    // document that instantiates them.
    function i18n(text) { return text; }
    function i18nc(context, text) { return text; }
    function i18np(singular, plural, n) { return n === 1 ? singular : plural; }
    function i18ncp(context, singular, plural, n) { return n === 1 ? singular : plural; }

    // Depth-first search of a page's object tree (popups live in `data`,
    // not `children`).
    function findObject(obj, pred, seen) {
        seen = seen || [];
        if (!obj || seen.indexOf(obj) !== -1) return null;
        seen.push(obj);
        if (pred(obj)) return obj;
        for (const key of ["data", "children", "contentItem"]) {
            const v = obj[key];
            const list = (v && v.length !== undefined) ? v : (v ? [v] : []);
            for (let i = 0; i < list.length; i++) {
                const hit = findObject(list[i], pred, seen);
                if (hit) return hit;
            }
        }
        return null;
    }

    Component { id: urlsPage; Ui.ConfigUrls {} }
    Component { id: authPage; Ui.ConfigAuth {} }

    SignalSpy { id: changedSpy; signalName: "configurationChanged" }

    TestCase {
        name: "ConfigLoad"
        when: windowShown

        readonly property string cleanUrlRow: JSON.stringify([{
            label: "", url: "https://x", enabled: true, authProfileId: "",
            thumbMode: "chartOnly", thumbSelector: "", thumbText: "",
            thumbIconName: "", thumbTimeRange: "", thumbScaleMode: "fit",
            thumbExcludeKeywords: [], thumbShowLabel: false,
            excludeFromRotation: false, popupMode: "fullPanel", popupSelector: ""
        }])

        function _open(comp, props) {
            const page = createTemporaryObject(comp, root, props);
            verify(page !== null);
            changedSpy.clear();
            changedSpy.target = page;
            return page;
        }

        // A load that re-persists a normalised row must mark the page
        // changed: the dialog greys Apply out after creating the page, so
        // Cancel or Close dropped the rewrite without a prompt.
        function test_urls_normalisingLoad_marksPageChanged() {
            const page = _open(urlsPage, {
                cfg_urlsJson: '[{"url":"https://x","thumbMode":"excluded"}]' });
            verify(page.cfg_urlsJson.indexOf('"thumbMode":"fullPanel"') !== -1);
            tryCompare(changedSpy, "count", 1);
        }
        function test_urls_cleanLoad_staysUnchanged() {
            const page = _open(urlsPage, { cfg_urlsJson: cleanUrlRow });
            compare(page.cfg_urlsJson, cleanUrlRow);
            wait(50);
            compare(changedSpy.count, 0);
        }
        function test_auth_normalisingLoad_marksPageChanged() {
            const page = _open(authPage, {
                cfg_authProfilesJson: '[{"id":"p","authType":"basic","username":1234}]' });
            verify(page.cfg_authProfilesJson.indexOf('"username":""') !== -1);
            tryCompare(changedSpy, "count", 1);
        }
        function test_auth_cleanLoad_staysUnchanged() {
            const clean = JSON.stringify([{ id: "p", name: "N", authType: "basic",
                username: "u", autheliaHost: "", preempt: false }]);
            const page = _open(authPage, { cfg_authProfilesJson: clean });
            wait(50);
            compare(changedSpy.count, 0);
        }
    }

    // The Grafana helper dialog on the URLs page.
    TestCase {
        name: "ConfigUrlsGrafanaHelper"
        when: windowShown

        function _helper(page) {
            const d = root.findObject(page, o => o.editingIndex !== undefined
                                    && o.standardButton !== undefined);
            verify(d !== null);
            return d;
        }
        function _pasteField(dialog) {
            const f = root.findObject(dialog.contentItem, o => typeof o.placeholderText === "string"
                && o.placeholderText.indexOf("grafana.example.com/d/") !== -1);
            verify(f !== null);
            return f;
        }
        function _errorShown(dialog) {
            return root.findObject(dialog.contentItem, o => o.type === Kirigami.MessageType.Error
                && o.visible === true && typeof o.text === "string") !== null;
        }

        // A URL wrapped across two lines made OK a silent no-op: the dialog
        // closed and the paste was gone, with no row added and no message.
        function test_pasteWithInteriorLineBreak_blocksOkWithError() {
            const page = createTemporaryObject(urlsPage, root, { cfg_urlsJson: "[]" });
            const dialog = _helper(page);
            dialog.open();
            tryCompare(dialog, "opened", true);
            const field = _pasteField(dialog);
            field.text = "https://g/d/abc?orgId=1&\nviewPanel=panel-5";
            verify(_errorShown(dialog));
            compare(dialog.standardButton(Dialog.Ok).enabled, false);
            field.text = "https://g/d/abc?orgId=1&viewPanel=panel-5\n";
            verify(!_errorShown(dialog));
            compare(dialog.standardButton(Dialog.Ok).enabled, true);
            dialog.close();
        }

        // A fixed per-URL thumbnail range (set with the inline combo of
        // 0.4.x/0.5.0) overrides the URL's from/to, and nothing on the page
        // could clear it: the range picked here never reached the thumbnail.
        function test_editAccept_clearsFixedThumbRange() {
            const url = "https://g/d-solo/abc/dash?orgId=1&panelId=5&from=now-1h&to=now";
            const page = createTemporaryObject(urlsPage, root, {
                cfg_urlsJson: JSON.stringify([{ url: url, label: "P", thumbTimeRange: "7d" }]) });
            compare(JSON.parse(page.cfg_urlsJson)[0].thumbTimeRange, "7d");
            const dialog = _helper(page);
            dialog.openForEdit(0, url, "P");
            tryCompare(dialog, "opened", true);
            dialog.accept();
            const row = JSON.parse(page.cfg_urlsJson)[0];
            compare(row.thumbTimeRange, "");
            verify(row.url.indexOf("/d-solo/abc/") !== -1);
        }
    }

    // The Authentication page's per-profile cards.
    TestCase {
        name: "ConfigAuthCards"
        when: windowShown

        // The widget applies a None profile's Authelia host (overlay plus
        // forced popup on every redirect there), but the card hid the
        // field, so a host set before switching to None could not be
        // cleared.
        function test_noneProfile_showsAutheliaHost() {
            const page = createTemporaryObject(authPage, root, {
                cfg_authProfilesJson: JSON.stringify([{ id: "p", name: "SSO",
                    authType: "none", username: "", autheliaHost: "auth.example.com",
                    preempt: false }]) });
            verify(page !== null);
            let field = null;
            tryVerify(() => {
                field = root.findObject(page, o => o.text === "auth.example.com"
                                      && typeof o.placeholderText === "string");
                return field !== null;
            });
            verify(field.parent.visible);
        }
    }
}
