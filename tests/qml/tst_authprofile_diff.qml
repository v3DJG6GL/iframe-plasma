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

    // ===== ids naming Object.prototype members ======================
    // isSafeAuthProfileId accepts them and a Backup import can carry one.
    // A "__proto__" write threw (aborting main.qml's auth priming), and
    // "constructor" / "toString" were diffed against inherited functions.
    function test_bodies_protoIdIsOwnKey() {
        const b = U.authProfileBodies([{ id: "__proto__" }, { id: "a" }]);
        compare(Object.keys(b).sort(), ["__proto__", "a"]);
        compare(b["__proto__"], JSON.stringify({ id: "__proto__" }));
    }
    function test_changed_prototypeNameIdRemoved() {
        compare(U.changedAuthProfileIds(U.authProfileBodies([{ id: "toString" }]), {}),
                ["toString"]);
    }
    function test_changed_prototypeNameIdAdded() {
        compare(U.changedAuthProfileIds({}, U.authProfileBodies([{ id: "constructor" }])),
                ["constructor"]);
    }
    function test_changed_prototypeNameIdBodyDiffers() {
        compare(U.changedAuthProfileIds(
            U.authProfileBodies([{ id: "valueOf", username: "u" }]),
            U.authProfileBodies([{ id: "valueOf", username: "v" }])), ["valueOf"]);
    }
    function test_changed_prototypeNameIdUnchanged() {
        compare(U.changedAuthProfileIds(
            U.authProfileBodies([{ id: "hasOwnProperty" }]),
            U.authProfileBodies([{ id: "hasOwnProperty" }])), []);
    }

    // ===== groupAuthHosts (primeAuthProfiles' grouping) ==============
    function _group(tabs, profiles) {
        const byId = Object.create(null);
        for (const p of profiles) byId[p.id] = p;
        return U.groupAuthHosts(tabs, id => byId[id], t => U.authKey(t.url));
    }
    function test_group_hostsPerProfile() {
        const g = _group([
            { url: "https://a.example/x", authProfileId: "p" },
            { url: "https://a.example/y", authProfileId: "p" },
            { url: "https://b.example/", authProfileId: "p" },
            { url: "https://c.example/", authProfileId: "" },
            { url: "https://d.example/", authProfileId: "missing" }
        ], [{ id: "p" }]);
        compare(Object.keys(g), ["p"]);
        compare(g.p.hosts, [U.authKey("https://a.example/x"), U.authKey("https://b.example/")]);
    }
    function test_group_hostThrowSkipsOnlyThatTab() {
        const g = U.groupAuthHosts([
            { url: "bad", authProfileId: "p" },
            { url: "https://a.example/", authProfileId: "p" }
        ], id => ({ id: id }), t => {
            if (t.url === "bad") throw new Error("unparsable");
            return U.authKey(t.url);
        });
        compare(g.p.hosts, [U.authKey("https://a.example/")]);
    }
    // A plain {} map read an inherited member for these ids and threw on
    // `.hosts`, which aborted the priming of every profile.
    function test_group_prototypeNameIdsAreOwnKeys() {
        const ids = ["constructor", "toString", "__proto__", "valueOf", "hasOwnProperty"];
        const tabs = [{ url: "https://good.example/", authProfileId: "good" }];
        for (const id of ids) tabs.push({ url: "https://" + id.replace(/_/g, "u") + ".example/", authProfileId: id });
        const g = _group(tabs, [{ id: "good" }].concat(ids.map(id => ({ id: id }))));
        compare(Object.keys(g).sort(), ["good"].concat(ids).sort());
        compare(g.good.hosts, [U.authKey("https://good.example/")]);
        compare(g["__proto__"].hosts, [U.authKey("https://uuprotouu.example/")]);
        compare(g.constructor.hosts, [U.authKey("https://constructor.example/")]);
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
