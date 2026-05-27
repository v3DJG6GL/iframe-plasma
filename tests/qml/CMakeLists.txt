# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Qt Quick Test binary. Discovers tst_*.qml files in this directory at
# run time via the QUICK_TEST_SOURCE_DIR define, then registers itself
# with CTest under the "qml" label.

add_executable(qmltests tst_main.cpp)
target_link_libraries(qmltests PRIVATE
    Qt6::QuickTest Qt6::Qml Qt6::Quick)
target_compile_definitions(qmltests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")

add_test(NAME iframe-qml-qmltests
    COMMAND qmltests
        -import "${CMAKE_SOURCE_DIR}/package/contents/ui"
        -input "${CMAKE_CURRENT_SOURCE_DIR}")
set_tests_properties(iframe-qml-qmltests PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
    LABELS "qml")
