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

QT       += core gui

greaterThan(QT_MAJOR_VERSION, 4): QT += widgets

TARGET = HostApp
TEMPLATE = app

QMAKE_LFLAGS += -F /System/Library/Frameworks/Security.framework/
QMAKE_LFLAGS += -F /System/Library/Frameworks/ServiceManagement.framework/
QMAKE_LFLAGS += -F /System/Library/Frameworks/Cocoa.framework/
QMAKE_LFLAGS += -F /System/Library/Frameworks/Foundation.framework/
LIBS += -framework Security -framework Cocoa -framework Foundation -framework ServiceManagement

CONFIG(debug, debug|release) {
    DESTDIR = $$clean_path($$OUT_PWD/../..)
}
CONFIG(release, debug|release) {
    DESTDIR = $$clean_path($$OUT_PWD/../..)
}

INFO_PLIST_PATH = $$shell_quote($${DESTDIR}/$${TARGET}.app/Contents/Info.plist)
HELPERAPP_INFO = PrivilegedHelper-Info.plist
HELPER_APP_LAUNCHD_INFO = PrivilegedHelper-Launchd.plist
TOOLAPP = com.mbs.ExampleTool
HELPER_IDENTIFIER = com.mbs.PrivilegedHelper

SOURCES += main.cpp\
        mainwindow.cpp

HEADERS  += mainwindow.h \
        ../common/SSPrivilegedHelperCommon.h \
        smjobbless.h

FORMS    += mainwindow.ui

DISTFILES += \
    Info.plist

OBJECTIVE_SOURCES += \
    smjobbless.mm

include (../common/certificate.pri)

QMAKE_POST_LINK += $(COPY) $$PWD/Info.plist $${INFO_PLIST_PATH}$$escape_expand(\n\t)
QMAKE_POST_LINK += /usr/libexec/PlistBuddy -c \"Set :CFBundleIdentifier com.mbs.$${TARGET}\" $${INFO_PLIST_PATH}$$escape_expand(\n\t)
QMAKE_POST_LINK += /usr/libexec/PlistBuddy -c \'Set :SMPrivilegedExecutables:$${HELPER_IDENTIFIER} 'anchor apple generic and identifier \\\"$${HELPER_IDENTIFIER}\\\" and (certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = \\\"$${CERT_OU}\\\")'\' $${INFO_PLIST_PATH}$$escape_expand(\n\t)

# Commands to organize the bundle app
QMAKE_POST_LINK += $(MKDIR) $${DESTDIR}/$${TARGET}.app/Contents/Library/LaunchServices$$escape_expand(\n\t)
QMAKE_POST_LINK += $(MOVE) $${DESTDIR}/$${HELPER_IDENTIFIER} $${DESTDIR}/$${TARGET}.app/Contents/Library/LaunchServices$$escape_expand(\n\t)
QMAKE_POST_LINK += $(COPY) $$clean_path($${PWD}/../PrivilegedHelper/$${HELPERAPP_INFO}) $${DESTDIR}/$${TARGET}.app/Contents/Resources$$escape_expand(\n\t)
QMAKE_POST_LINK += $(COPY) $$clean_path($${PWD}/../PrivilegedHelper/$${HELPER_APP_LAUNCHD_INFO}) $${DESTDIR}/$${TARGET}.app/Contents/Resources$$escape_expand(\n\t)
QMAKE_POST_LINK += $(MOVE) $${DESTDIR}/$${TOOLAPP} $${DESTDIR}/$${TARGET}.app/Contents/Resources$$escape_expand(\n\t)

# Bundle identifier for your application
BUNDLEID = com.mbs.$${TARGET}

QMAKE_CFLAGS_RELEASE = $$QMAKE_CFLAGS_RELEASE_WITH_DEBUGINFO
QMAKE_CXXFLAGS_RELEASE = $$QMAKE_CXXFLAGS_RELEASE_WITH_DEBUGINFO
QMAKE_OBJECTIVE_CFLAGS_RELEASE =  $$QMAKE_OBJECTIVE_CFLAGS_RELEASE_WITH_DEBUGINFO
QMAKE_LFLAGS_RELEASE = $$QMAKE_LFLAGS_RELEASE_WITH_DEBUGINFO

# Extract debug symbols
QMAKE_POST_LINK += dsymutil $${DESTDIR}/$${TARGET}.app/Contents/MacOS/$${TARGET} -o $${DESTDIR}/$${TARGET}.app.dSYM$$escape_expand(\n\t)
QMAKE_POST_LINK += $(COPY_DIR) $${DESTDIR}/$${TARGET}.app.dSYM $${DESTDIR}/$${TARGET}.app/Contents/MacOS/$${TARGET}.dSYM$$escape_expand(\n\t)

# deploy qt dependencies
QMAKE_POST_LINK += macdeployqt $${DESTDIR}/$${TARGET}.app -always-overwrite -codesign=$${CERTSHA1}$$escape_expand(\n\t)

# set the modification and access times of files
QMAKE_POST_LINK += touch -c $${DESTDIR}/$${TARGET}.app$$escape_expand(\n\t)

# Sign the application, using the provided entitlements
CODESIGN_ALLOCATE_PATH=$$system(xcrun -find codesign_allocate)
QMAKE_POST_LINK += export CODESIGN_ALLOCATE=$${CODESIGN_ALLOCATE_PATH}$$escape_expand(\n\t)
QMAKE_POST_LINK += codesign --force --sign $${CERTSHA1} -r=\'designated => anchor apple generic and identifier \"$${BUNDLEID}\" and ((cert leaf[field.1.2.840.113635.100.6.1.9] exists) or (certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU]=\"$${CERT_OU}\"))\' --timestamp=none $$DESTDIR/$${TARGET}.app$$escape_expand(\n\t)
