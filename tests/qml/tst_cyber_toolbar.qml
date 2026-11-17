/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui"

Item {
    id: root
    width: 900
    // Tall enough that an open menu's lower items are inside the window
    // and take the test's clicks.
    height: 300

    // The toolbar calls KLocalizedContext's i18n()/i18nc(), which a bare
    // test engine does not provide; it finds these through the scope of
    // the document that instantiates it.
    function i18n(text) { return text; }
    function i18nc(context, text) { return text; }

    CyberToolbar {
        id: toolbar
        width: 300
        isGrafana: true
        tlsOk: true
    }

    // The production style (org.kde.desktop) fades a Menu in and out; the
    // Basic style the tests run under has neither, so tests install these.
    Transition {
        id: menuEnterFade
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300 }
    }
    Transition {
        id: menuExitFade
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 300 }
    }
    SignalSpy { id: reloadSpy; target: toolbar; signalName: "reloadClicked" }
    SignalSpy { id: openExternalSpy; target: toolbar; signalName: "openExternalClicked" }

    TestCase {
        name: "CyberToolbar"
        when: windowShown

        function init() {
            toolbar.isGrafana = true;
            toolbar.refreshInterval = "";
            toolbar.timeRange = "";
            toolbar.httpStatus = 0;
            toolbar.latencyMs = 0;
            toolbar.fullRepVisible = false;
            toolbar.pickerActive = false;
        }

        // ============================================================
        //  host chip
        // ============================================================
        function test_hostChip_crampedToolbar_staysInsideAndElides() {
            toolbar.width = 300;
            toolbar.host = "a-very-long-dashboard-hostname.monitoring.internal.corp.example-company.com";
            const chip = findChild(toolbar, "hostChip");
            const label = findChild(toolbar, "hostLabel");
            verify(chip !== null);
            verify(label !== null);
            tryVerify(function() {
                return chip.mapToItem(toolbar, chip.width, 0).x <= toolbar.width;
            });
            verify(label.truncated);
        }

        // The squeezed host must keep its tail (the registrable domain),
        // or a phishing host reads as the trusted one it starts with.
        function test_hostChip_crampedToolbar_keepsRegistrableDomain() {
            toolbar.width = 300;
            toolbar.host = "login.grafana.example.com.attacker-phish.net";
            const label = findChild(toolbar, "hostLabel");
            verify(label !== null);
            tryVerify(function() { return label.truncated; });
            compare(label.elide, Text.ElideLeft);
        }

        function test_hostChip_roomyToolbar_showsWholeHost() {
            toolbar.width = 900;
            toolbar.host = "grafana.example.com";
            const chip = findChild(toolbar, "hostChip");
            const label = findChild(toolbar, "hostLabel");
            tryVerify(function() { return chip.width >= chip.implicitWidth; });
            verify(!label.truncated);
            verify(chip.mapToItem(toolbar, chip.width, 0).x <= toolbar.width);
        }

        // ============================================================
        //  HTTP status chip
        // ============================================================
        // Content-sized chips ("custom" range, long latency, "ERR") made a
        // fixed-width threshold show the status chip where the row could
        // not fit it, pushing the TLS/host chip past the toolbar's edge.
        function test_statusChip_neverPushesHostChipPastEdge() {
            toolbar.host = "a-very-long-dashboard-hostname.monitoring.internal.corp.example-company.com";
            toolbar.timeRange = "custom";
            toolbar.refreshInterval = "30s";
            toolbar.httpStatus = 503;
            toolbar.latencyMs = 12345;
            const row = findChild(toolbar, "toolbarRow");
            const chip = findChild(toolbar, "hostChip");
            const status = findChild(toolbar, "statusChip");
            verify(row !== null);
            verify(chip !== null);
            verify(status !== null);
            let shownAt = -1;
            for (let w = 380; w <= 640; ++w) {
                toolbar.width = w;
                verify(waitForItemPolished(row));
                // Inside the row's right margin, not just the toolbar.
                const right = chip.mapToItem(toolbar, chip.width, 0).x;
                verify(right <= toolbar.width - Theme.s2 + 0.5,
                       "host chip right edge " + right + " past toolbar width " + w
                       + " (status chip visible: " + status.visible + ")");
                if (status.visible && shownAt < 0)
                    shownAt = w;
            }
            // Not vacuous: the chip does come back once there is room.
            verify(shownAt > 0);
            toolbar.width = 900;
            verify(status.visible);
            toolbar.httpStatus = 0;
            verify(!status.visible);
        }

        // ============================================================
        //  refresh chip pulse
        // ============================================================
        function test_refreshChip_nonGrafanaPage_hiddenAndNotPulsing() {
            toolbar.host = "grafana.example.com";
            toolbar.fullRepVisible = true;
            toolbar.refreshInterval = "30s";
            const chip = findChild(toolbar, "refreshChip");
            verify(chip !== null);
            verify(chip.visible);
            verify(chip.pulseEnabled);
            // Navigated off the /d/ embed: the chip hides and the pulse
            // must stop with it, though refreshInterval is still "30s".
            toolbar.isGrafana = false;
            verify(!chip.visible);
            verify(!chip.pulseEnabled);
        }

        // ============================================================
        //  toolbar menus
        // ============================================================
        // A collapsed panel popup hides the window, and the collapsing
        // press lands in another window, so CloseOnPressOutside never
        // fires: the menus must close on the full rep going away.
        function test_fullRepHidden_whileReloadMenuOpen_closesMenu() {
            const menu = findChild(toolbar, "reloadMenu");
            verify(menu !== null);
            toolbar.fullRepVisible = true;
            menu.popup();
            tryCompare(menu, "opened", true);
            toolbar.fullRepVisible = false;
            tryCompare(menu, "visible", false);
        }

        // The second click of a double-click lands while the exit fade
        // still shows the items; it must not fire the action again.
        function test_doubleClickReloadItem_duringExitFade_triggersOnce() {
            const menu = findChild(toolbar, "reloadMenu");
            verify(menu !== null);
            menu.exit = menuExitFade;
            reloadSpy.clear();
            menu.popup();
            tryCompare(menu, "opened", true);
            mouseDoubleClickSequence(menu.itemAt(0));
            tryCompare(menu, "visible", false);
            compare(reloadSpy.count, 1);
            menu.exit = null;
        }

        function test_doubleClickOpenExternalItem_duringExitFade_triggersOnce() {
            const menu = findChild(toolbar, "moreMenu");
            verify(menu !== null);
            menu.exit = menuExitFade;
            openExternalSpy.clear();
            menu.popup();
            tryCompare(menu, "opened", true);
            const item = menu.itemAt(3);
            compare(item.text, "Open in default browser");
            mouseDoubleClickSequence(item);
            tryCompare(menu, "visible", false);
            compare(openExternalSpy.count, 1);
            menu.exit = null;
        }

        // `opened` is false during the enter fade too; a click there must
        // still fire, so the guard can't be `opened`.
        function test_clickReloadItem_duringEnterFade_triggers() {
            const menu = findChild(toolbar, "reloadMenu");
            verify(menu !== null);
            menu.enter = menuEnterFade;
            reloadSpy.clear();
            menu.popup();
            verify(menu.visible);
            verify(!menu.opened);
            mouseClick(menu.itemAt(0));
            compare(reloadSpy.count, 1);
            tryCompare(menu, "visible", false);
            menu.enter = null;
        }

        // The second press on the opening button must reach its toggle
        // with the menu still open; the press closing it and the click
        // reopening it left the menu stuck open.
        function test_gearClick_whileOpen_closesMenu() {
            const menu = findChild(toolbar, "moreMenu");
            const btn = findChild(toolbar, "moreBtn");
            verify(menu !== null);
            verify(btn !== null);
            mouseClick(btn);
            tryCompare(menu, "opened", true);
            mouseClick(btn);
            tryCompare(menu, "visible", false);
        }

        function test_caretClick_whileOpen_closesMenuWithoutReload() {
            const menu = findChild(toolbar, "reloadMenu");
            const btn = findChild(toolbar, "caretBtn");
            verify(menu !== null);
            verify(btn !== null);
            reloadSpy.clear();
            mouseClick(btn);
            tryCompare(menu, "opened", true);
            mouseClick(btn);
            tryCompare(menu, "visible", false);
            compare(reloadSpy.count, 0);
        }

        // Opened at the cursor, the menu covered the caret, so a second
        // caret click a few px off landed on "Reload".
        function test_caretClick_opensMenuClearOfCaret() {
            const menu = findChild(toolbar, "reloadMenu");
            const btn = findChild(toolbar, "caretBtn");
            mouseClick(btn);
            tryCompare(menu, "opened", true);
            const bg = menu.background;
            const p = bg.mapFromItem(btn, btn.width / 2, btn.height / 2);
            verify(p.x < 0 || p.y < 0 || p.x >= bg.width || p.y >= bg.height,
                   "menu covers the caret at " + p.x + "," + p.y);
            menu.close();
            tryCompare(menu, "visible", false);
        }

        // The long-press path still opened the menu at the cursor, over
        // the adjacent caret: the caret click meant to close it hit
        // "Reload" instead.
        function test_reloadLongPress_caretClickClosesMenuWithoutReload() {
            const menu = findChild(toolbar, "reloadMenu");
            const reload = findChild(toolbar, "reloadBtn");
            const caret = findChild(toolbar, "caretBtn");
            verify(menu !== null);
            verify(reload !== null);
            reloadSpy.clear();
            mousePress(reload, 11, 6);
            tryCompare(menu, "opened", true, 3000);
            mouseRelease(reload, 11, 6);
            mouseClick(caret);
            tryCompare(menu, "visible", false);
            compare(reloadSpy.count, 0);
        }

        function test_fullRepHidden_whileMoreMenuOpen_closesMenu() {
            const menu = findChild(toolbar, "moreMenu");
            verify(menu !== null);
            toolbar.fullRepVisible = true;
            menu.popup();
            tryCompare(menu, "opened", true);
            toolbar.fullRepVisible = false;
            tryCompare(menu, "visible", false);
        }

        // ============================================================
        //  picker menu item
        // ============================================================
        function test_pickerMenuItem_labelFollowsPickerState() {
            const item = findChild(toolbar, "pickerMenuItem");
            verify(item !== null);
            compare(item.text, "Pick element to crop…");
            // main.qml cancels a running picker on this item.
            toolbar.pickerActive = true;
            compare(item.text, "Cancel element picker");
            toolbar.pickerActive = false;
            compare(item.text, "Pick element to crop…");
        }
    }
}
