/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pure helpers of the Backup KCM page (ConfigBackup.qml), kept here so
 * tests/qml/tst_backup_page.qml can drive them without loading the page.
 */
.pragma library

// What an import did to the page, from three flat key->value maps:
// `before` is the persisted configuration, `after` the live values after the
// apply, `wanted` what the file asked for. The controls behind the page's
// aliases can store something other than the value assigned (a SpinBox
// clamps to its range), so both answers come from `after`, never from
// `wanted`:
//   changed  — some live value differs from the persisted one (Apply is
//              enabled). Judged over every key the page holds, as the
//              shell's Apply test is: an earlier unapplied import can have
//              changed a key this file does not carry.
//   adjusted — keys whose stored value is not the imported one
// Keys the page does not hold (absent from `after`) are ignored.
function importOutcome(before, wanted, after) {
    const adjusted = [];
    let changed = false;
    for (const k in wanted) {
        if (!(k in after)) continue;
        if (after[k] !== wanted[k]) adjusted.push(k);
    }
    for (const k in after) {
        if (after[k] !== before[k]) changed = true;
    }
    return { changed: changed, adjusted: adjusted };
}

// How the import banner reads, from importFromFile's `result` and the
// importOutcome above:
//   headline — "changed" (Apply is enabled), "matches" (the file's values
//              are the persisted ones) or "unusable" (no setting in the
//              file could be used: every one was skipped, or it carried
//              none, so nothing was compared and "matches" would claim a
//              match for a file that supplied nothing)
//   warning  — not a plain success: the file was unusable, something
//              was skipped, a value was adjusted to fit (the file's value
//              was replaced, too), or the revert-point snapshot reported an
//              error / caveat
function importBanner(result, outcome) {
    const r = result || {};
    const skipped = r.skipped ? r.skipped.length : 0;
    const used = r.config ? Object.keys(r.config).length : 0;
    let headline;
    if (used === 0) headline = "unusable";
    else headline = (outcome && outcome.changed) ? "changed" : "matches";
    const adjusted = (outcome && outcome.adjusted) ? outcome.adjusted.length : 0;
    return { headline: headline,
             warning: used === 0 || skipped > 0 || adjusted > 0
                      || !!(r.error || r.warning) };
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
