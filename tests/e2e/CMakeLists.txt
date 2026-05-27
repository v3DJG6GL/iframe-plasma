# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# End-to-end WebEngine tests. Each binary spawns the Python fixture HTTP
# server in tests/fixtures/httpd/ as a subprocess, then drives a real
# QQuickWebEngineProfile + BasicAuthInterceptor against it.
#
# These tests require a working GL stack (xvfb in CI). Locally they
# usually run under the user's display; gate with -L e2e so CI workflows
# without xvfb skip them cleanly.

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS WebEngineCore WebEngineQuick)

function(iframe_add_e2e_test test_name)
    cmake_parse_arguments(IFP "" "" "SOURCES;LIBS" ${ARGN})
    ecm_add_test(${test_name}.cpp ${IFP_SOURCES}
        TEST_NAME ${test_name}
        NAME_PREFIX "iframe-e2e-"
        LINK_LIBRARIES
            Qt6::Test Qt6::Core Qt6::Qml Qt6::Quick
            Qt6::WebEngineCore Qt6::WebEngineQuick
            ${IFP_LIBS}
    )
    set_tests_properties("iframe-e2e-${test_name}" PROPERTIES
        ENVIRONMENT
            "QTWEBENGINE_DISABLE_SANDBOX=1;QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox --disable-gpu --disable-dev-shm-usage;QT_QUICK_BACKEND=software;IFRAME_FIXTURE_HTTPD=${CMAKE_SOURCE_DIR}/tests/fixtures/httpd/server.py"
        LABELS "e2e"
        TIMEOUT 60)
    target_include_directories(${test_name} PRIVATE "${CMAKE_SOURCE_DIR}/src")
endfunction()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tst_auth_injection.cpp")
    iframe_add_e2e_test(tst_auth_injection
        SOURCES "${CMAKE_SOURCE_DIR}/src/basicauthinterceptor.cpp")
endif()
