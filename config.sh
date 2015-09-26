# Whether to build for various platforms
BUILD_MAC=1
BUILD_WIN32=1
BUILD_LINUX=1

# Version of Gecko to build with
GECKO_VERSION="41.0"
GECKO_SHORT_VERSION="41.0"

# Paths to Gecko runtimes
MAC_RUNTIME_PATH="`pwd`/xulrunner/Firefox.app"
WIN32_RUNTIME_PATH="`pwd`/xulrunner/xulrunner_win32"
LINUX_i686_RUNTIME_PATH="`pwd`/xulrunner/xulrunner_linux-i686"
LINUX_x86_64_RUNTIME_PATH="`pwd`/xulrunner/xulrunner_linux-x86_64"

# Whether to sign builds
SIGN=1

# OS X Developer ID certificate information
DEVELOPER_ID=c8a15a3bc9eaaabc112e83b2f885609e535d07f0
CODESIGN_REQUIREMENTS="=designated => anchor apple generic  and identifier \"org.zotero.zotero\" and ((cert leaf[field.1.2.840.113635.100.6.1.9] exists) or ( certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists  and certificate leaf[subject.OU] = \"8LAYR367YV\" ))"

# Paths for Windows installer build
MAKENSISU='C:\Program Files (x86)\NSIS\Unicode\makensis.exe'
UPX='C:\Program Files (x86)\upx\upx.exe'
EXE7ZIP='C:\Program Files\7-Zip\7z.exe'

# Paths for Windows installer build only necessary for signed binaries
#SIGNTOOL='C:\Program Files (x86)\Microsoft SDKs\Windows\v7.0A\Bin\signtool.exe'
SIGNTOOL='C:\Program Files (x86)\Windows Kits\8.0\bin\x86\signtool.exe'
SIGNATURE_URL='https://www.zotero.org/'

# If version is not specified on the command line, version is this prefix followed by the revision
DEFAULT_VERSION_PREFIX="4.0.999.SOURCE."
# Numeric version for OS X bundle
VERSION_NUMERIC="4.0.999"

# Directory for building
BUILDDIR="/tmp/zotero-build-`uuidgen | head -c 8`"
# Directory for unpacked binaries
STAGEDIR="$CALLDIR/staging"
# Directory for packed binaries
DISTDIR="$CALLDIR/dist"

# Repository URL
URL="git://github.com/zotero/zotero.git"
