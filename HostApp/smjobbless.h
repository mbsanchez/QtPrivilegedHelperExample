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

#ifndef SMJOBBLESS_H
#define SMJOBBLESS_H

#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFError.h>

enum HelperToolResult { HT_INSTALL_FAILED, HT_INSTALL_NO_NEEDED, HT_INSTALL_DONE};

bool blessHelperWithLabel(CFStringRef label, CFErrorRef* error);
HelperToolResult installPrivilegedHelperTool();
int runExampleTool(char *szStdOutBuffer, char *szStdErrBuffer, int iBuffersSize);

#endif // SMJOBBLESS

