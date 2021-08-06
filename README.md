About QtPrivilegedExample
==============

This sample illustrates how to install a helper tool that needs to run with privileges as a launchd task, how to have launchd launch the task on demand, and how to communicate with it using IPC to execute privileges tasks. This example is for Qt an C++ developers, because the other existing examples are based on xcode, and there is no documentatacion (and is not so easy) on how to translate those examples to Qt/C++ code.

It is based on next projects.


- SMJobBless: http://developer.apple.com/library/mac/#samplecode/SMJobBless/Introduction/Intro.html
- PrivilegedHelperExample: https://bitbucket.org/sinbad/privilegedhelperexample
- ECHelper: https://github.com/elegantchaos/ECHelper/blob/master/ReadMe.markdown
- Tunnelblickd: https://github.com/Tunnelblick/Tunnelblick/


Rough explanation
-----------------

There are 3 products defined here:

1. The HostApp application, which installs and communicate with the PrivilegedHelper application. 
2. A PrivilegedHelper application which can be used to perform privileged actions.
3. A simple ExampleTool application, which is executed by the PrivilegedHelper application with administratives privileges.

It's CRITICAL that all 3 are codesigned. As currently set up, the requirements are that the certificate is authorised by Apple, but you could change this.

The HostApp asks LaunchServices to install the privileged helper, which will later be communicated with over a socket to executes the ExamplepleTool with administravies privileges. Code signing is used to prevent tampering with the process.

Staying Consistent
------------------

The biggest problem with the installation part of the task is that the helper tool and the host application that's going to install it have to be set up very carefully to have the right code-signing details and bundle ids.

If you wanted to change these in the SMJobBless example you had to do it in lots of different places - and it was easy to miss one.

This sample gets round that problem by setting three user-defined values at the project level, in the common/certificate.pri file:

    # Name of the application signing certificate (Change this for your apple developer signing certificate)
    APPCERT = "\"3rd Party Mac Developer Application: App Developer (XXXXXXXXXX)\""
    
    # Cert OU (Change this for the code at the end of your apple developer certificate)
    CERT_OU = XXXXXXXXXX
    
    # Sha1 of the siging certificate (Change this for the Sha1 of your apple developer certificate)
    CERTSHA1 = 1234567890ABCDEFFEDCBA098765432112345678
    

The APPCERT, CERT_OUT and CERTSHA1 are embedded in various places, and it's important that they all match exactly what's in the certificate. For this reason you need to specify an exact profile name here (like "3rd Party Mac Developer Application: App Developer (XXXXXXXXXX)"), rather than a wildcard (like "3rd Party Mac Developer Application: *"). You can extract this information using the "Keychain Access" application (see image below).

![Certificate Information](https://raw.github.com/mbsanchez/QtPrivilegedHelperExample/master/images/cert_info.png)

Building The Plists
-------------------

The tricky part of all of this is that the HostApp application needs one plist (Info.plist), and the PrivilegedHelper application two (PrivilegedHelper-Info.plist and PrivilegedHelper-Launchd.plist), and both of them make reference to the three values defined above. Also, the PrivilegedHelper needs to be linked with both plist files. On Qt I did that using the QMAKE_LFLAGS (the code below is on PrivilegedHelper.pro file)

    QMAKE_LFLAGS += -F /System/Library/Frameworks/Security.framework/ -sectcreate __TEXT __info_plist $$PWD/PrivilegedHelper-Info.plist -sectcreate __TEXT __launchd_plist $$PWD/PrivilegedHelper-Launchd.plist
    

By using this command, the two plists are embedded in the __TEXT section of the PrivilegedHelper application, which is a simple binary and therefore doesn't live in a bundle. 

Even with the other plist (which is used for the HostApp application) has a complication to it, because one of the special keys in it is a dictionary where a key needs to be replaced by the value of the PrivilegedHelper identifier. The way I've got around this is to add build scripts to both targets which take the original plists and perform the substitutions. This was done using PlistBuddy apple command (this code is on HostApp.pro file ).

    list.commands += /usr/libexec/PlistBuddy -c \"Set :SMPrivilegedExecutables:$${HELPER_IDENTIFIER} 'anchor apple generic and identifier $${HELPER_IDENTIFIER} and (certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = $${CERT_OU})'\" $${INFO_PLIST_PATH
    

IPC
---

I've also expanded the example to illustrate how to communicate with the PrivilegedHelper application, and instruct this to execute the ExampleTool application with admin rights.

The example uses a private Unix Socket to communicate, the PrivilegedHelper application is the server, and the HostApp application is the client. The HostApp sends a command to the PrivilegedHelper to instructs it to run the ExampleTool application with adming rights. The PrivilegedExample checks wheather or not the HostApp and the ExampleTool are signed with the same certificate, by using the codesing utility, if all is good, the PrivilegedExample executes the ExampleTool, with admin rights and returns the state to the HostApp.

Scripts
-------

I have included a uninstall script, to uninstall the PrivilegedHelped.

In particular, you should run the uninstall script when you change something in the PrivilegedHelper application. It will remove all trace of the previous helper, ensuring that you test in a clean environment. 
This script runs some sudo rm commands, so be careful what you do with it - if you manage to *really* mess things up and give it the wrong path info it could eat your hard drive!

Images
------

![The QtPrivilegedHelperExample structure](https://raw.github.com/mbsanchez/QtPrivilegedHelperExample/master/images/qtcreator.png)

![The HostApp Main Window](https://raw.github.com/mbsanchez/QtPrivilegedHelperExample/master/images/HostApp.png)

![Installing the PrivilegedHelper](https://raw.github.com/mbsanchez/QtPrivilegedHelperExample/master/images/InstallingPrivilegedHelper.png)

![Installing the PrivilegedHelper results](https://raw.github.com/mbsanchez/QtPrivilegedHelperExample/master/images/InstallingPrivilegedHelperResult.png)

![Executing the ExampleTool](https://raw.github.com/mbsanchez/QtPrivilegedHelperExample/master/images/ExecutingExampleTool.png)

![The PrivilegedExample Log file](https://raw.github.com/mbsanchez/QtPrivilegedHelperExample/master/images/privilegedhelperlog.png)

![The ExampleTool Log file](https://raw.github.com/mbsanchez/QtPrivilegedHelperExample/master/images/exampletoolsyslog.png)


Qt Project Build and Run Settings
---------------------------------

![Build Settings](https://raw.github.com/mbsanchez/QtPrivilegedHelperExample/master/images/BuildSettings.png)

![Run Settings](https://raw.github.com/mbsanchez/QtPrivilegedHelperExample/master/images/RunSettings.png)

Show PrivilegedHelper Log
--------------------

    log show --predicate 'subsystem == "com.mbs.PrivilegedHelper"' --info --debug
    syslog | grep Hello

Issues
------

When you build the app a second time, you can see next error.
![build issue](https://raw.github.com/mbsanchez/QtPrivilegedHelperExample/master/images/issues.png)

Don't be afraid about that, this error is thrown by codesign because it's replacing the previous signature.
