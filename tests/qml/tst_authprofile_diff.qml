/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Pins the auth-profile diff main.qml's onAuthProfilesJsonChanged uses to
 * decide which tabs to soft-reload. The handler must diff against a
 * snapshot it owns: root.authProfiles is bound to the same config key and
 * its binding re-evaluates before the handler runs, so reading it as the
 * "before" side reports "unchanged" on the first edit of a session.
 */
import QtQuick
import QtTest
import "../../package/contents/ui/UrlUtils.js" as U

TestCase {
    id: tc
    name: "AuthProfileDiff"

    // Same shape as main.qml: a config key, a property bound to it, and a
    // Connections handler on the key's change signal.
    QtObject {
        id: cfg
        property string authProfilesJson: tc._json("old")
    }
    property var authProfiles: U.parseAuthProfiles(cfg.authProfilesJson)
    property var bodies: ({})
    property var changedLog: []
    Connections {
        target: cfg
        function onAuthProfilesJsonChanged() {
            const oldById = tc.bodies;
            tc.authProfiles = U.parseAuthProfiles(cfg.authProfilesJson);
            const newById = U.authProfileBodies(tc.authProfiles);
            tc.bodies = newById;
            tc.changedLog.push(U.changedAuthProfileIds(oldById, newById));
        }
    }

    function _json(user) {
        return JSON.stringify([
            { id: "a", authType: "basic", username: user },
            { id: "b", authType: "bearer" }
        ]);
    }

    // ===== authProfileBodies =========================================
    function test_bodies_keyedById() {
        const b = U.authProfileBodies([{ id: "a", username: "u" }]);
        compare(Object.keys(b), ["a"]);
        compare(b.a, JSON.stringify({ id: "a", username: "u" }));
    }
    function test_bodies_skipsRowsWithoutId() {
        compare(Object.keys(U.authProfileBodies([null, {}, { id: "" }, { id: "x" }])), ["x"]);
    }
    function test_bodies_nonArray_empty() {
        compare(Object.keys(U.authProfileBodies(null)).length, 0);
        compare(Object.keys(U.authProfileBodies("[]")).length, 0);
    }

    // ===== changedAuthProfileIds =====================================
    function test_changed_identical_none() {
        const b = U.authProfileBodies([{ id: "a", username: "u" }]);
        compare(U.changedAuthProfileIds(b, U.authProfileBodies([{ id: "a", username: "u" }])), []);
    }
    function test_changed_bodyDiffers() {
        compare(U.changedAuthProfileIds(
            U.authProfileBodies([{ id: "a", username: "u" }, { id: "b" }]),
            U.authProfileBodies([{ id: "a", username: "v" }, { id: "b" }])), ["a"]);
    }
    function test_changed_added() {
        compare(U.changedAuthProfileIds(
            U.authProfileBodies([{ id: "a" }]),
            U.authProfileBodies([{ id: "a" }, { id: "b" }])), ["b"]);
    }
    function test_changed_removed() {
        compare(U.changedAuthProfileIds(
            U.authProfileBodies([{ id: "a" }, { id: "b" }]),
            U.authProfileBodies([{ id: "a" }])), ["b"]);
    }
    function test_changed_nullMaps() {
        compare(U.changedAuthProfileIds(null, undefined), []);
        compare(U.changedAuthProfileIds(null, U.authProfileBodies([{ id: "a" }])), ["a"]);
    }

    // ===== First change of a session =================================
    function test_firstConfigChange_reportsEditedProfile() {
        // Seed as main.qml's Component.onCompleted does. No test above
        // writes cfg, so the binding on authProfiles is still live here.
        tc.bodies = U.authProfileBodies(tc.authProfiles);
        compare(Object.keys(tc.bodies), ["a", "b"]);

        cfg.authProfilesJson = _json("new");
        compare(tc.changedLog.length, 1);
        compare(tc.changedLog[0], ["a"]);

        cfg.authProfilesJson = _json("newer");
        compare(tc.changedLog.length, 2);
        compare(tc.changedLog[1], ["a"]);
    }
}
