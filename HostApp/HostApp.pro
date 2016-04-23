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
    DESTDIR = ../
}
CONFIG(release, debug|release) {
    DESTDIR = ../
}

INFO_PLIST_PATH = $$shell_quote($${DESTDIR}$${TARGET}.app/Contents/Info.plist)

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

HELPER_IDENTIFIER = com.mbs.PrivilegedHelper

plist.commands += $(COPY) $$PWD/Info.plist $${INFO_PLIST_PATH};
plist.commands += /usr/libexec/PlistBuddy -c \"Set :CFBundleIdentifier com.mbs.$${TARGET}\" $${INFO_PLIST_PATH};
plist.commands += /usr/libexec/PlistBuddy -c \"Set :SMPrivilegedExecutables:$${HELPER_IDENTIFIER} 'anchor apple generic and identifier $${HELPER_IDENTIFIER} and (certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = $${CERT_OU})'\" $${INFO_PLIST_PATH};
first.depends = $(first) plist
export(first.depends)
export(plist.commands)
QMAKE_EXTRA_TARGETS += first plist
