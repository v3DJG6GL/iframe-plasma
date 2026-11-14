/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pure helpers of the Backup KCM page (ConfigBackup.qml), kept here so
 * tests/qml/tst_backup_page.qml can drive them without loading the page.
 */
.pragma library

// What an import did to the page, from three flat key->value maps:
// `before` / `after` are the live values around the apply, `wanted` is what
// the file asked for. The controls behind the page's aliases can store
// something other than the value assigned (a SpinBox clamps to its range),
// so both answers come from `after`, never from `wanted`:
//   changed  — some live value differs from before (Apply is enabled)
//   adjusted — keys whose stored value is not the imported one
// Keys the page does not hold (absent from `after`) are ignored.
function importOutcome(before, wanted, after) {
    const adjusted = [];
    let changed = false;
    for (const k in wanted) {
        if (!(k in after)) continue;
        if (after[k] !== wanted[k]) adjusted.push(k);
        if (after[k] !== before[k]) changed = true;
    }
    return { changed: changed, adjusted: adjusted };
}

// File URL of `fileName` inside the folder `folderUrl` ("file:///…", as
// StandardPaths returns it). The dialog needs the folder: "file://" plus a
// bare name parses the name as the URL host and leaves the path empty.
// Returns "" without a folder, so the dialog falls back to its own default.
function exportFileUrl(folderUrl, fileName) {
    const folder = String(folderUrl || "");
    if (folder.length === 0) return "";
    return folder.replace(/\/$/, "") + "/" + encodeURIComponent(fileName);
}
