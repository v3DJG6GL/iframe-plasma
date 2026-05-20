# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

qt_add_qml_module(iframe_plasma_qml
    URI "io.github.v3DJG6GL.iframe"
    VERSION 1.0
    PLUGIN_TARGET iframe_plasma_qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/io/github/v3DJG6GL/iframe
    SOURCES
        secretsbridge.cpp secretsbridge.h
        basicauthinterceptor.cpp basicauthinterceptor.h
        screenlockmonitor.cpp screenlockmonitor.h
)

# Qt's CMake creates the plugin as a MODULE target which omits the "lib" prefix
# on Linux. System QML plugins (e.g. libqtqmlcoreplugin.so) and qmldir
# `plugin` directives expect the prefix, so force it.
set_target_properties(iframe_plasma_qml PROPERTIES PREFIX "lib")

target_link_libraries(iframe_plasma_qml PRIVATE
    Qt6::DBus
    Qt6::Quick
    Qt6::WebEngineCore
    Qt6::WebEngineQuick
    KF6::Wallet
    KF6::I18n
)

# Install the plugin .so and qmldir into the QML import tree
install(TARGETS iframe_plasma_qml
    LIBRARY DESTINATION "${KDE_INSTALL_QMLDIR}/io/github/v3DJG6GL/iframe"
    RUNTIME DESTINATION "${KDE_INSTALL_QMLDIR}/io/github/v3DJG6GL/iframe")
install(FILES
    "${CMAKE_BINARY_DIR}/qml/io/github/v3DJG6GL/iframe/qmldir"
    DESTINATION "${KDE_INSTALL_QMLDIR}/io/github/v3DJG6GL/iframe")
