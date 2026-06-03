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
 * normaliseTabRow(entry)     — apply tab defaults. Pure; idempotent.
 * normaliseAuthProfileRow(entry, uuidGen)
 *                            — apply profile defaults + synthesise UUID
 *                              when missing + default preempt from
 *                              authType. uuidGen is a callable so tests
 *                              can inject a deterministic generator.
 *                              Returns { row, synthesized: bool } so
 *                              callers know to re-persist.
 *
 * Neither function mutates `entry`.
 */
.pragma library

// Allow-list for thumbIconName. IconPickerDialog emits exactly three
// shapes (theme name, "bundled:<name>", "file:///<abs path>"); anything
// else can only arrive via attacker-crafted backup JSON (BackupBridge
// does not introspect urlsJson contents). Without this gate, a payload
// like "http://attacker/p?h=KIOSK-A" would reach Kirigami.Icon, which
// actually issues outbound HTTP via QQmlEngine::networkAccessManager —
// a persistent beacon on every panel paint / auto-cycle / reload.
function sanitizeIconName(name) {
    const s = String(name || "");
    if (s.length === 0) return "";
    // "bundled:<safe>" — no path separators, no ".." traversal out of
    // package/contents/icons/bundled/.
    if (/^bundled:[A-Za-z0-9_-]+$/.test(s)) return s;
    // "file:///<abs path>" from the operator's FileDialog pick. Refuse
    // C0/DEL so a smuggled CR/LF can't smear into a downstream renderer.
    if (/^file:\/\/\//.test(s) && !/[\x00-\x1f\x7f]/.test(s)) return s;
    // FreeDesktop icon-naming spec: letters/digits/dot/dash/underscore.
    // Leading char must be alnum so a stray "://" can't slip through.
    if (/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(s)) return s;
    return "";
}

// Three explicit modes for how the panel-slot thumbnail sizes the
// matched element's box and content:
//   "fit"      → measure intrinsic content size, apply transform: scale
//                so smaller content fills the viewport aspect-preserved
//   "original" → no width/height override; the matched element keeps
//                its natural size, anchored top-left, siblings hidden
//   "stretch"  → outer box sized to 100vw × 100vh (current/legacy
//                behavior — good for responsive widgets like uPlot)
// Unknown values normalise to "fit" so a corrupt backup can't paint
// "junk" mode all the way to the renderer.
function _normaliseScaleMode(v) {
    return (v === "original" || v === "stretch" || v === "fit") ? v : "fit";
}

// Coerce a thumbExcludeKeywords value into an Array<string>. Accepts:
//   - an Array of strings (the only on-disk shape — ConfigUrls stores it
//     as a plain Array)
//   - anything else (missing / null / non-array) → []
// Empty / non-string entries are filtered. Pure; idempotent. The
// downstream chip-list editor in ConfigUrls owns the user-visible
// add/remove flow; CropEngine compiles each entry to a RegExp or a
// case-insensitive substring at apply time.
function _normaliseKeywords(v) {
    if (!Array.isArray(v)) return [];
    const out = [];
    for (let i = 0; i < v.length; i++) {
        const s = v[i];
        if (typeof s === "string" && s.length > 0) out.push(s);
    }
    return out;
}

// Canonical, ordered field set for a tab row — the single declared
// contract that normaliseTabRow (deserialize) and serialiseTabRow
// (serialize) must both satisfy. tests/qml/tst_serialize_urls.qml asserts
// Object.keys(normaliseTabRow({})) === Object.keys(serialiseTabRow({})) ===
// TAB_FIELDS, so a field added to one direction but not the other (the
// f831b02 drift class — three thumb* fields silently dropped on serialize)
// fails CI instead of silently corrupting every save.
const TAB_FIELDS = [
    "label", "url", "enabled", "authProfileId", "thumbMode", "thumbSelector",
    "thumbText", "thumbIconName", "thumbTimeRange", "thumbScaleMode",
    "thumbExcludeKeywords", "thumbShowLabel", "excludeFromRotation",
    "popupMode", "popupSelector",
];

// Coerce the retired thumbMode="excluded" value (a single mode that used to
// both blank the panel slot AND skip rotation) to a plain full-page
// thumbnail. Auto-rotation skipping now lives in the dedicated
// `excludeFromRotation` boolean, so a legacy "excluded" row renders normally
// and rejoins rotation. Applied in both directions so a stale value can never
// reach a runtime consumer (UrlUtils.nextCycleTabIndex / main.qml previewTabIdx)
// — see tst_serialize_urls' coercion test.
function _coerceThumbMode(mode) {
    return mode === "excluded" ? "fullPanel" : mode;
}

function normaliseTabRow(entry) {
    entry = entry || {};
    const sel = entry.thumbSelector || "";
    const mode = _coerceThumbMode(entry.thumbMode || "chartOnly");

    const psel = entry.popupSelector || "";
    const pmode = entry.popupMode || "fullPanel";

    return {
        label:                entry.label || "",
        url:                  entry.url || "",
        // Per-URL on/off. Default ON: a missing/non-false value (legacy
        // rows, imported backups predating this field) round-trips as
        // enabled so existing configs are unchanged. main.qml's parseTabs
        // drops `enabled === false` rows from the live tab set, so a
        // disabled URL keeps its config here but never becomes a tab.
        enabled:              entry.enabled !== false,
        authProfileId:        entry.authProfileId || "",
        thumbMode:            mode,
        thumbSelector:        sel,
        thumbText:            entry.thumbText || "",
        thumbIconName:        sanitizeIconName(entry.thumbIconName),
        thumbTimeRange:       entry.thumbTimeRange || "",
        thumbScaleMode:       _normaliseScaleMode(entry.thumbScaleMode),
        thumbExcludeKeywords: _normaliseKeywords(entry.thumbExcludeKeywords),
        // Per-URL opt-IN for the panel-slot label overlay. The overlay
        // paints only for rows whose user has explicitly ticked the
        // URLs-tab "Display tab label on this thumbnail" checkbox.
        // Default false → no overlay; an explicit true → overlay
        // (provided thumbMode renders a slot at all).
        thumbShowLabel:       entry.thumbShowLabel === true,
        // Per-URL opt-IN to skip this tab during panel-slot auto-rotation
        // while leaving its thumbnail untouched (it still renders normally
        // when the user actively selects it). Default false. The cycle
        // stepper (UrlUtils.nextCycleTabIndex) reads this; nothing else does.
        excludeFromRotation:  entry.excludeFromRotation === true,
        popupMode:            pmode,
        popupSelector:        psel,
    };
}

// Pure serialise of ONE already-normalised tab row to its on-disk shape.
// Mirror of normaliseTabRow's return, reusing the SAME sanitisers
// (sanitizeIconName / _normaliseScaleMode / _normaliseKeywords) so the two
// directions cannot drift and serialise is defence-in-depth-equal to
// normalise. `row.thumbExcludeKeywords` MUST already be an Array — the
// ListModel JSON-string boundary is resolved by the caller (ConfigUrls).
// Pure; does not mutate `row`. Returns the canonical TAB_FIELDS object.
function serialiseTabRow(row) {
    row = row || {};
    return {
        label:                row.label || "",
        url:                  row.url || "",
        // Mirror normaliseTabRow's default-ON idiom (`!== false`), NOT the
        // default-OFF `=== true` form thumbShowLabel uses — the two
        // directions must agree so tst_serialize_urls' parity guard holds.
        enabled:              row.enabled !== false,
        authProfileId:        row.authProfileId || "",
        thumbMode:            _coerceThumbMode(row.thumbMode || "chartOnly"),
        thumbSelector:        row.thumbSelector || "",
        thumbText:            row.thumbText || "",
        thumbIconName:        sanitizeIconName(row.thumbIconName),
        thumbTimeRange:       row.thumbTimeRange || "",
        thumbScaleMode:       _normaliseScaleMode(row.thumbScaleMode),
        thumbExcludeKeywords: _normaliseKeywords(row.thumbExcludeKeywords),
        thumbShowLabel:       row.thumbShowLabel === true,
        excludeFromRotation:  row.excludeFromRotation === true,
        popupMode:            row.popupMode || "fullPanel",
        popupSelector:        row.popupSelector || "",
    };
}

// Canonical, ordered field set for an auth-profile row. Declared contract
// for normaliseAuthProfileRow(...).row and serialiseAuthProfileRow — the
// auth-side twin of TAB_FIELDS (see comment there).
const AUTH_FIELDS = [
    "id", "name", "authType", "username", "autheliaHost", "preempt",
];

function normaliseAuthProfileRow(entry, uuidGen) {
    entry = entry || {};
    let synthesized = false;
    let id = entry.id;
    if (!id) {
        id = uuidGen();
        synthesized = true;
    }
    const authType = entry.authType || "basic";

    // Defensive default for preempt when the field is missing or non-bool.
    // Bearer/raw MUST pre-empt because Qt's 401 dialog can only collect
    // user+password, so a token mismatch is otherwise unrecoverable.
    let preempt;
    if (typeof entry.preempt === "boolean") {
        preempt = entry.preempt;
    } else {
        preempt = (authType === "bearer" || authType === "raw");
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

// Pure serialise of ONE already-normalised auth-profile row to its on-disk
// shape. Mirror of normaliseAuthProfileRow's `row` (the 6 AUTH_FIELDS); the
// row is already normalised by the time it is serialised, so preempt is a
// plain `=== true` rather than the authType-derived default normalise
// applies on the way in. autheliaHost sanitisation deliberately stays a
// repopulate-time concern (sanitizeAutheliaHost lives in ConfigAuth, not
// here) to keep this a behaviour-preserving refactor. Pure; no mutation.
function serialiseAuthProfileRow(row) {
    row = row || {};
    return {
        id:           row.id || "",
        name:         row.name || "",
        authType:     row.authType || "basic",
        username:     row.username || "",
        autheliaHost: row.autheliaHost || "",
        preempt:      row.preempt === true,
    };
}
