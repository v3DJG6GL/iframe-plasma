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
        thumbIconName:  sanitizeIconName(entry.thumbIconName),
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
