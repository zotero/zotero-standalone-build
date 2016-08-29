DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Version of Gecko to build with
GECKO_VERSION="48.0.1"
GECKO_SHORT_VERSION="48.0"

# Paths to Gecko runtimes
MAC_RUNTIME_PATH="$DIR/xulrunner/Firefox.app"
WIN32_RUNTIME_PATH="$DIR/xulrunner/firefox-win32"
LINUX_i686_RUNTIME_PATH="$DIR/xulrunner/firefox-i686"
LINUX_x86_64_RUNTIME_PATH="$DIR/xulrunner/firefox-x86_64"

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

# Directory for unpacked binaries
STAGE_DIR="$DIR/staging"
# Directory for packed binaries
DIST_DIR="$DIR/dist"

S3_BUCKET="zotero-download"
S3_PATH="standalone"

DEPLOY_HOST="deploy.zotero"
DEPLOY_PATH="www/www-production/public/download/standalone/"
DEPLOY_CMD="ssh $DEPLOY_HOST update-site-files"

NUM_INCREMENTALS=3

unset DIR
