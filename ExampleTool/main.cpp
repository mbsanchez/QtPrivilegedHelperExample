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
#include <syslog.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[])
{
    Q_UNUSED(argc)
    Q_UNUSED(argv)

    syslog(LOG_NOTICE, "Hello world! uid = %d, euid = %d, pid = %d\n", (int) getuid(), (int) geteuid(), (int) getpid());

    return EXIT_SUCCESS;
}

