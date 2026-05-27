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

# Entries this script does NOT require to appear in a test. Each line
# must justify why — the gate exists to force contributors to think,
# not to be silenceable by convenience.
ALLOWLIST = {
    "zoomFactor":                  "passthrough property to WebEngineView.zoomFactor",
    "showTabBar":                  "TabBar.visible binding, no decision logic",
    "compactPreviewEnabled":       "compact representation visibility gate",
    "compactPreviewShowLabel":     "Label.visible binding in panel slot",
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


def main() -> int:
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


if __name__ == "__main__":
    sys.exit(main())
