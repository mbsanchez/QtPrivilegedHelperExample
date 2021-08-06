// -----------------------------------------------------------------------------------
// ! @author mbsanchez
// ! @date 22/04/2016
//
// Copyright 2016 mbsanchez. All rights reserved.
//
// This file is part of PrivilegedHelperExample.
//
// PrivilegedHelperExample is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License version 2
// as published by the Free Software Foundation.
//
// PrivilegedHelperExample is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program (see the file LICENSE included with this
// distribution); if not, write to the Free Software Foundation, Inc.,
// 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
// or see http://www.gnu.org/licenses/.
// -----------------------------------------------------------------------------------

#include <QtGui>
#include "../common/SSPrivilegedHelperCommon.h"
#include <ServiceManagement/ServiceManagement.h>
#include <Security/Security.h>
#include <Security/Authorization.h>
#include <Security/Security.h>
#include <Security/SecCertificate.h>
#include <Security/SecCode.h>
#include <Security/SecStaticCode.h>
#include <Security/SecCodeHost.h>
#include <Security/SecRequirement.h>
#include <Foundation/Foundation.h>
#include <syslog.h>
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFError.h>
#include "smjobbless.h"
#include <time.h>
#include <netinet/in.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>

static xpc_connection_t connection;

// this function was adapted from the SMJobBless example
bool blessHelperWithLabel(CFStringRef label, CFErrorRef* error)
{
    bool result = false;

    AuthorizationItem authItem		= { kSMRightBlessPrivilegedHelper, 0, Nil, 0 };
    AuthorizationRights authRights	= { 1, &authItem };
    AuthorizationFlags flags		=	kAuthorizationFlagDefaults				|
                                        kAuthorizationFlagInteractionAllowed	|
                                        kAuthorizationFlagPreAuthorize			|
                                        kAuthorizationFlagExtendRights;
    AuthorizationRef authRef = Nil;

    /* Obtain the right to install privileged helper tools (kPRIVILEGED_HELPER_LABEL). */
    OSStatus status = AuthorizationCreate(&authRights, kAuthorizationEmptyEnvironment, flags, &authRef);
    if (status != errAuthorizationSuccess)
    {
        qCritical() << QObject::tr("Failed to create AuthorizationRef, return code %1").arg( (long)status);
    }
    else
    {
        /* This does all the work of verifying the helper tool against the application
         * and vice-versa. Once verification has passed, the embedded launchd.plist
         * is extracted and placed in /Library/LaunchDaemons and then loaded. The
         * executable is placed in /Library/PrivilegedHelperTools.
         */
        qDebug() << "Blessing the helper tool: " << label;
        result = SMJobBless(kSMDomainSystemLaunchd, label, authRef, error);
        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    }

    return result;
}

// this function is adapted from https://bitbucket.org/sinbad/privilegedhelperexample
HelperToolResult installPrivilegedHelperTool()
{
    // This uses SMJobBless to install a tool in /Library/PrivilegedHelperTools which is
    // run by launchd instead of us, with elevated privileges. This can then be used to do
    // things like install utilities in /usr/local/bin or run another app with admin rights

    // We do this rather than AuthorizationExecuteWithPrivileges because that's deprecated in 10.7
    // The SMJobBless approach is more secure because both ends are validated via code signing
    // which is enforced by launchd - ie only tools signed with the right cert can be installed, and
    // only apps signed with the right cert can install it.

    // Although the launchd approach is primarily associated with daemons, it can be used for one-off
    // tools too. We effectively invoke the privileged helper by talking to it over a private Unix socket
    // (since we can't launch it directly). We still need to be careful about that invocation because
    // the SMJobBless structure doesn't validate that the caller at runtime is the right application.
    // However, the privilegehelper validates the signature of the calling app and the command to execute.

    CFErrorRef  error = Nil;
    bool needToInstall = true;

    qInfo() << "checking for installed tools";
    if ([[NSFileManager defaultManager] fileExistsAtPath: @"/Library/PrivilegedHelperTools/" kPRIVILEGED_HELPER_LABEL])
    {
        CFStringRef installedPath = CFSTR("/Library/PrivilegedHelperTools/" kPRIVILEGED_HELPER_LABEL);
        CFURLRef installedPathURL = CFURLCreateWithString(kCFAllocatorDefault, installedPath, Nil);
        CFDictionaryRef installedInfoPlist = CFBundleCopyInfoDictionaryForURL(installedPathURL);
        CFStringRef installedBundleVersion = (CFStringRef)CFDictionaryGetValue (installedInfoPlist, CFSTR("CFBundleVersion"));
        double installedVersion = CFStringGetDoubleValue(installedBundleVersion);

        qInfo() << "installedVersion: " << installedVersion;

        CFBundleRef appBundle = CFBundleGetMainBundle();
        CFURLRef appBundleURL = CFBundleCopyBundleURL(appBundle);

        qInfo() << "appBundleURL: " << appBundleURL;

        CFStringRef helperToolPath = CFStringCreateWithFormat(kCFAllocatorDefault, Nil, CFSTR("Contents/Library/LaunchServices/%@"), CFSTR(kPRIVILEGED_HELPER_LABEL));
        CFURLRef currentHelperToolURL = CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, appBundleURL, helperToolPath, false);

        qInfo() << "currentHelperToolURL: " << currentHelperToolURL;

        CFDictionaryRef currentInfoPlist = CFBundleCopyInfoDictionaryForURL(currentHelperToolURL);
        CFStringRef currentBundleVersion = (CFStringRef)CFDictionaryGetValue (currentInfoPlist, CFSTR("CFBundleVersion"));
        double currentVersion = CFStringGetDoubleValue(currentBundleVersion);

        qInfo() << "futureVersion: " << currentVersion;

        if ( currentVersion <= installedVersion )
        {
            SecRequirementRef requirement;
            OSStatus stErr;
            CFStringRef reqStr = CFStringCreateWithFormat(kCFAllocatorDefault, Nil, CFSTR("identifier \"%@\" and certificate leaf[subject.CN] = \"%@\""),
                                                          CFSTR(kPRIVILEGED_HELPER_LABEL), CFSTR(kSigningCertCommonName));

            stErr = SecRequirementCreateWithString(reqStr, kSecCSDefaultFlags, &requirement );

            //stErr = SecRequirementCreateWithString((CFStringRef)[NSString stringWithFormat:@"identifier %@ and certificate leaf[subject.CN] = \"%@\"", @kPRIVILEGED_HELPER_LABEL, @kSigningCertCommonName], kSecCSDefaultFlags, &requirement );

            if ( stErr == noErr )
            {
                SecStaticCodeRef staticCodeRef;

                stErr = SecStaticCodeCreateWithPath( installedPathURL, kSecCSDefaultFlags, &staticCodeRef );

                if ( stErr == noErr )
                {
                    stErr = SecStaticCodeCheckValidity( staticCodeRef, kSecCSDefaultFlags, requirement );

                    needToInstall = false;
                }
            }

            CFRelease(reqStr);
        }

        CFRelease(helperToolPath);
        CFRelease(installedPathURL);
        CFRelease(appBundleURL);
        CFRelease(currentHelperToolURL);
        CFRelease(currentInfoPlist);
        CFRelease(installedInfoPlist);
        CFRelease(installedPath);
    }

    HelperToolResult res = HT_INSTALL_NO_NEEDED;

    if (needToInstall)
    {
        qInfo() << "Installing the privileged helper tool" ;
        if (!blessHelperWithLabel(CFSTR(kPRIVILEGED_HELPER_LABEL), &error))
        {
            qDebug() << error;
            if(error){
                CFStringRef cfErrDescription = CFErrorCopyDescription(error);
                const char *szErrDesc = CFStringGetCStringPtr(cfErrDescription, CFStringGetSystemEncoding());
                qCritical() << "Failed to install privileged helper: " << szErrDesc;
            }
            res = HT_INSTALL_FAILED;
        }
        else {
            qInfo() << "Privileged helper installed.";
            res = HT_INSTALL_DONE;
        }
    }
    else
        qInfo() << "Privileged helper already available, not installing.";

    return res;
}

// This function was adapted from https://github.com/Tunnelblick/Tunnelblick/
// This functions send the command to the PrivilegedHelper using a unix socket,
// then waits for a response
int runExampleTool() {
    char requestToServer[4096];

    // Get the base app url
    CFURLRef appBasePathUrl = CFBundleCopyBundleURL(CFBundleGetMainBundle());
    CFStringRef appBasePath = CFURLCopyFileSystemPath(appBasePathUrl, kCFURLPOSIXPathStyle);
    const char *cStrAppBasePath = CFStringGetCStringPtr(appBasePath, CFStringGetSystemEncoding());

    // Create the resquest command
    snprintf(requestToServer, 4096, "%s%s%s", COMMAND_HEADER_C, kExecuteToolCommand, cStrAppBasePath);
    requestToServer[4096-1] = 0;

    // Release the base url and path
    CFRelease(appBasePathUrl);
    CFRelease(appBasePath);

    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(message, "cmd", requestToServer);

    qCritical() << "Sending request:" << message;

    xpc_connection_send_message_with_reply(connection, message, dispatch_get_main_queue(), ^(xpc_object_t event) {
        const char* response = xpc_dictionary_get_string(event, "reply");
        qInfo() << "Received response:" << response;
    });

    return 0;
}

void initConnection()
{
    connection = xpc_connection_create_mach_service(kPRIVILEGED_HELPER_LABEL, NULL, XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);

    if (!connection) {
        qCritical() << "Failed to create XPC connection.";
        return;
    }

    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        xpc_type_t type = xpc_get_type(event);

        if (type == XPC_TYPE_ERROR) {

            if (event == XPC_ERROR_CONNECTION_INTERRUPTED) {
                qCritical() << "XPC connection interupted.";

            } else if (event == XPC_ERROR_CONNECTION_INVALID) {
                qCritical() << "XPC connection invalid, releasing.";
                xpc_release(connection);

            } else {
                qCritical() << "Unexpected XPC connection error.";
            }

        } else {
            qCritical() << "Unexpected XPC connection event.";
        }
    });

    xpc_connection_resume(connection);
}
