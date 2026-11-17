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
        //  far jump across tabs of mixed width
        // ============================================================
        function test_farJump_mixedWidths_scrollsActiveTabFullyOnScreen() {
            // Short labels first, long ones after: the ListView's extent
            // estimate for the not-yet-created far delegates is too small,
            // so a single positionViewAtIndex under-scrolls.
            bar.tabs = [
                { label: "Home", url: "http://tab.example/0" },
                { label: "Logs", url: "http://tab.example/1" },
                { label: "UPS", url: "http://tab.example/2" },
                { label: "Network Traffic Overview", url: "http://tab.example/3" },
                { label: "Kubernetes Cluster Health", url: "http://tab.example/4" },
                { label: "Node Exporter Full Dashboard", url: "http://tab.example/5" },
                { label: "Proxmox VE Summary", url: "http://tab.example/6" },
                { label: "Home Assistant Energy", url: "http://tab.example/7" }
            ];
            bar.currentIndex = 0;
            const list = tabList();
            verify(list !== null);
            list.contentX = 0;
            tryVerify(function() { return activeTabOnScreen(list); });

            bar.currentIndex = 7;
            tryVerify(function() { return activeTabOnScreen(list); });
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
