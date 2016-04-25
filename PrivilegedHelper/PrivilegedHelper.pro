# -----------------------------------------------------------------------------------
# ! @author mbsanchez
# ! @date 22/04/2016
#
# Copyright 2016 mbsanchez. All rights reserved.
#
# This file is part of PrivilegedHelperExample.
#
# PrivilegedHelperExample is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2
# as published by the Free Software Foundation.
#
# PrivilegedHelperExample is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file LICENSE included with this
# distribution); if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# or see http://www.gnu.org/licenses/.
# -----------------------------------------------------------------------------------

QT += core
QT -= gui

TARGET = com.mbs.PrivilegedHelper
CONFIG += console
CONFIG -= app_bundle

TEMPLATE = app

QMAKE_LFLAGS += -F /System/Library/Frameworks/Security.framework/ -sectcreate __TEXT __info_plist $$PWD/PrivilegedHelper-Info.plist -sectcreate __TEXT __launchd_plist $$PWD/PrivilegedHelper-Launchd.plist
LIBS += -framework Security -framework Cocoa

CONFIG(debug, debug|release) {
    DESTDIR = ../
}
CONFIG(release, debug|release) {
    DESTDIR = ../
}

SOURCES += main.cpp

DISTFILES += \
    PrivilegedHelper-Info.plist \
    PrivilegedHelper-Launchd.plist

HEADERS += \
    ../common/SSPrivilegedHelperCommon.h

include (../common/certificate.pri)

# Bundle identifier for your application
BUNDLEID = $${TARGET}

HOSTAPP_IDENTIFIER = com.mbs.HostApp

QMAKE_PRE_LINK += /usr/libexec/PlistBuddy -c \"Set :SMAuthorizedClients:0 'anchor apple generic and identifier $${HOSTAPP_IDENTIFIER} and (certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = $${CERT_OU})'\" $$PWD/PrivilegedHelper-Info.plist;

QMAKE_CFLAGS_RELEASE = $$QMAKE_CFLAGS_RELEASE_WITH_DEBUGINFO
QMAKE_CXXFLAGS_RELEASE = $$QMAKE_CXXFLAGS_RELEASE_WITH_DEBUGINFO
QMAKE_OBJECTIVE_CFLAGS_RELEASE =  $$QMAKE_OBJECTIVE_CFLAGS_RELEASE_WITH_DEBUGINFO
QMAKE_LFLAGS_RELEASE = $$QMAKE_LFLAGS_RELEASE_WITH_DEBUGINFO

# Extract debug symbols
codesigner.commands += dsymutil $${DESTDIR}$${TARGET} -o $${DESTDIR}$${TARGET}.dSYM;

# Sign the application, using the provided entitlements
CODESIGN_ALLOCATE_PATH=$$system(xcrun -find codesign_allocate)
codesigner.commands += export CODESIGN_ALLOCATE=$${CODESIGN_ALLOCATE_PATH};
codesigner.commands += codesign --force --sign $${CERTSHA1} -r=\"designated => anchor apple generic and identifier $${BUNDLEID} and ((cert leaf[field.1.2.840.113635.100.6.1.9] exists) or (certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU]=$${CERT_OU}))\" --timestamp=none $${DESTDIR}$${TARGET};

first.depends = $(first) codesigner
export(first.depends)
export(codesigner.commands)
QMAKE_EXTRA_TARGETS += first codesigner
