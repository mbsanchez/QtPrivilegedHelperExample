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

TEMPLATE = subdirs

SUBDIRS += PrivilegedHelper ExampleTool HostApp

# Bundle App name

BUNDLEAPP = HostApp
HELPERAPP = com.mbs.PrivilegedHelper
TOOLAPP = com.mbs.ExampleTool
HELPERAPP_INFO = PrivilegedHelper-Info.plist
HELPER_APP_LAUNCHD_INFO = PrivilegedHelper-Launchd.plist

# Commands to organize the bundle app
organizer.commands += $(MKDIR) $$OUT_PWD/$${BUNDLEAPP}.app/Contents/Library/LaunchServices;
organizer.commands += $(MOVE) $$OUT_PWD/$${HELPERAPP} $$OUT_PWD/$${BUNDLEAPP}.app/Contents/Library/LaunchServices;
organizer.commands += $(COPY) $$PWD/PrivilegedHelper/$${HELPERAPP_INFO} $$OUT_PWD/$${BUNDLEAPP}.app/Contents/Resources;
organizer.commands += $(COPY) $$PWD/PrivilegedHelper/$${HELPER_APP_LAUNCHD_INFO} $$OUT_PWD/$${BUNDLEAPP}.app/Contents/Resources;
organizer.commands += $(MOVE) $$OUT_PWD/$${TOOLAPP} $$OUT_PWD/$${BUNDLEAPP}.app/Contents/Resources;

include (common/certificate.pri)

# Bundle identifier for your application
BUNDLEID = com.mbs.$${BUNDLEAPP}

QMAKE_CFLAGS_RELEASE = $$QMAKE_CFLAGS_RELEASE_WITH_DEBUGINFO
QMAKE_CXXFLAGS_RELEASE = $$QMAKE_CXXFLAGS_RELEASE_WITH_DEBUGINFO
QMAKE_OBJECTIVE_CFLAGS_RELEASE =  $$QMAKE_OBJECTIVE_CFLAGS_RELEASE_WITH_DEBUGINFO
QMAKE_LFLAGS_RELEASE = $$QMAKE_LFLAGS_RELEASE_WITH_DEBUGINFO

# Extract debug symbols
codesigner.commands += dsymutil $${OUT_PWD}/$${BUNDLEAPP}.app/Contents/MacOS/$${BUNDLEAPP} -o $${OUT_PWD}/$${BUNDLEAPP}.app.dSYM;
codesigner.commands += $(COPY_DIR) $${OUT_PWD}/$${BUNDLEAPP}.app.dSYM $${OUT_PWD}/$${BUNDLEAPP}.app/Contents/MacOS/$${BUNDLEAPP}.dSYM;

# deploy qt dependencies
codesigner.commands += macdeployqt $${OUT_PWD}/$${BUNDLEAPP}.app -always-overwrite -codesign=$${CERTSHA1};

# set the modification and access times of files
codesigner.commands += touch -c $${OUT_PWD}/$${BUNDLEAPP}.app;

# Sign the application, using the provided entitlements
CODESIGN_ALLOCATE_PATH=$$system(xcrun -find codesign_allocate)
codesigner.commands += export CODESIGN_ALLOCATE=$${CODESIGN_ALLOCATE_PATH};
codesigner.commands += codesign --deep --force --sign $${CERTSHA1} -r=\'designated => anchor apple generic and identifier \"$${BUNDLEID}\" and ((cert leaf[field.1.2.840.113635.100.6.1.9] exists) or (certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU]=$${CERT_OU}))\' --timestamp=none $$OUT_PWD/$${BUNDLEAPP}.app;

first.depends = $(first) organizer codesigner
export(first.depends)
export(organizer.commands)
export(codesigner.commands)
QMAKE_EXTRA_TARGETS += first organizer codesigner

QMAKE_POST_LINK += codesign --deep --force --sign $${CERTSHA1} -r=\'designated => anchor apple generic and identifier \"$${BUNDLEID}\" and ((cert leaf[field.1.2.840.113635.100.6.1.9] exists) or (certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU]=$${CERT_OU}))\' --timestamp=none $$OUT_PWD/$${BUNDLEAPP}.app;
