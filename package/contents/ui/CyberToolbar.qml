/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Toolbar sitting above the tab strip. Surfaces:
 *   reload (split button - click for soft reload, dropdown for the menu)
 *   [200 OK . 47ms]      HTTP status + nav timing of the active tab
 *   [lock] host.example.com  TLS-and-host chip
 *
 * The widget owns no state - properties are bound from main.qml to the
 * currently-active tab; signals are emitted up to main.qml which knows the
 * concrete WebEngineView + cookie store.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import org.kde.kirigami as Kirigami
import "sanitize.js" as Sanitize

Rectangle {
    id: tb

    // Inbound: bound from active tab in main.qml.
    property string host: ""
    property bool   tlsOk: false

    // `host` is derived from page-controlled `webview.url` (via
    // `new URL(...).host` in WebTab.currentHost) - a hostile redirect to
    // a host containing a Right-to-Left Override (U+202E) survives JS
    // URL parsing, and Qt's text engine then applies the Unicode bidi
    // algorithm to the QQC.Label below, rendering e.g. the bytes
    // "login<U+202E>gnafarg.com" as "login.grafana.com" on screen and
    // spoofing the operator's primary TLS-trust signal. Shared strip in
    // sanitize.js covers bidi/format/C0+C1 control code points.
    readonly property string hostSafe: Sanitize.strip(host)
    property int    httpStatus: 0       // 0 -> unknown / not yet captured
    property int    latencyMs: 0
    property bool   loading: false
    // Active tab's current Grafana time range (e.g. "24h", "custom", or "")
    // and refresh interval (e.g. "30s" or ""). Drive the dropdown selection.
    property string timeRange: ""
    property string refreshInterval: ""

    signal reloadClicked()
    signal hardReloadClicked()
    signal clearCookiesClicked()
    signal openExternalClicked()
    // Emitted when user picks a value from one of the dropdowns. main.qml
    // routes these to the active tab's setTimeRange / setRefreshInterval.
    signal selectTimeRange(string range)        // "24h" / "" / "custom"
    signal selectRefreshInterval(string interval)  // "30s" / "off"
    // Activate the click-to-pick element overlay in the live view —
    // main.qml routes this to the active tab's startPicker().
    signal pickElementClicked()

    implicitHeight: Theme.toolbarHeight
    color: Theme.bg

    // 1px hairline along the bottom - visually separates from CyberTabBar below
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.fgMute
        opacity: 0.6
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.s2
        anchors.rightMargin: Theme.s2
        spacing: Theme.s2

        // --- Reload split button -------------------------------------------
        Row {
            spacing: 0
            Layout.alignment: Qt.AlignVCenter
            // Primary action — pin its width so a cramped toolbar never
            // shrinks it (RowLayout would otherwise collapse it toward 0).
            Layout.minimumWidth: implicitWidth

            QQC.AbstractButton {
                id: reloadBtn
                width: 22; height: 20
                hoverEnabled: true
                onClicked: tb.reloadClicked()
                onPressAndHold: reloadMenu.popup()
                QQC.ToolTip.text: i18n("Reload (Ctrl+R) — long-press for more")
                QQC.ToolTip.visible: hovered
                QQC.ToolTip.delay: 600
                contentItem: Rectangle {
                    color: reloadBtn.hovered ? Theme.surfaceHi : Theme.surface
                    border.color: Theme.fgMute
                    border.width: 1
                    radius: 2
                    QQC.Label {
                        anchors.centerIn: parent
                        text: tb.loading ? "◠" : "↻"
                        color: Theme.accent
                        font.family: Theme.fontHeader
                        font.pixelSize: 13
                        font.bold: true
                        RotationAnimation on rotation {
                            running: tb.loading
                            loops: Animation.Infinite
                            from: 0; to: 360; duration: 900
                        }
                    }
                }
            }

            QQC.AbstractButton {
                id: caretBtn
                width: 14; height: 20
                hoverEnabled: true
                onClicked: reloadMenu.popup()
                contentItem: Rectangle {
                    color: caretBtn.hovered ? Theme.surfaceHi : Theme.surface
                    border.color: Theme.fgMute
                    border.width: 1
                    radius: 2
                    QQC.Label {
                        anchors.centerIn: parent
                        text: "▾"
                        color: Theme.fgDim
                        font.family: Theme.fontHeader
                        font.pixelSize: 10
                    }
                }
            }
        }

        QQC.Menu {
            id: reloadMenu
            QQC.MenuItem {
                text: i18n("Reload   (Ctrl+R)")
                icon.name: "view-refresh"
                onTriggered: tb.reloadClicked()
            }
            QQC.MenuItem {
                text: i18n("Hard reload — bypass cache   (Ctrl+Shift+R)")
                icon.name: "view-refresh-symbolic"
                onTriggered: tb.hardReloadClicked()
            }
            QQC.MenuItem {
                text: i18n("Clear HTTP cache && reload")
                icon.name: "edit-clear-history"
                onTriggered: tb.clearCookiesClicked()
            }
            QQC.MenuSeparator {}
            QQC.MenuItem {
                text: i18n("Open in default browser")
                icon.name: "internet-web-browser"
                onTriggered: tb.openExternalClicked()
            }
        }

        // --- Time-range chip dropdown ---------------------------------------
        CyberChipDropdown {
            id: timeChip
            visible: tb.host.length > 0
            icon: "⏱"
            value: tb.timeRange
            emptyText: "—"
            tooltipText: i18n("Time range — overrides URL's from/to (session only)")
            menu: timeMenu
        }

        CyberDropdown {
            id: timeMenu
            parent: timeChip
            x: 0
            y: timeChip.height + 2
            currentValue: tb.timeRange
            // Inline preset list (was a shared GrafanaTimeRanges singleton,
            // but `i18n()` is not resolved inside a QtObject singleton when
            // the KCM engine loads ConfigUrls — the singleton's QML scope
            // doesn't inherit KLocalizedContext there, so its `presets`
            // property evaluated to a ReferenceError and the dropdown
            // rendered empty in the config dialog).
            model: [
                { val: "",    label: i18nc("time range: keep URL's existing from/to", "(URL default)") },
                { val: "5m",  label: i18n("Last 5 minutes")  },
                { val: "15m", label: i18n("Last 15 minutes") },
                { val: "30m", label: i18n("Last 30 minutes") },
                { val: "1h",  label: i18n("Last 1 hour")     },
                { val: "6h",  label: i18n("Last 6 hours")    },
                { val: "12h", label: i18n("Last 12 hours")   },
                { val: "24h", label: i18n("Last 24 hours")   },
                { val: "7d",  label: i18n("Last 7 days")     },
                { val: "30d", label: i18n("Last 30 days")    },
                { val: "90d", label: i18n("Last 90 days")    }
            ]
            onValueSelected: (v) => tb.selectTimeRange(v)
        }

        // --- Refresh-interval chip dropdown ---------------------------------
        CyberChipDropdown {
            id: refreshChip
            visible: tb.host.length > 0
            icon: "⟳"   // distinct from the reload button's ↻
            iconPixelSize: 10
            iconColor: tb.refreshInterval.length > 0 ? Theme.success : Theme.fgDim
            value: tb.refreshInterval
            emptyText: i18nc("refresh off", "off")
            tooltipText: i18n("Auto-refresh interval (session only)")
            menu: refreshMenu
            // Pulse the icon while auto-refresh is on (and chip is shown).
            pulseEnabled: tb.host.length > 0 && tb.refreshInterval.length > 0
        }

        CyberDropdown {
            id: refreshMenu
            parent: refreshChip
            x: 0
            y: refreshChip.height + 2
            currentValue: tb.refreshInterval
            model: [
                { val: "",    label: i18nc("refresh off", "Off (no auto-refresh)") },
                { val: "5s",  label: i18n("Every 5 seconds")   },
                { val: "30s", label: i18n("Every 30 seconds")  },
                { val: "1m",  label: i18n("Every 1 minute")    },
                { val: "5m",  label: i18n("Every 5 minutes")   },
                { val: "30m", label: i18n("Every 30 minutes")  }
            ]
            onValueSelected: (v) => tb.selectRefreshInterval(v)
        }

        // --- Pick-element button --------------------------------------------
        // Activates the in-page click-to-pick overlay so the user can
        // visually select an element instead of authoring a CSS selector
        // by hand. Result is sent back via the active tab's
        // selectorPicked signal — main.qml prompts for scope (thumbnail
        // vs widget) and writes to the URL config.
        // Mirror reloadBtn's sizing: hardcoded width/height with zero
        // padding so the contentItem Rectangle fills the AbstractButton
        // box. Layout.preferredWidth + QQC2's default 6 px padding
        // shrinks the Rectangle and pushes the centred ⌖ glyph off-axis.
        QQC.AbstractButton {
            id: pickBtn
            width: 22; height: 20
            padding: 0
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: width
            Layout.preferredHeight: height
            visible: tb.host.length > 0
            hoverEnabled: true
            onClicked: tb.pickElementClicked()
            QQC.ToolTip.text: i18n("Pick an element to crop to — click any element in the page, Esc to cancel")
            QQC.ToolTip.visible: hovered
            QQC.ToolTip.delay: 600
            contentItem: Rectangle {
                color: pickBtn.hovered ? Theme.surfaceHi : Theme.surface
                border.color: Theme.fgMute
                border.width: 1
                radius: 2
                QQC.Label {
                    anchors.centerIn: parent
                    text: "⌖"
                    color: Theme.accent
                    font.family: Theme.fontHeader
                    font.pixelSize: 13
                    font.bold: true
                }
            }
        }

        // --- HTTP status chip ----------------------------------------------
        Rectangle {
            // Informational only — the first chip to drop when the popup is
            // too narrow to also fit the reload control + both dropdowns.
            visible: tb.httpStatus > 0 && tb.width >= Kirigami.Units.gridUnit * 22
            Layout.preferredHeight: Theme.chipHeight
            Layout.minimumWidth: implicitWidth
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: statusLabel.implicitWidth + Theme.chipPadding * 2
            color: Theme.surface
            border.color: Theme.fgMute
            border.width: 1
            radius: 2
            QQC.Label {
                id: statusLabel
                anchors.centerIn: parent
                text: "[" + tb.httpStatus + " "
                      + (tb.httpStatus < 400
                            ? i18nc("HTTP status 2xx/3xx indicator in toolbar status chip", "OK")
                            : i18nc("HTTP status 4xx/5xx indicator in toolbar status chip", "ERR"))
                      + (tb.latencyMs > 0 ? " · " + tb.latencyMs + "ms" : "") + "]"
                font.family: Theme.fontBody
                font.pixelSize: 9
                color: tb.httpStatus < 400 ? Theme.success : Theme.error
            }
        }

        Item { Layout.fillWidth: true }

        // --- Hostname + TLS chip -------------------------------------------
        Rectangle {
            id: hostChip
            visible: tb.host.length > 0
            Layout.preferredHeight: Theme.chipHeight
            Layout.alignment: Qt.AlignVCenter
            // Small floor — keep the TLS glyph + a few host chars legible even
            // on the narrowest popup; the label below elides to whatever width
            // RowLayout grants instead of overflowing the chip / the toolbar.
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            // Derived from the label's *natural* width (implicitWidth), never
            // its laid-out width — hostLabel.width depends on hostChip.width,
            // so feeding it back here would form a binding loop.
            implicitWidth: lockGlyph.implicitWidth + hostRow.spacing
                           + hostLabel.implicitWidth + Theme.chipPadding * 2
            color: Theme.surface
            border.color: Theme.fgMute
            border.width: 1
            radius: 2
            Row {
                id: hostRow
                anchors.centerIn: parent
                spacing: 4
                QQC.Label {
                    id: lockGlyph
                    text: tb.tlsOk ? "🔒" : "⚠"
                    font.pixelSize: 9
                    color: tb.tlsOk ? Theme.success : Theme.warning
                }
                QQC.Label {
                    id: hostLabel
                    // hostSafe strips bidi/format/control chars - see top of file.
                    // Width tracks the chip's granted size so a long hostname
                    // elides rather than overflowing the chip or the toolbar.
                    width: Math.min(implicitWidth,
                                    Math.max(0, hostChip.width - lockGlyph.implicitWidth
                                                - hostRow.spacing - Theme.chipPadding * 2))
                    text: tb.hostSafe
                    elide: Text.ElideRight
                    font.family: Theme.fontBody
                    font.pixelSize: 9
                    color: Theme.fg
                }
            }
        }
    }
}
