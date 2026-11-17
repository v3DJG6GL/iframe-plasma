/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui"

Item {
    id: root
    width: 300
    height: 40

    // The tab labels fall back to KLocalizedContext's i18n(), which a
    // bare test engine does not provide; it finds this through the scope
    // of the document that instantiates the bar.
    function i18n(text, arg) { return text.replace("%1", arg); }

    function makeTabs(n, tag) {
        const out = [];
        for (let i = 0; i < n; ++i)
            out.push({ label: tag + "-" + i, url: "http://tab.example/" + i });
        return out;
    }

    CyberTabBar {
        id: bar
        width: 300
        height: 30
        fullRepVisible: true
    }

    TestCase {
        name: "CyberTabBar"
        when: windowShown

        function tabList() {
            for (let i = 0; i < bar.children.length; ++i)
                if (bar.children[i].orientation !== undefined)
                    return bar.children[i];
            return null;
        }

        function activeTabOnScreen(list) {
            const item = list.itemAtIndex(bar.currentIndex);
            return item !== null
                && item.x >= list.contentX - 0.5
                && item.x + item.width <= list.contentX + list.width + 0.5;
        }

        // ============================================================
        //  auto-scroll after an in-place relabel
        // ============================================================
        function test_inPlaceRelabel_keepsActiveTabOnScreen() {
            bar.tabs = root.makeTabs(10, "t");
            bar.currentIndex = 9;
            const list = tabList();
            verify(list !== null);
            tryVerify(function() { return activeTabOnScreen(list); });

            // The KCM Apply fast path: mutate the labels in place, then
            // bump the serial. The tabs widen, pushing the active tab
            // past the right edge unless the bar scrolls again.
            for (let i = 0; i < bar.tabs.length; ++i)
                bar.tabs[i].label = "a-much-longer-relabelled-title-" + i;
            const widthBefore = list.contentWidth;
            bar.metadataSerial++;
            tryVerify(function() { return list.contentWidth > widthBefore; });
            tryVerify(function() { return activeTabOnScreen(list); });
        }
    }
}
