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

# Name of the application signing certificate
APPCERT = "\"Developer ID Application: App Developer (XXXXXXXXXX)\""

# Cert OU
CERT_OU = "\"XXXXXXXXXX"\"

# Sha1 of the siging certificate
CERTSHA1 = 1234567890ABCDEFFEDCBA098765432112345678

DEFINES += kSigningCertCommonName=\\\"$${APPCERT}\\\"
