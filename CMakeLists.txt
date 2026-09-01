# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

cmake_minimum_required(VERSION 3.20)
project(iframe-plasma VERSION 0.1.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.7.0")
set(KF6_MIN_VERSION "6.0.0")

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)
include(ECMFindQmlModule)
include(ECMQtDeclareLoggingCategory)
include(FeatureSummary)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS
    Core DBus Quick Qml WebEngineCore WebEngineQuick)

find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    Wallet I18n CoreAddons Package)

find_package(Plasma 6.0.0 REQUIRED)

# C++ QML plugin (io.github.v3DJG6GL.iframe 1.0)
add_subdirectory(src)

# Plasma applet package (QML, metadata, config)
plasma_install_package(package io.github.v3DJG6GL.iframe-plasma)

# Logging categories (kdebugsettings). The QML side declares them in
# package/contents/ui/Log.qml, the C++ plugin in src/*.cpp; the names and
# Info default must stay in sync with those declarations. Everything under
# io.github.v3djg6gl.iframe.* is debug-off by default; enable with
#   QT_LOGGING_RULES="io.github.v3djg6gl.iframe.*.debug=true"
set(_ifp_log_export IFRAME_PLASMA)
function(_ifp_log_category name description)
    ecm_qt_export_logging_category(
        IDENTIFIER "IFP_${name}"
        CATEGORY_NAME "io.github.v3djg6gl.iframe.${name}"
        DEFAULT_SEVERITY Info
        DESCRIPTION "iframe Plasma: ${description}"
        EXPORT ${_ifp_log_export}
        ${ARGN})
endfunction()
_ifp_log_category(auth      "auth profiles, header injection, credential dialogs"
    OLD_CATEGORY_NAMES iframeplasma.auth)
_ifp_log_category(load      "page loads, retries, renderer crashes, certificate errors")
_ifp_log_category(policy    "denied permissions, dialogs, navigations, downloads")
_ifp_log_category(thumb     "panel thumbnail crop and keyword exclusion")
_ifp_log_category(picker    "interactive panel-selector picker")
_ifp_log_category(config    "configuration parsing and startup capability checks")
_ifp_log_category(page      "console output forwarded from embedded web pages")
_ifp_log_category(lifecycle "freeze/discard lifecycle and screen-lock handling"
    OLD_CATEGORY_NAMES iframeplasma.lock)
ecm_qt_install_logging_categories(
    EXPORT ${_ifp_log_export}
    FILE iframe-plasma.categories
    DESTINATION "${KDE_INSTALL_LOGGINGCATEGORIESDIR}")

# Widget icon
install(FILES data/io.github.v3DJG6GL.iframe-plasma.svg
    DESTINATION ${KDE_INSTALL_FULL_ICONDIR}/hicolor/scalable/apps
    OPTIONAL)

# Test suite — opt-in via -DBUILD_TESTING=ON; KDECMakeSettings already defines
# the BUILD_TESTING option but defaults it to ON. We keep that default and
# only add the subdirectory when enabled so packagers can skip tests cleanly.
if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)
