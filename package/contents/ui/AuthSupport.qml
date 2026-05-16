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

    property var interceptor: IframePlasma.BasicAuthInterceptor {}

    // Legacy single-string wallet entries (basic:<host>) — used by the
    // one-shot migration in main.qml to read pre-0.4.0 secrets.
    function get(key) { return IframePlasma.SecretsBridge.get(key) }
    function set(key, value) { return IframePlasma.SecretsBridge.set(key, value) }
    function has(key) { return IframePlasma.SecretsBridge.has(key) }
    function remove(key) { return IframePlasma.SecretsBridge.remove(key) }

    // Multi-field map entries — used by named auth profiles.
    // Wallet key is `profile:<uuid>`, value is a map with one of:
    //   { password: "..." }       (authType=basic)
    //   { bearerToken: "..." }    (authType=bearer)
    //   { rawHeader: "..." }      (authType=raw)
    function getMap(key)         { return IframePlasma.SecretsBridge.getMap(key) }
    function setMap(key, fields) { return IframePlasma.SecretsBridge.setMap(key, fields) }
    function removeKey(key)      { return IframePlasma.SecretsBridge.removeKey(key) }

    // Legacy interceptor API — kept for migration compatibility.
    function setCredential(host, user, pw) { interceptor.setCredential(host, user, pw) }
    function setRawHeader(host, value) { interceptor.setRawHeader(host, value) }
    function clearCredentials() { interceptor.clearAll() }

    // Profile-aware interceptor API (0.4.0+).
    function applyProfile(id, type, user, secret, hosts) {
        interceptor.applyProfile(id, type, user, secret, hosts)
    }
    function clearProfile(id) { interceptor.clearProfile(id) }

    function attachInterceptor(profile) { return interceptor.attachTo(profile) }
    function detachInterceptor(profile) { return interceptor.detachFrom(profile) }
}
