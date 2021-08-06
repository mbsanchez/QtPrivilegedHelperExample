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

#include <QCoreApplication>
#include <arpa/inet.h>
#include <os/log.h>
#include <errno.h>
#include <fcntl.h>
#include <launch.h>
#include <libgen.h>
#include <netdb.h>
#include <netinet/in.h>
#include <pwd.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <sys/event.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/ucred.h>
#include <sys/un.h>
#include <unistd.h>
#include <signal.h>

#include <CoreFoundation/CFURL.h>
#include <CoreFoundation/CFBundle.h>

#include "../common/SSPrivilegedHelperCommon.h"

#include <xpc/xpc.h>

#define UNUSED(expr) do { (void)(expr); } while (0);

#define LOG_PATH_C              "/var/log/com.mbs.priviledhelper.log"
#define PREVIOUS_LOG_PATH_C     "/var/log/com.mbs.priviledhelper.previous.log"

static bool sigtermReceived = false;

static void signal_handler(int signalNumber) {

    if (  signalNumber == SIGTERM  ) {
        sigtermReceived = true;
    }
}

// Checks for a valid HostApp Path
bool isValidBasePath(const char *basePath){
    if(!basePath)
        return false;

    size_t iBaseUrlPath = strlen(basePath);
    size_t iHostAppLen = strlen(kHostAppRightName);

    return strcmp(basePath+iBaseUrlPath-iHostAppLen, kHostAppRightName)==0;
}

// Checks for a valid signature of the app located on appPath
bool checkSignature(const char* appPath){
    bool result = true;

    char* valCodeSignCmd = 0;
    // asprintf allocates & never overflows
    if (asprintf(&valCodeSignCmd, "codesign -v -R=\"certificate leaf[subject.CN] = \\\"%s\\\" and anchor apple generic\" \"%s\"", kSigningCertCommonName, appPath) != -1)
    {
        if (system(valCodeSignCmd) != 0)
        {
            result = false;
        }

        // Clean up
        free(valCodeSignCmd);
    }else
        result = false;

    return result;
}

// Validates the signature of the HostApp and ExampleTool
bool isValidSignature(const char *hostAppPath){
    char toolPath[4096];

    snprintf(toolPath, 4096, "%s/Contents/Resources/%s", hostAppPath, kToolRightName);
    toolPath[4096-1] = 0;

    return checkSignature(hostAppPath) && checkSignature(toolPath);
}

// This function executes the ExampleTool application using execvp
int runTool(const char *hostBasePath, char **stdoutString, char **stderrString){

    // Checks for valid signature on HostApp and ExampleTool
    if(!isValidSignature(hostBasePath))
        return -1;

    std::vector<char*> params;
    char toolPath[4096];
    snprintf(toolPath, 4096, "%s/Contents/Resources/%s", hostBasePath, kToolRightName);
    toolPath[4096-1] = 0;

    *stdoutString = strdup("");
    params.push_back(toolPath);
    params.push_back(NULL);

    pid_t pid = fork();

    if (pid == -1)
    {
        asprintf(stderrString, "Could not start %s: errno %i", kToolRightName, errno);
        return -4;
    }
    else if (pid == 0)
    {
        // here goes the second instance - the child process
        // create new process group (see Terminate() where it is used)
        setsid();
        execvp(toolPath, (char* const*)&params.front());
        _exit(254);
    }
    *stderrString = strdup("");

    return 0;
}

static os_log_t logger = os_log_create("com.mbs.PrivilegedHelper", "Daemon");

static void __XPC_Peer_Event_Handler(xpc_connection_t connection, xpc_object_t event) {
    UNUSED(connection)
    os_log_info(logger, "Received event in helper.");

    xpc_type_t type = xpc_get_type(event);

    if (type == XPC_TYPE_ERROR) {
        if (event == XPC_ERROR_CONNECTION_INVALID) {
            // The client process on the other end of the connection has either
            // crashed or cancelled the connection. After receiving this error,
            // the connection is in an invalid state, and you do not need to
            // call xpc_connection_cancel(). Just tear down any associated state
            // here.

        } else if (event == XPC_ERROR_TERMINATION_IMMINENT) {
            // Handle per-connection termination cleanup.
        }
    } else {
        xpc_connection_t remote = xpc_dictionary_get_remote_connection(event);
        static const char *command_header = COMMAND_HEADER_C;
        const char *buffer;
        int status;

        buffer = xpc_dictionary_get_string(event, "cmd");

        os_log_info(logger, "Command received: %s", buffer);
        // Ignore request unless it starts with a valid header and is terminated by a \n
        if (  0 != strncmp(buffer, command_header, strlen(command_header))  ) {
            os_log_error(logger, "Received %lu bytes from client but did it did not start with a valid header; received '%s'", (unsigned long)strlen(buffer), buffer);
            return; // this isn't fatal
        }

        //***************************************************************************************
        //***************************************************************************************
        // Process the request by calling the example tool and sending its status and output to the client
        //struct passwd *ss = getpwuid(client_euid);
        const char *hostBasePath =  buffer + strlen(COMMAND_HEADER_C) + strlen(kExecuteToolCommand);
        char *stdoutString = NULL;
        char *stderrString = NULL;
        char socketStream[1024];

        os_log_info(logger, "HostApp Path: %s", hostBasePath);

        // Run the ExampleTool
        status = runTool(hostBasePath, &stdoutString, &stderrString);

        if (status != 0) {
            // Log the status from executing the command
            os_log_info(logger, "Status = %ld from ExampleTool command '%s'", (long) status, hostBasePath);
        }

        xpc_object_t reply = xpc_dictionary_create_reply(event);
        snprintf(socketStream, 1024, "%ld %lu %lu\n%s%s%c", (long)status, (unsigned long)strlen(stdoutString),
                            (unsigned long)strlen(stderrString), stdoutString, stderrString, '\0');

        xpc_dictionary_set_string(reply, "reply", socketStream);
        xpc_connection_send_message(remote, reply);
        xpc_release(reply);
        free(stdoutString);
        free(stderrString);
    }
}

static void __XPC_Connection_Handler(xpc_connection_t connection)  {
    os_log_info(logger, "Configuring message event handler for helper.");

    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        __XPC_Peer_Event_Handler(connection, event);
    });

    xpc_connection_resume(connection);
}

int main(int argc, const char *argv[]) {
    UNUSED(argc)
    UNUSED(argv)

    // Make sure we are root:wheel
    if ((getuid() != 0) || (getgid() != 0) || (geteuid() != 0) || (getegid() != 0)) {
        os_log_error(logger, "Not root:wheel; our uid = %lu; our euid = %lu; our gid = %lu; our egid = %lu",
                     (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
        return EXIT_SUCCESS;
    }

    xpc_connection_t service = xpc_connection_create_mach_service("com.mbs.PrivilegedHelper",
                                                                  dispatch_get_main_queue(),
                                                                  XPC_CONNECTION_MACH_SERVICE_LISTENER);

    if (!service) {
        os_log_error(logger, "Failed to create service.");
        exit(EXIT_FAILURE);
    }

    // Set up SIGTERM handler
    struct sigaction action;
    action.sa_handler = signal_handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    if (  sigaction(SIGTERM, &action, NULL)  ) {
        os_log_error(logger, "Failed to set signal handler for SIGTERM");
        goto done;
    }

    os_log_info(logger, "Configuring connection event handler for helper");
    xpc_connection_set_event_handler(service, ^(xpc_object_t connection) {
        __XPC_Connection_Handler(static_cast<xpc_connection_t>(connection));
    });

    xpc_connection_resume(service);

    dispatch_main();

done:
    xpc_release(service);
    return EXIT_SUCCESS;
}
