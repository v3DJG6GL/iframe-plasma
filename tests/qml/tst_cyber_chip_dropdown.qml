/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui"

Item {
    id: root
    width: 400
    height: 300

    // Wired the way CyberToolbar wires its time-range / refresh chips.
    CyberChipDropdown {
        id: chip
        x: 20
        y: 20
        width: implicitWidth
        height: 20
        icon: "⏱"
        value: "1h"
        menu: dropdown
    }

    CyberDropdown {
        id: dropdown
        parent: chip
        x: 0
        y: chip.height + 2
        currentValue: "1h"
        model: [
            { val: "",   label: "(URL default)" },
            { val: "1h", label: "Last 1 hour" }
        ]
    }

    TestCase {
        name: "CyberChipDropdown"
        when: windowShown

        function init() {
            chip.visible = true;
            chip.pulseEnabled = false;
            chip.fullRepVisible = false;
            dropdown.close();
            tryCompare(dropdown, "visible", false);
        }

        // ============================================================
        //  open / close
        // ============================================================
        function test_chipClick_whileOpen_closesMenu() {
            mouseClick(chip);
            tryCompare(dropdown, "opened", true);
            mouseClick(chip);
            tryCompare(dropdown, "visible", false);
        }

        function test_pressElsewhere_closesMenu() {
            mouseClick(chip);
            tryCompare(dropdown, "opened", true);
            mouseClick(root, root.width - 10, root.height - 10);
            tryCompare(dropdown, "visible", false);
        }

        function test_chipHidden_whileOpen_closesMenu() {
            mouseClick(chip);
            tryCompare(dropdown, "opened", true);
            chip.visible = false;
            tryCompare(dropdown, "visible", false);
        }

        // ============================================================
        //  icon pulse
        // ============================================================
        function test_pulseStopped_restoresIconOpacity() {
            const icon = findChild(chip, "chipIcon");
            verify(icon !== null);
            chip.fullRepVisible = true;
            chip.pulseEnabled = true;
            tryVerify(function() { return icon.opacity < 1.0; });
            chip.pulseEnabled = false;
            compare(icon.opacity, 1.0);
        }

        function test_pulseHiddenWithFullRep_restoresIconOpacity() {
            const icon = findChild(chip, "chipIcon");
            chip.fullRepVisible = true;
            chip.pulseEnabled = true;
            tryVerify(function() { return icon.opacity < 1.0; });
            chip.fullRepVisible = false;
            compare(icon.opacity, 1.0);
        }
    }
}
