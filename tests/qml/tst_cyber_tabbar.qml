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

        function cleanup() {
            bar.visible = true;
            bar.statuses = [];
        }

        function findIn(item, pred) {
            if (!item) return null;
            if (pred(item)) return item;
            const kids = item.children || [];
            for (let i = 0; i < kids.length; ++i) {
                const hit = findIn(kids[i], pred);
                if (hit) return hit;
            }
            return null;
        }

        // ============================================================
        //  pulses stop while the bar is hidden
        // ============================================================
        // main.qml hides the bar for a single tab (the default setup)
        // without destroying it: tab 0 stays active with its glow loaded,
        // so an ungated infinite pulse keeps the window repainting for an
        // effect nobody can see.
        function test_hiddenBar_pulsesDoNotAnimate() {
            bar.tabs = root.makeTabs(1, "solo");
            bar.currentIndex = 0;
            bar.statuses = ["loading"];
            const list = tabList();
            verify(list !== null);
            tryVerify(function() { return list.itemAtIndex(0) !== null; });
            const del = list.itemAtIndex(0);
            const loader = findIn(del, function(o) { return o.sourceComponent !== undefined; });
            verify(loader !== null);
            tryVerify(function() { return loader.item !== null; });
            const glow = loader.item;
            const dot = findIn(del, function(o) { return o.text === "●"; });
            verify(dot !== null);

            bar.visible = false;
            wait(50);
            const glowBefore = glow.opacity;
            const dotBefore = dot.opacity;
            wait(400);
            compare(glow.opacity, glowBefore);
            compare(dot.opacity, dotBefore);
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
