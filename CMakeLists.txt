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
include(FeatureSummary)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS
    Core Quick Qml WebEngineCore WebEngineQuick)

find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    Wallet I18n CoreAddons Package)

find_package(Plasma 6.0.0 REQUIRED)

# C++ QML plugin (io.github.v3DJG6GL.iframe 1.0)
add_subdirectory(src)

# Plasma applet package (QML, metadata, config)
plasma_install_package(package io.github.v3DJG6GL.iframe-plasma)

# Widget icon
install(FILES data/io.github.v3DJG6GL.iframe-plasma.svg
    DESTINATION ${KDE_INSTALL_FULL_ICONDIR}/hicolor/scalable/apps
    OPTIONAL)

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)
