/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pins the User-Agent override value main.qml's _sanitisedUserAgent writes
 * onto every WebEngineProfile. null (not "") means "no override": "" on a
 * profile that has held a custom UA stores an empty User-Agent header.
 */
import QtQuick
import QtTest
import "../../package/contents/ui/UrlUtils.js" as UrlUtils

TestCase {
    name: "UserAgentOverride"

    function test_empty_isNull() {
        compare(UrlUtils.userAgentOverride(""), null);
    }

    function test_whitespaceOnly_isNull() {
        // WebEngine simplifies whitespace to "", the same empty header.
        compare(UrlUtils.userAgentOverride(" "), null);
        compare(UrlUtils.userAgentOverride("\t  "), null);
    }

    function test_onlyCrLf_isNull() {
        compare(UrlUtils.userAgentOverride("\r\n"), null);
    }

    function test_stripsCrLfNul() {
        compare(UrlUtils.userAgentOverride("custom/1\r\nX-Evil: 1\u0000"), "custom/1X-Evil: 1");
    }

    function test_realValue_keptVerbatim() {
        compare(UrlUtils.userAgentOverride("Mozilla/5.0 custom"), "Mozilla/5.0 custom");
    }
}
