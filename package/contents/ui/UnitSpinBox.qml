/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * QQC.SpinBox wrapper that makes typing multi-digit values actually work.
 *
 * Plain QQC.SpinBox + custom `textFromValue` (e.g. v + " seconds") is hostile
 * to typing: Qt's default `valueFromText` is Number.fromLocaleString, which
 * can't parse "30 seconds" → snaps to `from` on every Tab/Enter; meanwhile
 * the cursor lands at end-of-string (past the unit suffix), so the next
 * digit keystroke appends *after* the suffix ("30 seconds0"). The user
 * cannot type "300" from a default "30 seconds" without arrow-button
 * fights.
 *
 * Fix: `editable: true` + a `valueFromText` that strips every non-digit /
 * non-dash before parsing, then clamps to [from, to]. NoWheel suppresses
 * accidental scroll-over-spinbox value changes (same as it does for other
 * controls in the project).
 *
 * Two ways to configure the display:
 *
 *   suffix: " s"                         // simple "<value> s" rendering
 *   textFormatter: (v) => i18np("%1 second", "%1 seconds", v)
 *                                        // overrides suffix; full control,
 *                                        // useful for i18np plurals or a
 *                                        // sentinel like "disabled" at v=0.
 *
 * If both are set, textFormatter wins.
 *
 * Usage:
 *   UnitSpinBox { from: 1; to: 3600; value: 30; suffix: " s" }
 *
 *   UnitSpinBox {
 *       from: 0; to: 65535; value: 0
 *       textFormatter: (v) => v === 0 ? i18n("disabled") : String(v)
 *   }
 */
import QtQuick
import QtQuick.Controls as QQC

QQC.SpinBox {
    id: root

    property string suffix: ""
    property var textFormatter: null

    editable: true

    textFromValue: (v, _locale) => {
        if (textFormatter) return textFormatter(v);
        return String(v) + suffix;
    }

    valueFromText: (text, _locale) => {
        const n = parseInt(String(text).replace(/[^0-9-]/g, ""), 10);
        if (isNaN(n)) return value;
        return Math.max(from, Math.min(to, n));
    }

    NoWheel {}
}
