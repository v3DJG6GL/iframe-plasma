#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# The project version lives in two files that must agree:
#   CMakeLists.txt         project(iframe-plasma VERSION X.Y.Z …)  → package version
#   package/metadata.json  KPlugin.Version                         → shown by Plasma
#
#   scripts/version.sh                          print the current version
#   scripts/version.sh --check                  fail unless both files agree
#   scripts/version.sh patch|minor|major|X.Y.Z  set the new version in both files,
#       turn CHANGELOG.md's [Unreleased] section into [X.Y.Z] — <today> (leaving
#       an empty [Unreleased] above it) and print the new version
#
# Used by .forgejo/workflows/release.yml; no dependencies beyond sed and awk.
set -euo pipefail
cd "$(dirname "$0")/.."

cmake_version() {
    sed -nE 's/^project\(iframe-plasma VERSION ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' CMakeLists.txt
}

metadata_version() {
    sed -nE 's/^[[:space:]]*"Version":[[:space:]]*"([^"]*)".*/\1/p' package/metadata.json
}

die() {
    echo "version.sh: $*" >&2
    exit 1
}

current=$(cmake_version)
[ -n "$current" ] || die "no project(iframe-plasma VERSION X.Y.Z) in CMakeLists.txt"

case "${1:-}" in
    '')
        echo "$current"
        exit 0
        ;;
    --check)
        meta=$(metadata_version)
        [ "$meta" = "$current" ] \
            || die "CMakeLists.txt says $current but package/metadata.json says ${meta:-nothing}"
        exit 0
        ;;
esac

IFS=. read -r major minor patch <<<"$current"
case "$1" in
    major) new="$((major + 1)).0.0" ;;
    minor) new="$major.$((minor + 1)).0" ;;
    patch) new="$major.$minor.$((patch + 1))" ;;
    *)
        [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "expected patch, minor, major or X.Y.Z, got '$1'"
        new=$1
        ;;
esac

grep -q '^## \[Unreleased\]' CHANGELOG.md || die "CHANGELOG.md has no '## [Unreleased]' section"
if grep -qF "## [$new]" CHANGELOG.md; then
    die "CHANGELOG.md already has a [$new] section"
fi

sed -i -E "s/^(project\(iframe-plasma VERSION )[0-9.]+/\1$new/" CMakeLists.txt
sed -i -E "s/^([[:space:]]*\"Version\":[[:space:]]*\")[^\"]*/\1$new/" package/metadata.json

awk -v version="$new" -v today="$(date +%F)" '
    !done && /^## \[Unreleased\]/ {
        print
        print ""
        print "## [" version "] — " today
        done = 1
        next
    }
    { print }
' CHANGELOG.md >CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md

# Read both back: a sed pattern that stopped matching must not pass silently.
[ "$(cmake_version)" = "$new" ] || die "failed to set $new in CMakeLists.txt"
[ "$(metadata_version)" = "$new" ] || die "failed to set $new in package/metadata.json"

echo "$new"
