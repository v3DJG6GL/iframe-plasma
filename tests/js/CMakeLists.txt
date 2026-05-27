# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Node + jsdom tests for CropEngine.js. Run via `node --test` (Node 18+)
# against the production library — no copy, no shim. devDependency on jsdom
# is installed once via `npm install` (CTest's setup fixture does that on
# first run if the node_modules tree is missing).

find_program(NODEJS NAMES node nodejs)
find_program(NPMJS NAMES npm)

if(NOT NODEJS OR NOT NPMJS)
    message(STATUS "Node.js or npm not found; skipping JS tests")
    return()
endif()

# Install / refresh devDependencies. ctest will only run this if it sees
# the package.json change (via FILE_DEPENDS won't work with add_test, so
# we do it unconditionally — npm install is a no-op when node_modules
# is up to date).
add_test(NAME iframe-js-install
    COMMAND ${NPMJS} install --silent
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
set_tests_properties(iframe-js-install PROPERTIES
    FIXTURES_SETUP js_deps
    LABELS "js")

add_test(NAME iframe-js-cropengine
    COMMAND ${NODEJS} --test cropengine.test.mjs
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
set_tests_properties(iframe-js-cropengine PROPERTIES
    FIXTURES_REQUIRED js_deps
    LABELS "js")
