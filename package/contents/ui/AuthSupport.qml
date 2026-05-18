/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * This file isolates the C++ QML plugin import so the rest of the widget
 * still loads if the plugin isn't built/installed yet. Loaded via a Loader
 * in main.qml; on failure, basic-auth and pre-emptive header injection
 * gracefully disable themselves.
 */
import QtQuick
import QtWebEngine
import io.github.v3DJG6GL.iframe 1.0 as IframePlasma

QtObject {
    id: support
    readonly property bool available: true

    // One-per-process interceptor reserved for legacy callers (clearCredentials,
    // applyProfile, attachInterceptor) and code paths that still want a single
    // interceptor. The per-profile design in main.qml uses createInterceptor()
    // to mint a fresh instance per WebEngineProfile so each profile owns an
    // independent host→Authorization map (no cross-profile header leakage).
    property var interceptor: IframePlasma.BasicAuthInterceptor {}

    // Factory: mint a new BasicAuthInterceptor parented to this QtObject so
    // its lifetime tracks the auth-support context.  Returns null if the C++
    // plugin isn't loaded.
    function createInterceptor() {
        const comp = Qt.createComponent("io.github.v3DJG6GL.iframe", "BasicAuthInterceptor");
        if (comp.status !== Component.Ready) {
            console.warn("iframe-plasma[auth] createInterceptor failed:", comp.errorString());
            return null;
        }
        return comp.createObject(support);
    }

    // Read legacy pre-0.4.0 single-string entries (`basic:<host>`) during the
    // one-shot migration in main.qml. Newer profiles use map entries below.
    function get(key) { return IframePlasma.SecretsBridge.get(key) }
    function has(key) { return IframePlasma.SecretsBridge.has(key) }

    // Multi-field map entries for named auth profiles. Wallet key is
    // `profile:<uuid>` (single source of truth in `profileKey()`); value
    // is a map with one of:
    //   { password: "..." }       (authType=basic)
    //   { bearerToken: "..." }    (authType=bearer)
    //   { rawHeader: "..." }      (authType=raw)
    function profileKey(id)      { return "profile:" + id }
    function getMap(key)         { return IframePlasma.SecretsBridge.getMap(key) }
    function setMap(key, fields) { return IframePlasma.SecretsBridge.setMap(key, fields) }
    function removeKey(key)      { return IframePlasma.SecretsBridge.removeKey(key) }

    // Profile-aware interceptor API (0.4.0+). clearCredentials wipes the lot
    // before each prime so we don't accumulate stale per-host headers from
    // profiles that have been edited or deleted.
    function clearCredentials() { interceptor.clearAll() }
    function applyProfile(id, type, user, secret, hosts) {
        interceptor.applyProfile(id, type, user, secret, hosts)
    }

    function attachInterceptor(profile) { return interceptor.attachTo(profile) }
    function detachInterceptor(profile) { return interceptor.detachFrom(profile) }
}
