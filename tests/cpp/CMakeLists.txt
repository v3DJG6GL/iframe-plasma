# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# C++ unit tests for the QML plugin's plain-C++ pieces. Each test recompiles
# the plugin source files it needs (the production plugin is a MODULE target
# and cannot be linked against), then runs headless under
# QT_QPA_PLATFORM=offscreen.

include(ECMAddTests)

# Helper: define a Qt Test executable that pulls in iframe-plasma source
# files plus the test's own .cpp.  `LIBS` extends LINK_LIBRARIES.
function(iframe_add_cpp_test test_name)
    cmake_parse_arguments(IFP "" "" "SOURCES;LIBS" ${ARGN})
    ecm_add_test(${test_name}.cpp ${IFP_SOURCES}
        TEST_NAME ${test_name}
        NAME_PREFIX "iframe-cpp-"
        LINK_LIBRARIES Qt6::Test Qt6::Core ${IFP_LIBS}
    )
    set_tests_properties("iframe-cpp-${test_name}" PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
        LABELS "cpp")
    target_include_directories(${test_name} PRIVATE
        "${CMAKE_SOURCE_DIR}/src"
        "${CMAKE_SOURCE_DIR}/tests/fixtures/fakewallet")
endfunction()

# 1. canonicalizeHost(rawHost, scheme, port)
iframe_add_cpp_test(tst_canonicalizehost
    SOURCES "${CMAKE_SOURCE_DIR}/src/basicauthinterceptor.cpp"
    LIBS    Qt6::WebEngineCore Qt6::WebEngineQuick)

# 2. buildAuthHeader(authType, username, secret, errorReason*)
iframe_add_cpp_test(tst_buildauthheader
    SOURCES "${CMAKE_SOURCE_DIR}/src/basicauthinterceptor.cpp"
    LIBS    Qt6::WebEngineCore Qt6::WebEngineQuick)

# 3. BasicAuthInterceptor class behaviour
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tst_basicauthinterceptor.cpp")
    iframe_add_cpp_test(tst_basicauthinterceptor
        SOURCES "${CMAKE_SOURCE_DIR}/src/basicauthinterceptor.cpp"
        LIBS    Qt6::WebEngineCore Qt6::WebEngineQuick Qt6::Concurrent)
endif()

# 4. SecretsBridge against the FakeWallet in tests/fixtures/fakewallet/.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tst_secretsbridge.cpp")
    iframe_add_cpp_test(tst_secretsbridge
        SOURCES
            "${CMAKE_SOURCE_DIR}/src/secretsbridge.cpp"
            "${CMAKE_SOURCE_DIR}/tests/fixtures/fakewallet/fakewallet.cpp"
        LIBS    Qt6::Qml KF6::Wallet KF6::I18n)
endif()

# 5. ScreenLockMonitor — state-machine half via QMetaObject + DBus
#    subscription via the dbusmock fixture (skips if python3-dbusmock
#    isn't available on the runner).
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tst_screenlockmonitor.cpp")
    iframe_add_cpp_test(tst_screenlockmonitor
        SOURCES "${CMAKE_SOURCE_DIR}/src/screenlockmonitor.cpp"
        LIBS    Qt6::Qml Qt6::DBus)
    # Append the dbusmock fixture path on top of whatever the helper
    # already set (QT_QPA_PLATFORM=offscreen) — ENVIRONMENT_MODIFICATION
    # merges per-entry, but we set it via the simpler ENVIRONMENT list.
    set_tests_properties("iframe-cpp-tst_screenlockmonitor" PROPERTIES
        ENVIRONMENT
            "QT_QPA_PLATFORM=offscreen;IFRAME_DBUSMOCK_SCREENSAVER=${CMAKE_SOURCE_DIR}/tests/fixtures/dbusmock/screensaver.py")
endif()
