# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Top-level gate. Subdirectories register themselves as labelled CTest
# entries so `ctest -L cpp|qml|js|e2e|smoke` slices the suite.
find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test QuickTest Concurrent)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

add_subdirectory(cpp)
add_subdirectory(qml)
add_subdirectory(js)
add_subdirectory(e2e)
add_subdirectory(smoke)
