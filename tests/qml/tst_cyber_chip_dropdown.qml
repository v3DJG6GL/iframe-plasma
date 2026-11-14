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
    }
}
