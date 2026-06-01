#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Regression gate that enforces the plan's "coverage spot-check" verification:
every KConfigXT entry in package/contents/config/main.xml MUST be either

  1. referenced by name from a test source under tests/, OR
  2. allowlisted below with a one-line rationale.

Run via `ctest` (registered in tests/CMakeLists.txt) or directly:

    python3 tests/fixtures/check_kcfg_coverage.py

Exits 0 when every entry has coverage or is allowlisted; 1 with the list
of unreferenced entries otherwise.

Allowlisted entries are visibility/passthrough keys with no decision
logic to drive — adding them to the allowlist forces a contributor to
either write a real test or, if the entry truly is logic-free, explain
why in the line below.
"""
from __future__ import annotations

import pathlib
import re
import sys
import xml.etree.ElementTree as ET


ROOT = pathlib.Path(__file__).resolve().parents[2]
KCFG = ROOT / "package" / "contents" / "config" / "main.xml"
TESTS = ROOT / "tests"
LIBS = ROOT / "package" / "contents" / "ui"
CONFIG_BACKUP = LIBS / "ConfigBackup.qml"

# Keys deliberately NOT round-tripped through Backup export/import. Keep in
# sync with the kSchema comment in src/backupbridge.cpp and the kExcluded
# set in tests/cpp/tst_backupbridge.cpp's schema guard.
BACKUP_EXCLUDE = {"authProfilesSecretsSerial"}

# Entries this script does NOT require to appear in a test. Each line
# must justify why — the gate exists to force contributors to think,
# not to be silenceable by convenience.
ALLOWLIST = {
    "zoomFactor":                  "passthrough property to WebEngineView.zoomFactor",
    "showTabBar":                  "TabBar.visible binding, no decision logic",
    "compactPreviewEnabled":       "compact representation visibility gate",
    "compactPreviewLongAxisPx":    "passthrough size to compact rep",
    "popupPinned":                 "binding to hideOnWindowDeactivate",
    "userAgentOverride":           "passthrough to WebEngineProfile.httpUserAgent (sanitised in main.qml; sanitiser itself is shared with sanitize.js which is covered)",
    "remoteDebuggingPort":         "passthrough to WebTab.debugPort",
}


def collect_entry_names() -> list[str]:
    tree = ET.parse(KCFG)
    ns = "{http://www.kde.org/standards/kcfg/1.0}"
    return [e.attrib["name"] for e in tree.iter(f"{ns}entry") if "name" in e.attrib]


def find_references(name: str) -> list[pathlib.Path]:
    """Return the list of test/library files mentioning `name` verbatim."""
    pattern = re.compile(r"\b" + re.escape(name) + r"\b")
    hits = []
    for root in (TESTS, LIBS):
        for f in root.rglob("*"):
            if not f.is_file():
                continue
            if f.suffix not in {".qml", ".cpp", ".h", ".js", ".mjs", ".py", ".ini"}:
                continue
            try:
                if pattern.search(f.read_text(errors="ignore")):
                    hits.append(f)
            except OSError:
                continue
    return hits


def check_backup_lists() -> int:
    """Guard the Backup KCM page's two hand-maintained key lists against
    main.xml. The real ConfigBackup.qml can't be loaded under the bare
    qmltests harness (it pulls org.kde.kcmutils + the C++ plugin), and KCM
    dirty-tracking requires literal named cfg_<key> aliases — so the lists
    can't be generated and are guarded by static extraction instead.

    Asserts: (C) the `property alias cfg_<key>` set, (D) the _collectConfig()
    object-literal key set, and (A) main.xml's entries minus BACKUP_EXCLUDE
    are all identical. A key added to main.xml + kSchema but forgotten in
    either QML list would otherwise silently never export."""
    text = CONFIG_BACKUP.read_text()

    aliases = set(re.findall(r"property\s+alias\s+cfg_(\w+)\s*:", text))

    collect_match = re.search(r"_collectConfig\s*\(\)\s*\{(.*?)\n\s*\}", text, re.S)
    if not collect_match:
        print("FAIL: could not locate _collectConfig() literal in ConfigBackup.qml",
              file=sys.stderr)
        return 1
    collected = set(re.findall(r"^\s*(\w+)\s*:", collect_match.group(1), re.M))

    expected = set(collect_entry_names()) - BACKUP_EXCLUDE

    problems = []
    if aliases != expected:
        problems.append(("cfg_ aliases vs main.xml schema", aliases ^ expected))
    if collected != expected:
        problems.append(("_collectConfig keys vs main.xml schema", collected ^ expected))
    if aliases != collected:
        problems.append(("cfg_ aliases vs _collectConfig keys", aliases ^ collected))

    if problems:
        print("ConfigBackup.qml backup lists are out of sync:", file=sys.stderr)
        for label, diff in problems:
            print(f"  - {label}: differ by {sorted(diff)}", file=sys.stderr)
        print("\nEvery backup key must appear in main.xml, the cfg_ aliases, and",
              "_collectConfig() (minus BACKUP_EXCLUDE). Update the missing list.",
              file=sys.stderr)
        return 1

    print(f"backup list consistency OK — {len(expected)} keys mirrored across "
          f"main.xml, cfg_ aliases, and _collectConfig.")
    return 0


def check_coverage() -> int:
    names = collect_entry_names()
    if not names:
        print("FAIL: no kcfg entries found — main.xml moved or empty?", file=sys.stderr)
        return 1

    unreferenced = []
    for name in names:
        if find_references(name):
            continue
        if name in ALLOWLIST:
            continue
        unreferenced.append(name)

    if unreferenced:
        print("kcfg coverage FAILED — the following entries are not referenced by",
              "any test or .pragma library file and are not in the allowlist:",
              file=sys.stderr)
        for name in unreferenced:
            print(f"  - {name}", file=sys.stderr)
        print("\nEither add a test that references the entry by name, or add it",
              "to ALLOWLIST in this script with a one-line rationale.",
              file=sys.stderr)
        return 1

    print(f"kcfg coverage OK — {len(names)} entries, "
          f"{len(ALLOWLIST)} allowlisted, "
          f"{len(names) - len(ALLOWLIST)} with explicit test references.")
    return 0


def main() -> int:
    # Run both gates and report all failures (don't short-circuit) so a
    # contributor sees every problem in one run. Non-zero if either fails.
    rc = 0
    rc |= check_coverage()
    rc |= check_backup_lists()
    return rc


if __name__ == "__main__":
    sys.exit(main())
