#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Build the Arch package inside an archlinux:base-devel container, as root.
# Used by release.yml's `arch` job; also runs locally from the repo root:
#   docker run --rm -v "$PWD:/src" -w /src archlinux:base-devel packaging/arch/ci-build.sh
# Output: packaging/arch/iframe-plasma-<ver>-<rel>-x86_64.pkg.tar.zst (+ .sha256)
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"

# git/jq for this script and release.yml, namcap for the lint. -Syu because a
# partial upgrade (-Sy without -u) is unsupported on Arch.
pacman -Syu --noconfirm --needed git jq namcap
# depends= and makedepends=, so makepkg (run without --syncdeps, it has no
# root) finds them.
# shellcheck disable=SC1091
deps=$(source packaging/arch/PKGBUILD && printf '%s\n' "${depends[@]}" "${makedepends[@]}")
# shellcheck disable=SC2086
pacman -S --noconfirm --needed $deps

ver=$(scripts/version.sh)
pkgname=iframe-plasma
echo "packaging $pkgname $ver"

# The checkout may belong to another uid (bind mount, runner workspace).
git config --global --add safe.directory "$root"
rm -f "packaging/arch/$pkgname-"*.tar.gz "packaging/arch/$pkgname-"*.pkg.tar.zst*
git archive --prefix="$pkgname-$ver/" -o "packaging/arch/$pkgname-$ver.tar.gz" HEAD

# makepkg refuses to run as root.
id builder >/dev/null 2>&1 || useradd -m builder
work=$(mktemp -d)
cp packaging/arch/PKGBUILD "packaging/arch/$pkgname-$ver.tar.gz" "$work/"
chown -R builder: "$work"
sed -i "s/^pkgver=.*/pkgver=$ver/" "$work/PKGBUILD"
su builder -c "cd '$work' && makepkg --noconfirm --cleanbuild"

pkg=$(find "$work" -maxdepth 1 -name "$pkgname-$ver-*-x86_64.pkg.tar.zst" -print -quit)
[ -n "$pkg" ] || { echo "makepkg produced no package" >&2; exit 1; }
# The C++ plugin must land in Qt's own QML import path, or plasmashell can't
# load it without a QML_IMPORT_PATH tweak. No `grep -q`: it exits on the first
# match, bsdtar then dies of SIGPIPE on the entries after the .so, and pipefail
# turns that into a false "plugin not under" failure.
bsdtar -tf "$pkg" | grep '^usr/lib/qt6/qml/io/github/v3DJG6GL/iframe/libiframe_plasma_qml.so$' >/dev/null \
  || { echo "plugin not under usr/lib/qt6/qml in $pkg" >&2; bsdtar -tf "$pkg" >&2; exit 1; }
# Lint only: namcap's dependency hints are advice, not a gate.
namcap "$work/PKGBUILD" "$pkg" || true
cp "$pkg" packaging/arch/
cd packaging/arch
f=$(basename "$pkg")
sha256sum "$f" > "$f.sha256"
ls -l ./*.pkg.tar.zst*
