/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pure cores of the three one-shot config migrations main.qml runs at
 * widget startup. Lifted here so tests/qml/tst_migrations.qml can drive
 * every code path with table-driven fixtures, deterministic UUIDs, and
 * a fake wallet reader — none of which is possible against the live
 * Plasmoid.configuration / authSupport bindings.
 *
 * Each function takes the *inputs* the production wrapper would read
 * from Plasmoid.configuration / KWallet and returns a *result* the
 * wrapper persists. No I/O, no side effects.
 */
.pragma library

// ─────────────────────────────────────────────────────────────────────
// 1. Pre-empt-flag migration (0.4.0 → 0.5.0).
//    The deprecated global useBasicAuthInjection becomes per-profile
//    `preempt`. Bearer/raw MUST be true (Qt's 401 dialog can't collect
//    a token); basic respects the old global; "none"/unknown → false.
//
// Returns { json: string, mutated: bool, error: string|null }
//   json:    new authProfilesJson (or the input on no-op / error)
//   mutated: whether any profile gained a preempt field
//   error:   non-null only on JSON.parse failure
// ─────────────────────────────────────────────────────────────────────
function preemptMigration(profilesJson, oldGlobalUseBasicAuth) {
    let profiles;
    try {
        profiles = JSON.parse(profilesJson || "[]");
        if (!Array.isArray(profiles)) profiles = [];
    } catch (e) {
        return { json: profilesJson, mutated: false, error: e.message };
    }
    const globalWasOn = oldGlobalUseBasicAuth === true;
    let mutated = false;
    for (const p of profiles) {
        if (typeof p.preempt === "boolean") continue;
        const t = p.authType || "basic";
        if (t === "bearer" || t === "raw")  p.preempt = true;
        else if (t === "basic")             p.preempt = globalWasOn;
        else                                p.preempt = false;
        mutated = true;
    }
    return {
        json:    mutated ? JSON.stringify(profiles) : profilesJson,
        mutated: mutated,
        error:   null,
    };
}

// ─────────────────────────────────────────────────────────────────────
// 2. Compact-preview migration (0.4.0 → 0.5.0).
//    The deprecated global compactPreviewMode="fixed" + compactPreviewTabIndex=N
//    becomes per-URL thumbMode="excluded" for every tab except N. For
//    mode="auto" (or unset) this is a no-op. Out-of-range pinned index
//    is treated as a corrupt config and skipped — wiping it into
//    "show nothing" would destroy the operator's intent silently.
//
// Returns { json: string|null, mutated: bool, skipped: bool, reason: string }
//   json:    new urlsJson (only when mutated); null otherwise
//   mutated: whether any tab gained thumbMode="excluded"
//   skipped: true when the migration deliberately did nothing
//            (mode!="fixed", parse error, out-of-range index)
//   reason:  human-readable explanation for skipped/mutated/no-op
// ─────────────────────────────────────────────────────────────────────
function compactPreviewMigration(urlsJson, oldMode, pinnedIndex) {
    if ((oldMode || "auto") !== "fixed") {
        return { json: null, mutated: false, skipped: true,
                 reason: "old mode is not 'fixed' (no-op)" };
    }
    let tabs;
    try {
        tabs = JSON.parse(urlsJson || "[]");
        if (!Array.isArray(tabs)) tabs = [];
    } catch (e) {
        return { json: null, mutated: false, skipped: true,
                 reason: "urlsJson parse error: " + e.message };
    }
    if (!Number.isInteger(pinnedIndex) || pinnedIndex < 0 || pinnedIndex >= tabs.length) {
        return { json: null, mutated: false, skipped: true,
                 reason: "pinned index out-of-range (" + pinnedIndex + "/" + tabs.length + ")" };
    }
    let mutated = false;
    for (let i = 0; i < tabs.length; i++) {
        if (i === pinnedIndex) continue;
        const t = tabs[i];
        if (!t || t.thumbMode === "excluded") continue;
        t.thumbMode = "excluded";
        mutated = true;
    }
    return {
        json:    mutated ? JSON.stringify(tabs) : null,
        mutated: mutated,
        skipped: false,
        reason:  mutated ? "marked non-pinned tabs as excluded"
                         : "pinned tab is only non-excluded; no-op",
    };
}

// ─────────────────────────────────────────────────────────────────────
// 3. Legacy-auth-fields migration (0.3.x → 0.4.0).
//    Pre-0.4.0 stored credentials per-URL in basicAuthUser/
//    basicAuthPasswordPlaintext/rawAuthHeader. 0.4.0 introduces named
//    profiles. Walks urlsJson, dedupes legacy fields by signature, and
//    emits the new shape + the wallet ops to perform.
//
// `walletReader(key)` is called for legacy "basic:<host>" keys that
//   the pre-0.4.0 code may have written. Tests inject a fake; the
//   production wrapper passes authSupport.get(key).
// `uuidGen()` returns a fresh UUID. Tests inject a deterministic gen.
//
// Returns {
//   urlsJson:     string,   // rewritten (legacy fields stripped)
//   profilesJson: string,   // augmented with newly-created profiles
//   walletWrites: [{ key, map }], // entries the caller should write
//   mutated:      bool,
// }
// On JSON parse error, returns { ..., mutated: false } with inputs verbatim.
// ─────────────────────────────────────────────────────────────────────
function legacyAuthMigration(urlsJson, profilesJson, autheliaHostFallback,
                             walletReader, uuidGen) {
    walletReader = walletReader || function() { return ""; };
    autheliaHostFallback = autheliaHostFallback || "";

    let tabs;
    let profiles;
    try {
        tabs = JSON.parse(urlsJson || "[]");
        if (!Array.isArray(tabs)) tabs = [];
        profiles = JSON.parse(profilesJson || "[]");
        if (!Array.isArray(profiles)) profiles = [];
    } catch (e) {
        return { urlsJson: urlsJson, profilesJson: profilesJson,
                 walletWrites: [], mutated: false };
    }

    // Dedupe key per existing profile so we re-use on re-runs.
    const byKey = {};
    for (const p of profiles) {
        const sig = (p.authType === "raw") ? ("raw:" + p.id)
                                            : ("basic:" + (p.username || ""));
        byKey[sig] = p;
    }

    const walletWrites = [];
    let mutated = false;

    for (const t of tabs) {
        if (!t || t.authProfileId) continue;
        const hasLegacy = (t.basicAuthUser && t.basicAuthUser.length > 0) ||
                          (t.basicAuthPasswordPlaintext && t.basicAuthPasswordPlaintext.length > 0) ||
                          (t.rawAuthHeader && t.rawAuthHeader.length > 0);
        if (!hasLegacy) continue;

        let host = "";
        try { host = new URL(t.url).host; } catch (e) { /* keep "" */ }

        const sig = t.rawAuthHeader
            ? ("raw:" + t.rawAuthHeader.substring(0, 32))
            : ("basic:" + host + ":" + (t.basicAuthUser || ""));

        let p = byKey[sig];
        if (!p) {
            p = {
                id: uuidGen(),
                name: host + (t.basicAuthUser ? " (" + t.basicAuthUser + ")"
                                              : t.rawAuthHeader ? " (raw header)" : ""),
                authType: t.rawAuthHeader ? "raw" : "basic",
                username: t.basicAuthUser || "",
                autheliaHost: autheliaHostFallback,
            };
            const oldKWalletPw = walletReader("basic:" + host) || "";
            const secret = t.rawAuthHeader || oldKWalletPw || t.basicAuthPasswordPlaintext || "";
            if (secret.length > 0) {
                const map = {};
                if (t.rawAuthHeader) map.rawHeader = secret;
                else                  map.password  = secret;
                walletWrites.push({ key: "profile:" + p.id, map: map });
            }
            profiles.push(p);
            byKey[sig] = p;
        }
        t.authProfileId = p.id;
        delete t.basicAuthUser;
        delete t.basicAuthPasswordPlaintext;
        delete t.rawAuthHeader;
        mutated = true;
    }

    return {
        urlsJson:     mutated ? JSON.stringify(tabs)     : urlsJson,
        profilesJson: mutated ? JSON.stringify(profiles) : profilesJson,
        walletWrites: walletWrites,
        mutated:      mutated,
    };
}
