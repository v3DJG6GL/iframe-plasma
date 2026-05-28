# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Project-wide cmake-lint config. (cmake-format hook is disabled in
# .pre-commit-config.yaml because no format setting we tried preserves the
# codebase's grouped/column-aligned `ecm_add_test` blocks; cmake-lint
# still reads this file and respects the format.* keys when computing
# line-length lints.)
#
# Python format (not YAML) because the pre-commit cmakelang venv ships
# without PyYAML — see cheshirekow/cmake-format-precommit#71.
#
# - format.line_width 100: matches the project's existing visual budget.
# - lint.disabled_codes: C0111 (missing docstring) is noise on internal
#   CMake helpers like iframe_add_e2e_test; C0301 (line too long) trips on
#   ENVIRONMENT lists where the value embeds an absolute path that can't
#   reasonably be split.

with section("format"):
    line_width = 100
    tab_size = 4

with section("lint"):
    disabled_codes = ["C0111", "C0301"]
