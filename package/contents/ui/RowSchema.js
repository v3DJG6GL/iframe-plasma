/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Per-row schema normalisation for urlsJson + authProfilesJson — the
 * mapping each KCM page applies on deserialize so missing/legacy fields
 * round-trip cleanly into the ListModel. Pulled out of ConfigUrls.qml
 * and ConfigAuth.qml so tests/qml/tst_serialize_urls.qml and
 * tests/qml/tst_serialize_authprofiles.qml can drive the contract
 * without instantiating the KCM Dialog tree.
 *
 * normaliseTabRow(entry)     — apply tab defaults + thumbMode/popupMode
 *                              legacy inference. Pure; idempotent.
 * normaliseAuthProfileRow(entry, uuidGen)
 *                            — apply profile defaults + synthesise UUID
 *                              when missing + derive preempt from
 *                              authType. uuidGen is a callable so tests
 *                              can inject a deterministic generator.
 *                              Returns { row, synthesized: bool } so
 *                              callers know to re-persist.
 *
 * Neither function mutates `entry`.
 */
.pragma library

function normaliseTabRow(entry) {
    entry = entry || {};
    let mode = entry.thumbMode || "";
    const sel = entry.thumbSelector || "";
    if (!mode) mode = sel.length > 0 ? "custom" : "chartOnly";

    let pmode = entry.popupMode || "";
    const psel = entry.popupSelector || "";
    if (!pmode) pmode = psel.length > 0 ? "custom" : "fullPanel";

    return {
        label:          entry.label || "",
        url:            entry.url || "",
        authProfileId:  entry.authProfileId || "",
        thumbMode:      mode,
        thumbSelector:  sel,
        thumbText:      entry.thumbText || "",
        thumbIconName:  entry.thumbIconName || "",
        thumbTimeRange: entry.thumbTimeRange || "",
        popupMode:      pmode,
        popupSelector:  psel,
    };
}

function normaliseAuthProfileRow(entry, uuidGen) {
    entry = entry || {};
    let synthesized = false;
    let id = entry.id;
    if (!id) {
        id = uuidGen();
        synthesized = true;
    }
    const authType = entry.authType || "basic";

    // Default preempt per type when the field is missing on pre-0.5.0
    // entries. Bearer/raw MUST pre-empt because Qt's 401 dialog can only
    // collect user+password, so a token mismatch is otherwise unrecoverable.
    let preempt;
    if (typeof entry.preempt === "boolean") {
        preempt = entry.preempt;
    } else {
        preempt = (authType === "bearer" || authType === "raw");
        synthesized = true;
    }

    return {
        row: {
            id:           id,
            name:         entry.name || "",
            authType:     authType,
            username:     entry.username || "",
            autheliaHost: entry.autheliaHost || "",
            preempt:      preempt,
        },
        synthesized: synthesized,
    };
}
