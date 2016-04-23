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


// this function was adapted from the SMJobBless example
bool blessHelperWithLabel(CFStringRef label, CFErrorRef* error)
{
    bool result = false;

    AuthorizationItem authItem		= { kSMRightBlessPrivilegedHelper, 0, NULL, 0 };
    AuthorizationRights authRights	= { 1, &authItem };
    AuthorizationFlags flags		=	kAuthorizationFlagDefaults				|
                                        kAuthorizationFlagInteractionAllowed	|
                                        kAuthorizationFlagPreAuthorize			|
                                        kAuthorizationFlagExtendRights;
    AuthorizationRef authRef = NULL;

    /* Obtain the right to install privileged helper tools (kPRIVILEGED_HELPER_LABEL). */
    OSStatus status = AuthorizationCreate(&authRights, kAuthorizationEmptyEnvironment, flags, &authRef);
    if (status != errAuthorizationSuccess)
    {
        qCritical() << QObject::tr("Failed to create AuthorizationRef, return code %1").arg( (long)status);
    } else
    {
        /* This does all the work of verifying the helper tool against the application
         * and vice-versa. Once verification has passed, the embedded launchd.plist
         * is extracted and placed in /Library/LaunchDaemons and then loaded. The
         * executable is placed in /Library/PrivilegedHelperTools.
         */
        result = SMJobBless(kSMDomainSystemLaunchd, label, authRef, error);
    }

    AuthorizationFree(authRef, kAuthorizationFlagDefaults);


    return result;
}

// this function is adapted from https://bitbucket.org/sinbad/privilegedhelperexample
bool installPrivilegedHelperTool()
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

    CFErrorRef  error = NULL;
    CFDictionaryRef	installedHelperJobData 	= SMJobCopyDictionary(kSMDomainSystemLaunchd, CFSTR(kPRIVILEGED_HELPER_LABEL));
    bool needToInstall = true;

    if (installedHelperJobData)
    {
        // This code vVerify wheather or not the PrivilegedHelper is installed as a privileged helper tool
        CFArrayRef arguments = (CFArrayRef)CFDictionaryGetValue (installedHelperJobData, CFSTR("ProgramArguments"));
        CFStringRef installedPath = (CFStringRef)CFArrayGetValueAtIndex(arguments, 0);
        CFURLRef installedPathURL = CFURLCreateWithString(kCFAllocatorDefault, installedPath, NULL);
        CFDictionaryRef installedInfoPlist = CFBundleCopyInfoDictionaryForURL(installedPathURL);
        CFStringRef installedBundleVersion = (CFStringRef)CFDictionaryGetValue (installedInfoPlist, CFSTR("CFBundleVersion"));
        int installedVersion = CFStringGetIntValue(installedBundleVersion);

        qInfo() << "installedVersion: " << (long)installedVersion;

        CFBundleRef appBundle = CFBundleGetMainBundle();
        CFURLRef appBundleURL = CFBundleCopyBundleURL(appBundle);

        qInfo() << "appBundleURL: " << appBundleURL;

        CFStringRef helperToolPath = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("Contents/Library/LaunchServices/%@"), CFSTR(kPRIVILEGED_HELPER_LABEL));
        CFURLRef currentHelperToolURL = CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, appBundleURL, helperToolPath, false);

        qInfo() << "currentHelperToolURL: " << currentHelperToolURL;

        CFDictionaryRef currentInfoPlist = CFBundleCopyInfoDictionaryForURL(currentHelperToolURL);
        CFStringRef currentBundleVersion = (CFStringRef)CFDictionaryGetValue (currentInfoPlist, CFSTR("CFBundleVersion"));
        int currentVersion = CFStringGetIntValue(currentBundleVersion);

        qInfo() << "currentVersion: " << currentVersion;

        if ( currentVersion == installedVersion )
        {
            SecRequirementRef requirement;
            OSStatus stErr;
            CFStringRef reqStr = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("identifier %@ and certificate leaf[subject.CN] = \"%@\""),
                                                          CFSTR(kPRIVILEGED_HELPER_LABEL), CFSTR(kSigningCertCommonName));

            stErr = SecRequirementCreateWithString(reqStr, kSecCSDefaultFlags, &requirement );

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
        CFRelease(installedHelperJobData);
    }


    // When the PrivilegedHelper is not installed, we proceed to install it, using the blessHelperWithLabel function
    if (needToInstall)
    {
        if (!blessHelperWithLabel(CFSTR(kPRIVILEGED_HELPER_LABEL), &error))
        {
            CFStringRef cfErrDescription = CFErrorCopyDescription(error);
            const char *szErrDesc = CFStringGetCStringPtr(cfErrDescription, CFStringGetSystemEncoding());
            qCritical() << "Failed to install privileged helper: " << szErrDesc;
            return false;
        }
        else
            qInfo() << "Privileged helper installed.";
    }
    else
        qInfo() << "Privileged helper already available, not installing.";

    return true;
}

// This function was adapted from https://github.com/Tunnelblick/Tunnelblick/
// This functions send the command to the PrivilegedHelper using a unix socket,
// then waits for a response
int runExampleTool(char *szStdOutBuffer, char *szStdErrBuffer, int iBuffersSize) {
    int sockfd;
    int n;

    char requestToServer[4096];
    const char *socketPath = HELPER_SOCKET_PATH;
    char *pOutMsg, *pErrMsg, *buf_ptr, *pNl;
    char *p_szStatus, *p_szOutLen, *p_szErrLen;
    int status, stdOutLen, stdErrLen;
    size_t bytes_to_write, offset=0, mbytes=4096;
    time_t tm1, tm2;
    useconds_t sleepTimeMicroseconds;
    bool foundZeroByte;

#define SOCKET_BUF_SIZE 1024
    char buffer[SOCKET_BUF_SIZE];
    struct sockaddr_un socket_data;

    // Get the base app url
    CFURLRef appBasePathUrl = CFBundleCopyBundleURL(CFBundleGetMainBundle());
    CFStringRef appBasePath = CFURLCopyFileSystemPath(appBasePathUrl, kCFURLPOSIXPathStyle);
    const char *cStrAppBasePath = CFStringGetCStringPtr(appBasePath, CFStringGetSystemEncoding());

    // Create the resquest command
    snprintf(requestToServer, 4096, "%s%s%s\n", COMMAND_HEADER_C, kExecuteToolCommand, cStrAppBasePath);
    requestToServer[4096-1] = 0;

    // Release the base url and path
    CFRelease(appBasePathUrl);
    CFRelease(appBasePath);

    // Create a Unix domain socket as a stream
    sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (  sockfd < 0  ) {
        qCritical() << "runExampleTool: Error creating Unix domain socket; errno = "
                    << errno << "; error was '" << strerror(errno) << "'";
        goto error2;
    }

    // Connect to the PrivilegedHelper server's socket
    bzero((char *) &socket_data, sizeof(socket_data));
    socket_data.sun_len    = sizeof(socket_data);
    socket_data.sun_family = AF_UNIX;
    if (  sizeof(socket_data.sun_path) <= strlen(socketPath)  ) {
        qCritical() << "runExampleTool: socketPath is "
                    << strlen(socketPath) << " bytes long but there is only room for "
                    << sizeof(socket_data.sun_path) << " bytes in socket_data.sun_path";
        goto error1;
    }
    memmove((char *)&socket_data.sun_path, (char *)socketPath, strlen(socketPath));
    if (  connect(sockfd, (struct sockaddr *)&socket_data, sizeof(socket_data)  ) < 0) {
       qCritical() << "PrivilegedHelper: Error connecting to PrivilegedHelper server socket; errno = "
                   << errno << "; error was '" << strerror(errno) << "'";
        goto error1;
    }

    // Send our request to the socket
    buf_ptr = (char*)requestToServer;
    bytes_to_write = strlen(requestToServer);
    while (  bytes_to_write != 0  ) {
        n = write(sockfd, buf_ptr, bytes_to_write);
        if (  n < 0  ) {
           qCritical() << "runExampleTool: Error writing to PrivilegedHelper server socket; errno = "
                       << errno << "; error was '" << strerror(errno) << "'";
            goto error1;
        }

        buf_ptr += n;
        bytes_to_write -= n;
    }

    // Receive from the socket until we receive a \0
    // Must receive all data within 30 seconds or we assume PrivilegedHelper is not responding properly and abort

    // Set the socket to use non-blocking I/O (but we've already done the output, so we're really just doing non-blocking input)
    if (  -1 == fcntl(sockfd, F_SETFL,  O_NONBLOCK)  ) {
        qCritical() << "runExampleTool: Error from fcntl(sockfd, F_SETFL,  O_NONBLOCK) with PrivilegedHelper server socket; errno = "
                    << errno << "; error was '" << strerror(errno) << "'";
        goto error1;
    }

    char output[4096];

    foundZeroByte = false;
    offset=0;
    mbytes=4096;
    tm1 = time(NULL);
    tm2 = tm1;
    sleepTimeMicroseconds = 10000;	// First sleep is 0.10 seconds; each sleep thereafter will be doubled, up to 5.0 seconds

    memset(output, 0, 4096);
    while (  tm2-tm1 < 30  ) {
        bzero((char *)buffer, SOCKET_BUF_SIZE);
        n = read(sockfd, (char *)buffer, SOCKET_BUF_SIZE - 1);
        time(&tm2);
        if (   (n == -1)
            && (errno == EAGAIN)  ) {
            sleepTimeMicroseconds *= 2;
            if (  sleepTimeMicroseconds > 5000000  ) {
                sleepTimeMicroseconds = 5000000;
                qInfo() << "runExampleTool: no data available from PrivilegedHelper socket; sleeping "
                        << ((float)sleepTimeMicroseconds)/1000000.0 << "seconds...";
            }
            usleep(sleepTimeMicroseconds);
            continue;
        } else if (  n < 0  ) {
            qCritical() << "runExampleTool: Error reading from PrivilegedHelper socket; errno = "
                        << errno << "; error was '" << strerror(errno) << "'";
            goto error1;
        }
        buffer[n] = '\0';
        if(n+offset<4096){
            snprintf(output+offset, mbytes-1, "%s", buffer);
            offset = strlen(output); mbytes = 4096 - offset;
        }
        if (  strchr(buffer, '\0') != (buffer + n)  ) {
            if (  strchr(buffer, '\0') != (buffer + n - 1)  ) {
                qCritical() << "runExampleTool: Data from PrivilegedHelper after the zero byte that should terminate the data";
                goto error1;
            }
            foundZeroByte = true;
            break;
        }
    }

    shutdown(sockfd, SHUT_RDWR);
    close(sockfd);

    if (  ! foundZeroByte  ) {
        qCritical() <<  "runExampleTool: PrivilegedHelper is not responding; received only " << strlen(output) <<" bytes";
        goto error2;
    }

    pNl = strchr(output, '\n');
    if (  pNl == NULL  ) {
        qCritical() << "Invalid output from PrivilegedHelper: no newline; full output = '"<< output << "'";
        goto error2;
    }
    *pNl = 0; // remove the end line
    p_szStatus = output;
    p_szOutLen = strchr(output, ' ');
    p_szErrLen = (p_szOutLen == NULL)?NULL:strchr(p_szOutLen+1, ' ');
    if (  p_szErrLen == NULL || strlen(p_szErrLen)<=1) {
        qCritical() << "Invalid output from PrivilegedHelper: header line does not have three components; full output = '" << output << "'";
        goto error2;
    }
    *p_szOutLen = 0; p_szOutLen++;
    *p_szErrLen = 0; p_szErrLen++;
    status = atoi(p_szStatus);
    stdOutLen = atoi(p_szOutLen);
    stdErrLen = atoi(p_szErrLen);
    pOutMsg = pNl+1;
    pErrMsg=pOutMsg+stdOutLen;

    *pErrMsg = 0; pErrMsg++; *(pErrMsg+stdErrLen)=0;

    if (  szStdOutBuffer ) {
        snprintf(szStdOutBuffer, iBuffersSize, "%s", pOutMsg);
    }
    if (  szStdErrBuffer ) {
        snprintf(szStdErrBuffer, iBuffersSize, "%s", pErrMsg);
    }

    return status;

error1:
    shutdown(sockfd, SHUT_RDWR);
    close(sockfd);

error2:
    return -1;
}
