/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
import QtQuick
import QtTest
import "../../package/contents/ui" as Ui

TestCase {
    name: "Log"

    function test_redactUrl_stripsQueryAndFragment() {
        compare(Ui.Log.redactUrl("https://host.example/d/abc?token=s3cret#panel-2"),
                "https://host.example/d/abc");
        compare(Ui.Log.redactUrl("https://host.example/d/abc#frag?x=1"),
                "https://host.example/d/abc");
    }

    function test_redactUrl_stripsUserinfo() {
        compare(Ui.Log.redactUrl("https://user:secret@host.example/p?q=1#f"),
                "https://host.example/p");
        compare(Ui.Log.redactUrl("http://user@host.example:8080/p"),
                "http://host.example:8080/p");
        // No path: the authority runs to the end of the string.
        compare(Ui.Log.redactUrl("https://user:secret@host.example"),
                "https://host.example");
        // An unescaped "@" inside the password must not leave half of it.
        compare(Ui.Log.redactUrl("https://user:p@ss@host.example/p"),
                "https://host.example/p");
    }

    function test_redactUrl_keepsAtSignInPath() {
        compare(Ui.Log.redactUrl("https://host.example/users/@me?x=1"),
                "https://host.example/users/@me");
    }

    function test_redactUrl_nonStringInput() {
        compare(Ui.Log.redactUrl(undefined), "");
        compare(Ui.Log.redactUrl(null), "");
        compare(Ui.Log.redactUrl(Qt.url("https://user:secret@host.example/p?q=1")),
                "https://host.example/p");
    }
}
