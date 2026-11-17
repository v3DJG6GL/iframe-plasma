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
    height: 60

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

    TestCase {
        name: "CyberToolbar"
        when: windowShown

        function init() {
            toolbar.isGrafana = true;
            toolbar.refreshInterval = "";
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
