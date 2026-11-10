# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# CPack: binary .deb + .tar.gz of the install tree. Used by the release
# workflow; locally:
#   cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
#   cmake --build build && cpack --config build/CPackConfig.cmake -B dist
# The prefix must be /usr: KDEInstallDirs computes absolute destinations at
# configure time, so CPACK_SET_DESTDIR stages them under the package root.

set(CPACK_PACKAGE_NAME "iframe-plasma")
set(CPACK_PACKAGE_VENDOR "v3DJG6GL")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY
    "Plasma 6 widget that embeds web pages with live panel thumbnails")
set(CPACK_PACKAGE_HOMEPAGE_URL
    "https://forgejo.informethic.ch/v3djg6gl/iframe-plasma")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
set(CPACK_GENERATOR "DEB;TGZ")
set(CPACK_SET_DESTDIR ON)
set(CPACK_PACKAGING_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")
set(CPACK_STRIP_FILES ON)

set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
set(CPACK_DEBIAN_PACKAGE_MAINTAINER
    "v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>")
set(CPACK_DEBIAN_PACKAGE_SECTION "kde")
# Shared-library deps come from dpkg-shlibdeps; QML-only runtime modules
# are not linked, so they are listed by hand.
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
set(CPACK_DEBIAN_PACKAGE_DEPENDS "plasma-workspace, qml6-module-qtwebengine")

include(CPack)
