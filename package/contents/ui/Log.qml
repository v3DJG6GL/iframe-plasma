// SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma Singleton
import QtQml

// Logging categories for the widget's QML side. Pass one as the first
// argument to console.debug/info/warn/error so the message is attributed to
// it instead of Qt's shared "qml" category, e.g.
//
//     console.debug(Log.auth, "applied profile id=" + id);
//
// Every category defaults to Info, mirroring plasmashell's own categories:
// debug-level trace is off until enabled with a Qt logging rule
// (QT_LOGGING_RULES="io.github.v3djg6gl.iframe.*.debug=true", or via
// kdebugsettings followed by a plasmashell restart). The C++ plugin declares
// the same names (src/*.cpp) so a single rule covers both layers.
//
// Level guide: debug = routine per-load/per-tick trace; info = rare,
// user-meaningful state changes; warn = recoverable problems and blocked
// actions; error = a feature is out of action.
//
// NOTE: no i18n() in this singleton — see Theme.qml for the rationale.
QtObject {
    // Auth profiles, secrets, header injection, credential dialogs.
    readonly property LoggingCategory auth: LoggingCategory {
        name: "io.github.v3djg6gl.iframe.auth"
        defaultLogLevel: LoggingCategory.Info
    }
    // Page loads, reloads, retries, renderer crashes, certificate errors.
    readonly property LoggingCategory load: LoggingCategory {
        name: "io.github.v3djg6gl.iframe.load"
        defaultLogLevel: LoggingCategory.Info
    }
    // Denied permissions / dialogs / navigations / downloads (audit trail).
    readonly property LoggingCategory policy: LoggingCategory {
        name: "io.github.v3djg6gl.iframe.policy"
        defaultLogLevel: LoggingCategory.Info
    }
    // Panel thumbnail crop, keyword exclusion, compact-view apply paths.
    readonly property LoggingCategory thumb: LoggingCategory {
        name: "io.github.v3djg6gl.iframe.thumb"
        defaultLogLevel: LoggingCategory.Info
    }
    // Interactive panel-selector picker.
    readonly property LoggingCategory picker: LoggingCategory {
        name: "io.github.v3djg6gl.iframe.picker"
        defaultLogLevel: LoggingCategory.Info
    }
    // Configuration parsing/validity and startup capability reports.
    readonly property LoggingCategory config: LoggingCategory {
        name: "io.github.v3djg6gl.iframe.config"
        defaultLogLevel: LoggingCategory.Info
    }
    // Console output forwarded from the embedded web pages (untrusted, chatty).
    readonly property LoggingCategory page: LoggingCategory {
        name: "io.github.v3djg6gl.iframe.page"
        defaultLogLevel: LoggingCategory.Info
    }
    // Freeze/discard lifecycle and screen-lock handling.
    readonly property LoggingCategory lifecycle: LoggingCategory {
        name: "io.github.v3djg6gl.iframe.lifecycle"
        defaultLogLevel: LoggingCategory.Info
    }

    // Scheme + host + path only: query strings (Grafana share tokens, auth
    // params) and fragments never belong in a message that is on by default.
    function redactUrl(u) {
        return String(u === undefined || u === null ? "" : u).replace(/[?#].*$/, "");
    }

    // Forward a page console message (QQuickWebEngineView.javaScriptConsoleMessage)
    // into the `page` category. Page errors surface as warnings so a broken
    // dashboard leaves a breadcrumb; everything else is debug-only trace.
    function pageConsole(level, safeMessage) {
        // JavaScriptConsoleMessageLevel: 0 Info, 1 Warning, 2 Error
        if (level === 2) console.warn(page, safeMessage);
        else console.debug(page, safeMessage);
    }
}
