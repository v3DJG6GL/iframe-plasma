/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Canonical Grafana time-range presets — shared between the popup's
 * toolbar chip dropdown (CyberToolbar) and the config dialog's two
 * combos (ConfigUrls thumbnail-range picker + Grafana-URL helper).
 * Each call site prepends its own no-override head row ("(URL default)",
 * "Same as widget", "(keep URL's range)"); this list covers 5m..90d
 * so the i18n strings exist in exactly one place for translators.
 */
pragma Singleton
import QtQuick

QtObject {
    readonly property var presets: [
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
}
