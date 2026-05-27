/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Entry point for the Qt Quick Test binary. Discovers every tst_*.qml file
 * under QUICK_TEST_SOURCE_DIR and runs its TestCase blocks. The import path
 * is extended in the CMake invocation to point at the production
 * package/contents/ui/ tree so tests can import sanitize.js, CropEngine.js,
 * and any QML helpers by relative URL.
 */
#include <QtQuickTest>
QUICK_TEST_MAIN(qmltests)
