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
//   - an Array of strings (preferred shape)
//   - a single string (legacy single-keyword field)
//   - missing / null / undefined → []
// Empty / non-string entries are filtered. Pure; idempotent. The
// downstream chip-list editor in ConfigUrls owns the user-visible
// add/remove flow; CropEngine compiles each entry to a RegExp or a
// case-insensitive substring at apply time.
function _normaliseKeywords(v) {
    if (!v) return [];
    const arr = Array.isArray(v) ? v : [v];
    const out = [];
    for (let i = 0; i < arr.length; i++) {
        const s = arr[i];
        if (typeof s === "string" && s.length > 0) out.push(s);
    }
    return out;
}

function normaliseTabRow(entry) {
    entry = entry || {};
    const sel = entry.thumbSelector || "";
    const mode = entry.thumbMode || "chartOnly";

    const psel = entry.popupSelector || "";
    const pmode = entry.popupMode || "fullPanel";

    return {
        label:                entry.label || "",
        url:                  entry.url || "",
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
        popupMode:            pmode,
        popupSelector:        psel,
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
