/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Tabs strip — Tokyo Night Storm + Hack monospace headers.
 * Inactive labels stay fully readable. Active tab is signalled by colour +
 * weight + an accent-glow underline.
 *
 * The strip is a horizontal ListView so it scrolls (mouse-wheel / drag /
 * flick) when more tabs are configured than fit the popup width. The previous
 * RowLayout laid overflowing tabs past the right edge, where they were
 * unreachable without widening the widget. The active tab is auto-scrolled
 * into view; edge-fade gradients hint that there are off-screen tabs.
 *
 * Per-tab live status is read from `statuses[index]`; values: "loading", "ok",
 * "err", "auth", anything-else → muted dot. The parent (main.qml) keeps that
 * array in sync from per-WebTab load events.
 */
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Effects
import org.kde.kirigami as Kirigami

Rectangle {
    id: bar
    property var tabs: []
    property int currentIndex: 0
    property var statuses: []
    // True while the full popup representation is on screen. The accent-glow
    // animation is infinite, so without this gate it keeps the QtQuick
    // animation timer ticking even when the full rep is hidden (panel-mode
    // popup collapsed, OR desktop-widget mode where root.expanded stays
    // false but the full rep is rendered continuously — main.qml's
    // fullRepVisible is the only correct source, see its docblock).
    property bool fullRepVisible: false
    signal tabSelected(int index)
    signal reloadRequested(int index)

    implicitHeight: Theme.tabHeight
    color: Theme.bgAlt

    // Bring the active tab on-screen — when it changes, when the strip is
    // resized, when the tab set changes, or when the popup (re)opens.
    // `ListView.Contain` only scrolls when the tab is actually off-screen, so
    // an already-visible selection never jumps. Qt.callLater coalesces bursts
    // and lets layout settle before positionViewAtIndex reads geometry.
    function scrollToCurrent() {
        if (bar.currentIndex >= 0 && bar.currentIndex < tabList.count)
            tabList.positionViewAtIndex(bar.currentIndex, ListView.Contain);
    }
    onCurrentIndexChanged: Qt.callLater(scrollToCurrent)
    onFullRepVisibleChanged: if (fullRepVisible) Qt.callLater(scrollToCurrent)
    Component.onCompleted: Qt.callLater(scrollToCurrent)

    // 1px hairline under the tab strip
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.fgMute
    }

    ListView {
        id: tabList
        anchors.fill: parent
        anchors.leftMargin: Theme.s2
        anchors.rightMargin: Theme.s2
        orientation: ListView.Horizontal
        clip: true
        spacing: 0
        // A compact widget strip — no rubber-band overscroll.
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        model: bar.tabs
        currentIndex: bar.currentIndex

        onWidthChanged: Qt.callLater(bar.scrollToCurrent)
        onCountChanged: Qt.callLater(bar.scrollToCurrent)

        delegate: Item {
            id: tabDel
            required property var modelData
            required property int index
            readonly property bool active: index === bar.currentIndex
            readonly property string status: (bar.statuses && bar.statuses[index]) || ""
            readonly property color statusColor: {
                switch (status) {
                    case "loading": return Theme.warning
                    case "ok":      return Theme.success
                    case "err":     return Theme.error
                    case "auth":    return Theme.magenta
                    default:        return Theme.fgMute
                }
            }

            // A ListView sizes horizontal delegates from implicitWidth and
            // does not shrink them — so overflow scrolls instead of clipping.
            height: ListView.view.height
            implicitWidth: contentRow.implicitWidth + Theme.s4 * 2

            // Hover wash
            Rectangle {
                anchors.fill: parent
                anchors.bottomMargin: 2
                color: Theme.surface
                opacity: hoverArea.containsMouse && !tabDel.active ? 0.45 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                radius: 2
            }

            Row {
                id: contentRow
                anchors.centerIn: parent
                spacing: Theme.s2

                // Status dot
                QQC.Label {
                    id: statusDot
                    anchors.verticalCenter: parent.verticalCenter
                    text: "●"   // ●
                    font.family: Theme.fontHeader
                    font.pixelSize: 9
                    color: tabDel.statusColor
                    // Pulsing dot when the tab is loading
                    SequentialAnimation on opacity {
                        // Same popup-gating as the accent-glow MultiEffect
                        // below — without it the infinite pulse keeps the
                        // QtQuick animation timer ticking when the popup
                        // is collapsed (the full rep is hidden, not
                        // destroyed).
                        running: tabDel.status === "loading" && bar.fullRepVisible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.3; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.0; to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                        // "Animation on property" retains its last animated
                        // frame when stopped; without this reset a load that
                        // completes mid-cycle leaves the (now-green) "ok" dot
                        // stuck at opacity 0.3-ish until the next loading
                        // cycle starts.
                        onRunningChanged: if (!running) statusDot.opacity = 1.0
                    }
                }

                QQC.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    // Cap the width so one long title can't make a single tab
                    // dominate the strip; the overflow then elides. Unbounded
                    // inside this Row the `elide` would never trigger.
                    width: Math.min(implicitWidth, Kirigami.Units.gridUnit * 10)
                    text: tabDel.modelData.label || tabDel.modelData.url || i18n("Tab %1", tabDel.index + 1)
                    // PlainText pins the renderer so Qt's mightBeRichText
                    // heuristic can't promote an imported-JSON label like
                    // `<img src=…>` to StyledText and beacon out via the
                    // QQmlEngine NAM (same SSRF class as 5388f75).
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.fontHeader
                    font.pixelSize: 11
                    font.letterSpacing: 0.8
                    font.weight: tabDel.active ? Font.Bold : Font.Medium
                    color: tabDel.active ? Theme.fg : Theme.fgDim
                }
            }

            // Active-tab accent underline + soft pulse glow
            Rectangle {
                id: accentBar
                visible: tabDel.active
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Theme.s3 * 2
                height: 2
                color: Theme.accent
                radius: 1
            }
            // Gate the glow MultiEffect behind a Loader so inactive
            // tabs don't each allocate a GPU FBO + shader pass.  The
            // effect itself was already `visible: tabDel.active` but
            // visible-false items still own their render resources.
            Loader {
                anchors.fill: accentBar
                active: tabDel.active
                sourceComponent: glowComponent
            }

            Component {
                id: glowComponent
                MultiEffect {
                    source: accentBar
                    // Fill the Loader (our parent) — it is itself anchored to
                    // accentBar. Anchoring straight to accentBar fails: from
                    // inside the Component, accentBar is neither parent nor
                    // sibling of this effect.
                    anchors.fill: parent
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 16
                    brightness: 0.15
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: bar.fullRepVisible
                        NumberAnimation { from: 0.55; to: 0.95; duration: 1200; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.95; to: 0.55; duration: 1200; easing.type: Easing.InOutSine }
                    }
                }
            }

            MouseArea {
                id: hoverArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: function(mouse) {
                    if (mouse.button === Qt.MiddleButton) {
                        bar.reloadRequested(tabDel.index);
                    } else {
                        bar.tabSelected(tabDel.index);
                    }
                }
            }
        }
    }

    // Wheel overlay — maps any wheel direction (incl. the normal vertical
    // mouse wheel) to horizontal motion on the tab strip. Sits on top of
    // tabList via z, declines all buttons so tab-click MouseAreas underneath
    // still get clicks, and accepts the wheel so Flickable's own native
    // handling doesn't double-shift contentX past the bounds. We delegate
    // bounds clamping to Flickable.returnToBounds() — manually clamping by
    // contentWidth-width over-shoots when the ListView is still realising
    // delegates at the far edge.
    MouseArea {
        anchors.fill: tabList
        acceptedButtons: Qt.NoButton
        z: tabList.z + 1
        onWheel: (wheel) => {
            const dx = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x
                     : wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y
                     : (wheel.angleDelta.x !== 0 ? wheel.angleDelta.x
                                                 : wheel.angleDelta.y) / 8
            tabList.contentX -= dx
            tabList.returnToBounds()
            wheel.accepted = true
        }
    }

    // Edge-fade affordances — hint that the strip scrolls past the visible
    // edge. A bare Rectangle accepts no pointer input, so clicks/drags fall
    // through to the tab + ListView beneath. `bottomMargin` keeps the 1px
    // hairline crisp in the corners.
    Rectangle {
        anchors {
            left: tabList.left
            top: tabList.top
            bottom: tabList.bottom
            bottomMargin: 1
        }
        width: Theme.s4
        visible: !tabList.atXBeginning
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.bgAlt }
            GradientStop { position: 1.0; color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0) }
        }
    }
    Rectangle {
        anchors {
            right: tabList.right
            top: tabList.top
            bottom: tabList.bottom
            bottomMargin: 1
        }
        width: Theme.s4
        visible: !tabList.atXEnd
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0) }
            GradientStop { position: 1.0; color: Theme.bgAlt }
        }
    }
}
