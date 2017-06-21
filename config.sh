DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Version of Gecko to build with
#
# xulrunner-stub.exe currently requires <=47, though it can probably be rebuilt against a later SDK
GECKO_VERSION_MAC="54.0b13"
GECKO_VERSION_LINUX="54.0b13"
GECKO_VERSION_WIN="52.2.0esr"

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

# Paths for Windows installer build only necessary for signed binaries
#SIGNTOOL='C:\Program Files (x86)\Microsoft SDKs\Windows\v7.0A\Bin\signtool.exe'
SIGNTOOL='C:\Program Files (x86)\Windows Kits\8.0\bin\x86\signtool.exe'
SIGNATURE_URL='https://www.zotero.org/'
SIGNTOOL_CERT_SUBJECT="Corporation for Digital Scholarship"

# Directory for Zotero code repos
repo_dir=$( cd "$DIR"/.. && pwd )
# Directory for Zotero source code
ZOTERO_SOURCE_DIR="$repo_dir"/zotero-client
# Directory for Zotero build files (needed for scripts/*_build_and_deploy)
ZOTERO_BUILD_DIR="$repo_dir"/zotero-build
# Directory for unpacked binaries
STAGE_DIR="$DIR/staging"
# Directory for packed binaries
DIST_DIR="$DIR/dist"

SOURCE_REPO_URL="https://github.com/zotero/zotero"
S3_BUCKET="zotero-download"
S3_CI_ZIP_PATH="ci/client"
S3_DIST_PATH="standalone"

DEPLOY_HOST="deploy.zotero"
DEPLOY_PATH="www/www-production/public/download/standalone/manifests"
DEPLOY_CMD="ssh $DEPLOY_HOST update-site-files"

BUILD_PLATFORMS=""
NUM_INCREMENTALS=6

if [ -f "$DIR/config-custom.sh" ]; then
	. config-custom.sh
fi

unset DIR
