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
#include <asl.h>
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

// This function was adapted from https://github.com/Tunnelblick/Tunnelblick/
// This function waits for a command from the HostApp, then executes the ExampletTool
// and send the response to the HostApp
int main(int argc, char *argv[])
{
    Q_UNUSED(argc);
    Q_UNUSED(argv);

    struct sigaction action; 
    struct sockaddr_storage ss;
    socklen_t       slen          = sizeof(ss);
    aslclient       asl           = NULL;
    aslmsg          log_msg       = NULL;
    int             retval        = EXIT_FAILURE;
    struct timespec timeout       = {  30, 0  };	// TimeOut value (OS X supplies a 30 second value if there is no TimeOut entry in the launchd .plist)
    struct kevent   kev_init;
    struct kevent   kev_listener;
    launch_data_t   sockets_dict, checkin_response, checkin_request, listening_fd_array;
    size_t          i;
    int             kq, status;
    static const char *command_header = COMMAND_HEADER_C;
    
    // Create a new ASL log
    asl = asl_open("com.mbs.PrivilegedHelper", "Daemon", ASL_OPT_STDERR);
    log_msg = asl_new(ASL_TYPE_MSG);
    asl_set(log_msg, ASL_KEY_SENDER, "com.mbs.PrivilegedHelper");

    // Create a new kernel event queue that we'll use for our notification.
    // Note the use of the '%m' formatting character.
    // ASL will replace %m with the error string associated with the current value of errno.
    if (  -1 == (kq = kqueue())  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "kqueue(): %m");
        goto done;
    }

    // Make sure we are root:wheel
    if (   (getuid()  != 0)
        || (getgid()  != 0)
        || (geteuid() != 0)
        || (getegid() != 0)
        ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Not root:wheel; our uid = %lu; our euid = %lu; our gid = %lu; our egid = %lu",
                (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
        goto done;
    }

    if (  NULL == (checkin_request = launch_data_new_string(LAUNCH_KEY_CHECKIN))  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "launch_data_new_string(\"" LAUNCH_KEY_CHECKIN "\") Unable to create string.");
        goto done;
    }

    if (  (checkin_response = launch_msg(checkin_request)) == NULL  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "launch_msg(\"" LAUNCH_KEY_CHECKIN "\") IPC failure: %m");
        goto done;
    }

    if (  LAUNCH_DATA_ERRNO == launch_data_get_type(checkin_response)  ) {
        errno = launch_data_get_errno(checkin_response);
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Check-in failed: %m");
        goto done;
    }
    {
        // If the .plist and OS X did not specify a TimeOut, default to 30 seconds
        launch_data_t timeoutValue = launch_data_dict_lookup(checkin_response, LAUNCH_JOBKEY_TIMEOUT);
        if (  timeoutValue != NULL) {
            timeout.tv_sec = launch_data_get_integer(timeoutValue);
        }

        launch_data_t the_label = launch_data_dict_lookup(checkin_response, LAUNCH_JOBKEY_LABEL);
        if (  NULL == the_label  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "No label found");
            goto done;
        }

        asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Started %s", launch_data_get_string(the_label));
    }

    // Retrieve the dictionary of Socket entries in the config file
    sockets_dict = launch_data_dict_lookup(checkin_response, LAUNCH_JOBKEY_SOCKETS);
    if (  NULL == sockets_dict  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "No sockets found on which to answer requests!");
        goto done;
    }

    if (  launch_data_dict_get_count(sockets_dict) > 1) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Too many sockets! This daemon supports only one socket.");
        goto done;
    }

    // Get the dictionary value from the key "MyListenerSocket", as defined in the .plist file.
    listening_fd_array = launch_data_dict_lookup(sockets_dict, "com.mbs.PrivilegedHelper");
    if (  NULL == listening_fd_array  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "No socket named 'com.mbs.PrivilegedHelper' found in launchd .plist to answer requests on!");
        goto done;
    }

    // Initialize a new kernel event.  This will trigger when a connection occurs on our listener socket.
    for (  i = 0; i < launch_data_array_get_count(listening_fd_array); i++  ) {
        launch_data_t this_listening_fd = launch_data_array_get_index(listening_fd_array, i);
        EV_SET(&kev_init, launch_data_get_fd(this_listening_fd), EVFILT_READ, EV_ADD, 0, 0, NULL);
        if (  -1 == kevent(kq, &kev_init, 1, NULL, 0, NULL)  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Error from kevent(): %m");
            goto done;
        }
    }

    launch_data_free(checkin_response);

    // Set up SIGTERM handler
    action.sa_handler = signal_handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    if (  sigaction(SIGTERM, &action, NULL)  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Failed to set signal handler for SIGTERM");
        goto done;
    }

    // Loop processing kernel events.
    for (;;) {
        FILE *socketStream;
        int  filedesc;
        int  nbytes;

#define SOCKET_BUF_SIZE 1024

        char buffer[SOCKET_BUF_SIZE];

        // Get the next event from the kernel event queue.
        if (  -1 == (filedesc = kevent(kq, NULL, 0, &kev_listener, 1, &timeout))  ) {
            if (   sigtermReceived
                && (errno == EINTR)  ) {
                asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "SIGTERM received; exiting");
                retval = EXIT_SUCCESS;
                goto done;
            }
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Error from kevent(): %m");
            goto done;
        } else if (  0 == filedesc  ) {
            asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Timed out; exiting");

            // If the current log file is too large, start it over
            asl_close(asl);
            struct stat st;
            int stat_result = stat(LOG_PATH_C, &st);
            if (  0 == stat_result  ) {
                if (  st.st_size > 100000  ) {
                    // Log file is large; replace any existing old log with it and start a new one
                    rename(LOG_PATH_C, PREVIOUS_LOG_PATH_C);
                }
            }
            return EXIT_SUCCESS;
        }

        // Accept an incoming connection.
        if (  -1 == (filedesc = accept(kev_listener.ident, (struct sockaddr *)&ss, &slen))  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Error from accept(): %m");
            continue; /* this isn't fatal */
        }

        // Get the client's credentials
        uid_t client_euid;
        gid_t client_egid;
        if (  0 != getpeereid(filedesc, &client_euid, &client_egid)  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not obtain peer credentials from unix domain socket: %m; our uid = %lu; our euid = %lu; our gid = %lu; our egid = %lu",
                    (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
            continue; // this isn't fatal
        }

        // Get the request from the client
        nbytes = read(filedesc, buffer, SOCKET_BUF_SIZE - 1);
        if (  0 == nbytes  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "0 bytes from read()");
            continue; // this isn't fatal
        } else if (  nbytes < 0  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Error from read(): &m");
            continue; // this isn't fatal
        } else if (  SOCKET_BUF_SIZE - 1 == nbytes   ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Too many bytes read; maximum is %lu", (unsigned long)(SOCKET_BUF_SIZE - 2));
            continue; // this isn't fatal
        }

        buffer[nbytes] = '\0';	// Terminate so the request is a string

        asl_log(asl, log_msg, ASL_LEVEL_INFO, "Command received: %s", buffer);
        // Ignore request unless it starts with a valid header and is terminated by a \n
        if (  0 != strncmp(buffer, command_header, strlen(command_header))  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Received %lu bytes from client but did it did not start with a valid header; received '%s'", (unsigned long)nbytes, buffer);
            continue; // this isn't fatal
        }
        char * nlPtr = strchr(buffer, '\n');
        if (   (nlPtr == NULL)
            || (nlPtr != (buffer + nbytes - 1))
            ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Received %lu bytes from client but did not receive a LF at the end; received '%s'", (unsigned long)nbytes, buffer);
            continue; // this isn't fatal
        }

        // Remove the LF at the end of the request
        buffer[nbytes - 1] = '\0';

        //***************************************************************************************
        //***************************************************************************************
        // Process the request by calling the example tool and sending its status and output to the client
        //struct passwd *ss = getpwuid(client_euid);
        char *hostBasePath =  buffer + strlen(COMMAND_HEADER_C) + strlen(kExecuteToolCommand);
        char *stdoutString = NULL;
        char *stderrString = NULL;

        asl_log(asl, log_msg, ASL_LEVEL_INFO, "HostApp Path: %s", hostBasePath);

        // Run the ExampleTool
        status = runTool(hostBasePath, &stdoutString, &stderrString);

        if (status != 0) {
            // Log the status from executing the command
            asl_log(asl, log_msg, ASL_LEVEL_NOTICE, "Status = %ld from ExampleTool command '%s'", (long) status, hostBasePath);
        }

        // Send the status, stdout, and stderr to the client as a UTF-8-encoded string which is terminated by a \0.
        //
        // The header of the string consists of the signed status, the unsigned length of the stdout string,
        // the unsigned length of the stderr string, and a newline. (The numbers are each separated by one space.)
        //
        // The stdout string follows the header, the stderr string follows the stdout string, and a \0 follows that.
        socketStream = fdopen(filedesc, "r+");
        if (socketStream) {
            fprintf(socketStream, "%ld %lu %lu\n%s%s%c", (long)status, (unsigned long)strlen(stdoutString),
                    (unsigned long)strlen(stderrString), stdoutString, stderrString, '\0');
            fclose(socketStream);
            asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Responded to client; header = %ld %lu %lu", (long)status, (unsigned long)strlen(stdoutString),
                    (unsigned long)strlen(stderrString));
        } else {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not open stream to output to client");
            close(filedesc);  // This isn't fatal
        }
        free(stdoutString);
        free(stderrString);
    }
done:
    asl_close(asl);
    return retval;
}

