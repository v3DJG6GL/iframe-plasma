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

    Transition {
        id: chipMenuEnterFade
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300 }
    }

    // The production style (org.kde.desktop) fades a Popup in on open and
    // out on close; the Basic style the tests run under has neither
    // transition, so this one supplies them.
    CyberDropdown {
        id: fadingDropdown
        x: 20
        y: 60
        currentValue: ""
        model: [
            { val: "",   label: "(URL default)" },
            { val: "1h", label: "Last 1 hour" }
        ]
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300 }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 300 }
        }
        property int hits: 0
        onValueSelected: hits++
    }

    TestCase {
        name: "CyberChipDropdown"
        when: windowShown

        function init() {
            chip.visible = true;
            chip.pulseEnabled = false;
            chip.fullRepVisible = false;
            dropdown.enter = null;
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

        // `opened` is false during the enter fade, so a toggle on it
        // re-opened the showing menu instead of closing it.
        function test_chipClick_duringEnterFade_closesMenu() {
            dropdown.enter = chipMenuEnterFade;
            mouseClick(chip);
            verify(dropdown.visible);
            verify(!dropdown.opened);
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

        // Panel popup collapsing hides the window but keeps chip.visible
        // true; fullRepVisible going false is the only signal.
        function test_fullRepHidden_whileOpen_closesMenu() {
            chip.fullRepVisible = true;
            mouseClick(chip);
            tryCompare(dropdown, "opened", true);
            chip.fullRepVisible = false;
            tryCompare(dropdown, "visible", false);
            verify(chip.visible);
        }

        // ============================================================
        //  row click during the open / close fades
        // ============================================================
        function fadingRow(val) {
            const kids = fadingDropdown.contentItem.children;
            for (let i = 0; i < kids.length; ++i)
                if (kids[i].modelData !== undefined && kids[i].modelData.val === val)
                    return kids[i];
            return null;
        }

        // The second click of a double-click lands while the exit fade
        // still shows the rows; it must not select (and reload) again.
        function test_doubleClickRow_duringExitFade_selectsOnce() {
            fadingDropdown.hits = 0;
            fadingDropdown.open();
            tryCompare(fadingDropdown, "opened", true);
            const row = fadingRow("1h");
            verify(row !== null);
            mouseDoubleClickSequence(row);
            tryCompare(fadingDropdown, "visible", false);
            compare(fadingDropdown.hits, 1);
        }

        // `opened` is false during the enter fade as well; a quick
        // chip-then-row pick there must still select and close.
        function test_clickRow_duringEnterFade_selects() {
            fadingDropdown.hits = 0;
            fadingDropdown.open();
            verify(fadingDropdown.visible);
            verify(!fadingDropdown.opened);
            const row = fadingRow("1h");
            verify(row !== null);
            mouseClick(row);
            compare(fadingDropdown.hits, 1);
            tryCompare(fadingDropdown, "visible", false);
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

        function test_pulseChipHidden_stopsAndRestoresIconOpacity() {
            const icon = findChild(chip, "chipIcon");
            chip.fullRepVisible = true;
            chip.pulseEnabled = true;
            tryVerify(function() { return icon.opacity < 1.0; });
            chip.visible = false;
            compare(icon.opacity, 1.0);
            // A still-running pulse would move the opacity again.
            wait(300);
            compare(icon.opacity, 1.0);
        }
    }
}
