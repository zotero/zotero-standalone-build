# Whether to build for various platforms
BUILD_MAC=1
BUILD_WIN32=1
BUILD_LINUX=1

# Version of Gecko to build with
GECKO_VERSION="10.0"

# Paths to Gecko runtimes
MAC_RUNTIME_PATH="`pwd`/xulrunner/XUL.framework"
WIN32_RUNTIME_PATH="`pwd`/xulrunner/xulrunner_win32"
LINUX_i686_RUNTIME_PATH="`pwd`/xulrunner/xulrunner_linux-i686"
LINUX_x86_64_RUNTIME_PATH="`pwd`/xulrunner/xulrunner_linux-x86_64"

# Paths for Windows installer build
MAKENSISU='C:\Program Files (x86)\NSIS\Unicode\makensis.exe'
UPX='C:\Program Files (x86)\upx\upx.exe'
EXE7ZIP='C:\Program Files\7-Zip\7z.exe'

# Paths for Windows installer build only necessary for signed binaries
SIGN=1
SIGNTOOL='C:\Program Files (x86)\Microsoft SDKs\Windows\v7.0A\Bin\signtool.exe'
SIGNATURE_URL='https://www.zotero.org/'

# If version is not specified on the command line, version is this prefix followed by the revision
DEFAULT_VERSION_PREFIX="3.0.4.SOURCE."
# Numeric version for OS X bundle
VERSION_NUMERIC="3.0.4"

# Directory for building
BUILDDIR="/tmp/zotero-build-`uuidgen | head -c 8`"
# Directory for unpacked binaries
STAGEDIR="$CALLDIR/staging"
# Directory for packed binaries
DISTDIR="$CALLDIR/dist"

# Repository URL
URL="git://github.com/zotero/zotero.git"