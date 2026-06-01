// SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Generic, reusable disclosure section for the KCM config cards. A clickable,
// keyboard-accessible header (caret + bold title + muted summary-when-
// collapsed) toggles the visibility of arbitrary child content.
//
// View-state ONLY: `expanded` is not persisted and may reset when a ListView
// recycles the delegate that hosts this section — that's acceptable, because
// no data flows through this component; every edit inside the body still
// commits via the host's own _setRowField/serialize path.
//
// Standard Kirigami (Theme.* roles, system fonts) — deliberately does NOT use
// the widget-only cyber Theme singleton, so the config page stays native to
// KDE System Settings. Min target Plasma 6.0: no kirigami-addons, no
// Kirigami.Form.
//
// Usage — children are reparented into the collapsible body:
//   CollapsibleSection {
//       title: i18n("Thumbnail")
//       summary: someModeDisplayString   // shown only while collapsed
//       QQC.ComboBox { ... }
//       QQC.TextField { ... }
//   }
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    // --- Public API ---
    property string title: ""
    // Muted one-liner painted at the right of the header while collapsed
    // (e.g. the current mode's display name). Callers may derive this from
    // attacker-controllable data, so the sink below pins Text.PlainText.
    property string summary: ""
    property bool expanded: false   // collapsed by default
    // Children land in the collapsible body. `.data` (not `.children`) so
    // non-visual items (Dialogs, Bindings) reparent cleanly too.
    default property alias content: contentHolder.data

    // 4px between the header and its content — within-group tightness (HIG).
    spacing: Kirigami.Units.smallSpacing

    // --- Clickable, focusable disclosure header ---
    // AbstractButton gives Space/Enter activation and a focus stop for free;
    // mirrors the AbstractButton usage in CyberToolbar.qml. Padding follows
    // KDE's FormHeader/ListSectionHeader rhythm (12px top of breathing room,
    // 8px each side of the click target) so the row never feels cramped.
    QQC.AbstractButton {
        id: headerButton
        Layout.fillWidth: true
        topPadding: Kirigami.Units.largeSpacing
        bottomPadding: Kirigami.Units.largeSpacing
        leftPadding: Kirigami.Units.smallSpacing
        rightPadding: Kirigami.Units.smallSpacing
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        Accessible.role: Accessible.Button
        Accessible.name: root.title
        Accessible.description: root.expanded
            ? i18n("Expanded. Activate to collapse.")
            : i18n("Collapsed. Activate to expand.")
        onClicked: root.expanded = !root.expanded

        // Subtle hover / focus wash. Qt.rgba over a theme role (the
        // nonexistent Qt.alpha() is intentionally avoided) — same tinting
        // idiom as the keyword chips in ConfigUrls.qml.
        background: Rectangle {
            radius: Kirigami.Units.smallSpacing
            color: headerButton.activeFocus
                ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                          Kirigami.Theme.highlightColor.g,
                          Kirigami.Theme.highlightColor.b, 0.15)
                : headerButton.hovered
                    ? Qt.rgba(Kirigami.Theme.textColor.r,
                              Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, 0.06)
                    : "transparent"
        }

        contentItem: RowLayout {
            id: headerRow
            spacing: Kirigami.Units.largeSpacing   // 8px caret ↔ title (FormCard)
            Kirigami.Icon {
                source: root.expanded ? "arrow-down" : "arrow-right"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                color: Kirigami.Theme.textColor
            }
            // Title fills the row and stays LEFT-aligned. This is load-bearing:
            // if the title doesn't fill, then on expand (when the summary below
            // hides) the RowLayout shrinks to its content and the AbstractButton
            // centres it — the "title jumps to the middle" bug. fillWidth keeps
            // the row full-width in both states, so the title never moves.
            Kirigami.Heading {
                level: 5
                text: root.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
            // Muted inline summary, only while collapsed. Natural width (capped
            // + elided) so it sits at the right without stealing the fillWidth
            // from the title. PlainText sink: callers may feed url/label-derived
            // strings.
            QQC.Label {
                visible: !root.expanded && text.length > 0
                text: root.summary
                textFormat: Text.PlainText
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                Layout.maximumWidth: Kirigami.Units.gridUnit * 16
                Layout.alignment: Qt.AlignVCenter
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 1
            }
        }
    }

    // --- Collapsible body ---
    // visible:false drops it from QtQuick.Layouts size accounting, so the
    // host card shrinks to just the header when collapsed. Indented under the
    // header to reinforce the grouping; 4px between sibling controls (within-
    // group tightness), a little air top and bottom.
    ColumnLayout {
        id: contentHolder
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        visible: root.expanded
    }
}
