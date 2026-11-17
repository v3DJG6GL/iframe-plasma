// SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma Singleton
import QtQml
import QtWebEngine

// The one place a user script is built and installed on a WebEngineView, so
// every script the widget injects (popup WebTab and the compact thumbnail)
// shares the same injection settings: document creation, the page's main
// world, top frame only.
//
// WebEngineScript is a value type in Qt 6 and can't be inlined in QML, so it
// is built imperatively via the WebEngine.script() factory.
QtObject {
    // Removes any script called `name` from `view`, then installs `src`
    // under that name. An empty `src` only removes.
    function replace(view, name, src) {
        const old = view.userScripts.find(name);
        for (let i = 0; i < old.length; ++i) view.userScripts.remove(old[i]);
        if (!src) return;
        const s = WebEngine.script();
        s.name = name;
        s.injectionPoint = WebEngineScript.DocumentCreation;
        s.worldId = WebEngineScript.MainWorld;
        // The value type's property is runsOnSubFrames; the old copies set
        // a non-existent runOnSubFrames, a silent no-op (false is the
        // default, so the effect is the same).
        s.runsOnSubFrames = false;
        s.sourceCode = src;
        view.userScripts.insert(s);
    }
}
