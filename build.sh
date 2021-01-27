#!/bin/bash -e

# Copyright (c) 2011  Zotero
#                     Center for History and New Media
#                     George Mason University, Fairfax, Virginia, USA
#                     http://zotero.org
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

CALLDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CALLDIR/config.sh"

if [ "`uname`" = "Darwin" ]; then
	MAC_NATIVE=1
else
	MAC_NATIVE=0
fi
if [ "`uname -o 2> /dev/null`" = "Cygwin" ]; then
	WIN_NATIVE=1
else
	WIN_NATIVE=0
fi

function usage {
	cat >&2 <<DONE
Usage: $0 [-d DIR] [-f FILE] -p PLATFORMS [-c CHANNEL] [-d]
Options
 -d DIR              build directory to build from (from build_xpi; cannot be used with -f)
 -f FILE             ZIP file to build from (cannot be used with -d)
 -t                  add devtools
 -p PLATFORMS        build for platforms PLATFORMS (m=Mac, w=Windows, l=Linux)
 -c CHANNEL          use update channel CHANNEL
 -e                  enforce signing
 -s                  don't package; only build binaries in staging/ directory
DONE
	exit 1
}

BUILD_DIR=`mktemp -d`
function cleanup {
	rm -rf $BUILD_DIR
}
trap cleanup EXIT

function abspath {
	echo $(cd $(dirname $1); pwd)/$(basename $1);
}

SOURCE_DIR=""
ZIP_FILE=""
BUILD_MAC=0
BUILD_WIN32=0
BUILD_LINUX=0
PACKAGE=1
DEVTOOLS=0
while getopts "d:f:p:c:tse" opt; do
	case $opt in
		d)
			SOURCE_DIR="$OPTARG"
			;;
		f)
			ZIP_FILE="$OPTARG"
			;;
		p)
			for i in `seq 0 1 $((${#OPTARG}-1))`
			do
				case ${OPTARG:i:1} in
					m) BUILD_MAC=1;;
					w) BUILD_WIN32=1;;
					l) BUILD_LINUX=1;;
					*)
						echo "$0: Invalid platform option ${OPTARG:i:1}"
						usage
						;;
				esac
			done
			;;
		c)
			UPDATE_CHANNEL="$OPTARG"
			;;
		t)
			DEVTOOLS=1
			;;
		e)
			SIGN=1
			;;
		s)
			PACKAGE=0
			;;
		*)
			usage
			;;
	esac
	shift $((OPTIND-1)); OPTIND=1
done

# Require source dir or ZIP file
if [[ -z "$SOURCE_DIR" ]] && [[ -z "$ZIP_FILE" ]]; then
	usage
elif [[ -n "$SOURCE_DIR" ]] && [[ -n "$ZIP_FILE" ]]; then
	usage
fi

# Require at least one platform
if [[ $BUILD_MAC == 0 ]] && [[ $BUILD_WIN32 == 0 ]] && [[ $BUILD_LINUX == 0 ]]; then
	usage
fi

BUILD_ID=`date +%Y%m%d%H%M%S`

shopt -s extglob
mkdir -p "$BUILD_DIR/zotero"
rm -rf "$STAGE_DIR"
mkdir "$STAGE_DIR"
rm -rf "$DIST_DIR"
mkdir "$DIST_DIR"

# Save build id, which is needed for updates manifest
echo $BUILD_ID > "$DIST_DIR/build_id"

if [ -z "$UPDATE_CHANNEL" ]; then UPDATE_CHANNEL="default"; fi

if [ -n "$ZIP_FILE" ]; then
	ZIP_FILE="`abspath $ZIP_FILE`"
	echo "Building from $ZIP_FILE"
	unzip -q $ZIP_FILE -d "$BUILD_DIR/zotero"
else
	# TODO: Could probably just mv instead, at least if these repos are merged
	rsync -a "$SOURCE_DIR/" "$BUILD_DIR/zotero/"
fi

cd "$BUILD_DIR/zotero"

VERSION=`perl -ne 'print and last if s/.*<em:version>(.+)<\/em:version>.*/\1/;' install.rdf`
VERSION_NUMERIC=`perl -ne 'print and last if s/.*<em:version>(\d+\.\d+\.\d+).*<\/em:version>.*/\1/;' install.rdf`
if [ -z "$VERSION" ]; then
	echo "Version number not found in install.rdf"
	exit 1
fi
rm install.rdf

echo
echo "Version: $VERSION"

# Delete Mozilla signing info if present
rm -rf META-INF

# Copy branding
cp -R "$CALLDIR/assets/branding" "$BUILD_DIR/zotero/chrome/branding"

# Add to chrome manifest
echo "" >> "$BUILD_DIR/zotero/chrome.manifest"
cat "$CALLDIR/assets/chrome.manifest" >> "$BUILD_DIR/zotero/chrome.manifest"

# Copy Error Console files
cp "$CALLDIR/assets/console/jsconsole-clhandler.js" "$BUILD_DIR/zotero/components/"
echo >> "$BUILD_DIR/zotero/chrome.manifest"
cat "$CALLDIR/assets/console/jsconsole-clhandler.manifest" >> "$BUILD_DIR/zotero/chrome.manifest"
cp -R "$CALLDIR/assets/console/content" "$BUILD_DIR/zotero/chrome/console"
cp -R "$CALLDIR/assets/console/skin/osx" "$BUILD_DIR/zotero/chrome/console/skin"
cp -R "$CALLDIR/assets/console/locale/en-US" "$BUILD_DIR/zotero/chrome/console/locale"
cat "$CALLDIR/assets/console/jsconsole.manifest" >> "$BUILD_DIR/zotero/chrome.manifest"

# Delete files that shouldn't be distributed
find "$BUILD_DIR/zotero/chrome" -name .DS_Store -exec rm -f {} \;

# Zip chrome into JAR
cd "$BUILD_DIR/zotero"
zip -r -q zotero.jar chrome deleted.txt resource styles.zip translators.index translators.zip styles translators.json translators
rm -rf "chrome/"* install.rdf deleted.txt resource styles.zip translators.index translators.zip styles translators.json translators

# Copy updater.ini
cp "$CALLDIR/assets/updater.ini" "$BUILD_DIR/zotero"

# Adjust chrome.manifest
perl -pi -e 's^(chrome|resource)/^jar:zotero.jar\!/$1/^g' "$BUILD_DIR/zotero/chrome.manifest"

# Adjust connector pref
perl -pi -e 's/pref\("extensions\.zotero\.httpServer\.enabled", false\);/pref("extensions.zotero.httpServer.enabled", true);/g' "$BUILD_DIR/zotero/defaults/preferences/zotero.js"
perl -pi -e 's/pref\("extensions\.zotero\.connector\.enabled", false\);/pref("extensions.zotero.connector.enabled", true);/g' "$BUILD_DIR/zotero/defaults/preferences/zotero.js"

# Copy icons
cp -r "$CALLDIR/assets/icons" "$BUILD_DIR/zotero/chrome/icons"

# Copy application.ini and modify
cp "$CALLDIR/assets/application.ini" "$BUILD_DIR/application.ini"
perl -pi -e "s/\{\{VERSION}}/$VERSION/" "$BUILD_DIR/application.ini"
perl -pi -e "s/\{\{BUILDID}}/$BUILD_ID/" "$BUILD_DIR/application.ini"

# Copy prefs.js and modify
cp "$CALLDIR/assets/prefs.js" "$BUILD_DIR/zotero/defaults/preferences"
perl -pi -e 's/pref\("app\.update\.channel", "[^"]*"\);/pref\("app\.update\.channel", "'"$UPDATE_CHANNEL"'");/' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"

# Add devtools manifest and pref
if [ $DEVTOOLS -eq 1 ]; then
	cat "$CALLDIR/assets/devtools.manifest" >> "$BUILD_DIR/zotero/chrome.manifest"
	echo 'pref("devtools.debugger.remote-enabled", true);' >> "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	echo 'pref("devtools.debugger.remote-port", 6100);' >> "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	echo 'pref("devtools.debugger.prompt-connection", false);' >> "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
fi

echo -n "Channel: "
grep app.update.channel "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
echo

# Remove unnecessary files
find "$BUILD_DIR" -name .DS_Store -exec rm -f {} \;
rm -rf "$BUILD_DIR/zotero/test"

cd "$CALLDIR"

# Mac
if [ $BUILD_MAC == 1 ]; then
	echo 'Building Zotero.app'
		
	# Set up directory structure
	APPDIR="$STAGE_DIR/Zotero.app"
	rm -rf "$APPDIR"
	mkdir "$APPDIR"
	chmod 755 "$APPDIR"
	cp -r "$CALLDIR/mac/Contents" "$APPDIR"
	CONTENTSDIR="$APPDIR/Contents"
	
	# Modify platform-specific prefs
	perl -pi -e 's/pref\("browser\.preferences\.instantApply", false\);/pref\("browser\.preferences\.instantApply", true);/' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	perl -pi -e 's/%GECKO_VERSION%/'"$GECKO_VERSION_MAC"'/g' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	# Fix horizontal mousewheel scrolling (this is set to 4 in the Fx60 .app greprefs.js, but
	# defaults to 1 in later versions of Firefox, and needs to be 1 to work on macOS)
	echo 'pref("mousewheel.with_shift.action", 1);' >> "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	
	# Merge relevant assets from Firefox
	mkdir "$CONTENTSDIR/MacOS"
	cp -r "$MAC_RUNTIME_PATH/Contents/MacOS/"!(firefox|firefox-bin|crashreporter.app|pingsender|updater.app) "$CONTENTSDIR/MacOS"
	cp -r "$MAC_RUNTIME_PATH/Contents/Resources/"!(application.ini|updater.ini|update-settings.ini|browser|devtools-files|precomplete|removed-files|webapprt*|*.icns|defaults|*.lproj) "$CONTENTSDIR/Resources"

	# Use our own launcher
	cp "$CALLDIR/mac/zotero" "$CONTENTSDIR/MacOS/zotero"
	cp "$BUILD_DIR/application.ini" "$CONTENTSDIR/Resources"

	# TEMP: Modified versions of some Firefox components for Big Sur, placed in xulrunner/MacOS
	cp "$MAC_RUNTIME_PATH/../MacOS/"{libnss3.dylib,XUL} "$CONTENTSDIR/MacOS/"

	# Use our own updater, because Mozilla's requires updates signed by Mozilla
	cd "$CONTENTSDIR/MacOS"
	tar -xjf "$CALLDIR/mac/updater.tar.bz2"

	# Copy PDF tools and data
	cp "$CALLDIR/pdftools/pdftotext-mac" "$CONTENTSDIR/MacOS/pdftotext"
	cp "$CALLDIR/pdftools/pdfinfo-mac" "$CONTENTSDIR/MacOS/pdfinfo"
	cp -R "$CALLDIR/pdftools/poppler-data" "$CONTENTSDIR/Resources/"

	# Modify Info.plist
	perl -pi -e "s/\{\{VERSION\}\}/$VERSION/" "$CONTENTSDIR/Info.plist"
	perl -pi -e "s/\{\{VERSION_NUMERIC\}\}/$VERSION_NUMERIC/" "$CONTENTSDIR/Info.plist"
	if [ $UPDATE_CHANNEL == "beta" ] || [ $UPDATE_CHANNEL == "dev" ] || [ $UPDATE_CHANNEL == "source" ]; then
		perl -pi -e "s/org\.zotero\.zotero/org.zotero.zotero-$UPDATE_CHANNEL/" "$CONTENTSDIR/Info.plist"
	fi
	perl -pi -e "s/\{\{VERSION\}\}/$VERSION/" "$CONTENTSDIR/Info.plist"
	# Needed for "monkeypatch" Windows builds: 
	# http://www.nntp.perl.org/group/perl.perl5.porters/2010/08/msg162834.html
	rm -f "$CONTENTSDIR/Info.plist.bak"
	
	echo
	grep -B 1 org.zotero.zotero "$CONTENTSDIR/Info.plist"
	echo
	grep -A 1 CFBundleShortVersionString "$CONTENTSDIR/Info.plist"
	echo
	grep -A 1 CFBundleVersion "$CONTENTSDIR/Info.plist"
	echo
	
	# Add components
	cp -R "$BUILD_DIR/zotero/"* "$CONTENTSDIR/Resources"
	
	# Add Mac-specific Standalone assets
	cd "$CALLDIR/assets/mac"
	zip -r -q "$CONTENTSDIR/Resources/zotero.jar" *
	
	# Add devtools
	if [ $DEVTOOLS -eq 1 ]; then
		cp -r "$MAC_RUNTIME_PATH"/Contents/Resources/devtools-files/chrome/* "$CONTENTSDIR/Resources/chrome/"
		cp "$MAC_RUNTIME_PATH/Contents/Resources/devtools-files/components/interfaces.xpt" "$CONTENTSDIR/Resources/components/"
	fi
	
	# Add word processor plug-ins
	mkdir "$CONTENTSDIR/Resources/extensions"
	cp -RH "$CALLDIR/modules/zotero-word-for-mac-integration" "$CONTENTSDIR/Resources/extensions/zoteroMacWordIntegration@zotero.org"
	cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$CONTENTSDIR/Resources/extensions/zoteroOpenOfficeIntegration@zotero.org"
	echo
	for ext in "zoteroMacWordIntegration@zotero.org" "zoteroOpenOfficeIntegration@zotero.org"; do
		perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$CONTENTSDIR/Resources/extensions/$ext/install.rdf"
		echo -n "$ext Version: "
		perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$CONTENTSDIR/Resources/extensions/$ext/install.rdf"
		rm -rf "$CONTENTSDIR/Resources/extensions/$ext/.git"
	done
	# Add Mac Word plugin's XPC Service
	mkdir -p "$CONTENTSDIR/XPCServices"
	mv "$CONTENTSDIR/Resources/extensions/zoteroMacWordIntegration@zotero.org/resource/ZoteroWordIntegrationService.xpc" "$CONTENTSDIR/XPCServices"
	# Default preferenes are no longer read from built-in extensions in Firefox 60
	echo >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	cat "$CALLDIR/modules/zotero-word-for-mac-integration/defaults/preferences/zoteroMacWordIntegration.js" >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	echo >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	cat "$CALLDIR/modules/zotero-libreoffice-integration/defaults/preferences/zoteroOpenOfficeIntegration.js" >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	echo
	
	# Delete extraneous files
	find "$CONTENTSDIR" -depth -type d -name .git -exec rm -rf {} \;
	find "$CONTENTSDIR" \( -name .DS_Store -or -name update.rdf \) -exec rm -f {} \;
	find "$CONTENTSDIR/Resources/extensions" -depth -type d -name build -exec rm -rf {} \;

	# Copy over removed-files and make a precomplete file since it
	# needs to be stable for the signature
	cp "$CALLDIR/update-packaging/removed-files_mac" "$CONTENTSDIR/Resources/removed-files"
	touch "$CONTENTSDIR/Resources/precomplete"
	
	# Sign
	if [ $SIGN == 1 ]; then
		# Unlock keychain if a password is provided (necessary for building from a shell)
		if [ -n "$KEYCHAIN_PASSWORD" ]; then
			security -v unlock-keychain -p "$KEYCHAIN_PASSWORD" ~/Library/Keychains/$KEYCHAIN.keychain-db
		fi
		# Clear extended attributes, which can cause codesign to fail
		/usr/bin/xattr -cr "$APPDIR"

		# Sign app
		entitlements_file="$CALLDIR/mac/entitlements.xml"
		/usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" \
			"$APPDIR/Contents/MacOS/pdftotext" \
			"$APPDIR/Contents/MacOS/pdfinfo" \
			"$APPDIR/Contents/MacOS/XUL" \
			"$APPDIR/Contents/MacOS/updater.app/Contents/MacOS/org.mozilla.updater" \
			"$APPDIR/Contents/XPCServices/ZoteroWordIntegrationService.xpc/Contents/MacOS/ZoteroWordIntegrationService" \
			"$APPDIR/Contents/XPCServices/ZoteroWordIntegrationService.xpc"
		find "$APPDIR/Contents" -name '*.dylib' -exec /usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" {} \;
		find "$APPDIR/Contents" -name '*.app' -exec /usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" {} \;
		/usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" "$APPDIR/Contents/MacOS/zotero"
		
		# Bundle and sign Safari App Extension
		#
		# Even though it's signed by Xcode, we sign it again to make sure it matches the parent app signature
		if [[ -n "$SAFARI_APPEX" ]] && [[ -d "$SAFARI_APPEX" ]]; then
			echo
			# Extract entitlements, which differ from parent app
			/usr/bin/codesign -d --entitlements :"$BUILD_DIR/safari-entitlements.plist" $SAFARI_APPEX
			mkdir "$APPDIR/Contents/PlugIns"
			cp -R $SAFARI_APPEX "$APPDIR/Contents/PlugIns/ZoteroSafariExtension.appex"
			# Add suffix to appex bundle identifier
			if [ $UPDATE_CHANNEL == "beta" ] || [ $UPDATE_CHANNEL == "dev" ] || [ $UPDATE_CHANNEL == "source" ]; then
				perl -pi -e "s/org\.zotero\.SafariExtensionApp\.SafariExtension/org.zotero.SafariExtensionApp.SafariExtension-$UPDATE_CHANNEL/" "$APPDIR/Contents/PlugIns/ZoteroSafariExtension.appex/Contents/Info.plist"
			fi
			find "$APPDIR/Contents/PlugIns/ZoteroSafariExtension.appex/Contents" -name '*.dylib' -exec /usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" {} \;
			/usr/bin/codesign --force --options runtime --entitlements "$BUILD_DIR/safari-entitlements.plist" --sign "$DEVELOPER_ID" "$APPDIR/Contents/PlugIns/ZoteroSafariExtension.appex"
		fi
		
		# Sign final app package
		echo
		/usr/bin/codesign --force --options runtime --entitlements "$entitlements_file" --sign "$DEVELOPER_ID" "$APPDIR"
		
		# Verify app
		/usr/bin/codesign --verify -vvvv "$APPDIR"
		# Verify Safari App Extension
		if [[ -n "$SAFARI_APPEX" ]] && [[ -d "$SAFARI_APPEX" ]]; then
			echo
			/usr/bin/codesign --verify -vvvv "$APPDIR/Contents/PlugIns/ZoteroSafariExtension.appex"
		fi
	fi
	
	# Build and notarize disk image
	if [ $PACKAGE == 1 ]; then
		if [ $MAC_NATIVE == 1 ]; then
			echo "Creating Mac installer"
			dmg="$DIST_DIR/Zotero-$VERSION.dmg"
			"$CALLDIR/mac/pkg-dmg" --source "$STAGE_DIR/Zotero.app" \
				--target "$dmg" \
				--sourcefile --volname Zotero --copy "$CALLDIR/mac/DSStore:/.DS_Store" \
				--symlink /Applications:"/Drag Here to Install" > /dev/null
			
			# Upload disk image to Apple
			output=$("$CALLDIR/scripts/notarize_mac_app" "$dmg")
			echo
			echo "$output"
			echo
			id=$(echo "$output" | plutil -extract notarization-upload.RequestUUID xml1 -o - - | sed -n "s/.*<string>\(.*\)<\/string>.*/\1/p")
			echo "Notarization request identifier: $id"
			echo
			
			sleep 60
			
			# Check back every 30 seconds, for up to an hour
			i="0"
			while [ $i -lt 120 ]
			do
				status=$("$CALLDIR/scripts/notarization_status" $id)
				if [[ $status != "in progress" ]]; then
					break
				fi
				echo "Notarization in progress"
				sleep 30
				i=$[$i+1]
			done
			
			# Staple notarization info to disk image
			if [ $status == "success" ]; then
				"$CALLDIR/scripts/notarization_stapler" "$dmg"
			else
				echo "Notarization failed!"
				"$CALLDIR/scripts/notarization_status" $id
				exit 1
			fi
			
			echo "Notarization complete"
		else
			echo 'Not building on Mac; creating Mac distribution as a zip file'
			rm -f "$DIST_DIR/Zotero_mac.zip"
			cd "$STAGE_DIR" && zip -rqX "$DIST_DIR/Zotero-${VERSION}_mac.zip" Zotero.app
		fi
	fi
fi

# Win32
if [ $BUILD_WIN32 == 1 ]; then
	echo 'Building Zotero_win32'
	
	# Set up directory
	APPDIR="$STAGE_DIR/Zotero_win32"
	rm -rf "$APPDIR"
	mkdir "$APPDIR"
	
	# Modify platform-specific prefs
	perl -pi -e 's/%GECKO_VERSION%/'"$GECKO_VERSION_WIN"'/g' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	
	# Copy relevant assets from Firefox
	cp -R "$WIN32_RUNTIME_PATH"/!(application.ini|browser|defaults|devtools-files|crashreporter*|firefox.exe|maintenanceservice*|precomplete|removed-files|uninstall|update*) "$APPDIR"

	# Copy zotero_win32.exe, which is built directly from Firefox source
	#
	# After the initial build the temporary resource in "C:\mozilla-source\obj-i686-pc-mingw32\browser\app\module.res"
	# is modified with Visual Studio resource editor where icon and file details are changed.
	# Then firefox.exe is rebuilt again
	cp "$CALLDIR/win/zotero_win32.exe" "$APPDIR/zotero.exe"

	# Use our own updater, because Mozilla's requires updates signed by Mozilla
	cp "$CALLDIR/win/updater.exe" "$APPDIR"
	cat "$CALLDIR/win/installer/updater_append.ini" >> "$APPDIR/updater.ini"

	# Copy PDF tools and data
	cp "$CALLDIR/pdftools/pdftotext-win.exe" "$APPDIR/pdftotext.exe"
	cp "$CALLDIR/pdftools/pdfinfo-win.exe" "$APPDIR/pdfinfo.exe"
	cp -R "$CALLDIR/pdftools/poppler-data" "$APPDIR/"
	
	cp -R "$BUILD_DIR/zotero/"* "$BUILD_DIR/application.ini" "$APPDIR"
	
	# Add Windows-specific Standalone assets
	cd "$CALLDIR/assets/win"
	zip -r -q "$APPDIR/zotero.jar" *
	
	# Add devtools
	if [ $DEVTOOLS -eq 1 ]; then
		cp -r "$WIN32_RUNTIME_PATH"/devtools-files/chrome/* "$APPDIR/chrome/"
		cp "$WIN32_RUNTIME_PATH/devtools-files/components/interfaces.xpt" "$APPDIR/components/"
	fi
	
	# Add word processor plug-ins
	mkdir "$APPDIR/extensions"
	cp -RH "$CALLDIR/modules/zotero-word-for-windows-integration" "$APPDIR/extensions/zoteroWinWordIntegration@zotero.org"
	cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
	echo
	for ext in "zoteroWinWordIntegration@zotero.org" "zoteroOpenOfficeIntegration@zotero.org"; do
		perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$APPDIR/extensions/$ext/install.rdf"
		echo -n "$ext Version: "
		perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$APPDIR/extensions/$ext/install.rdf"
		rm -rf "$APPDIR/extensions/$ext/.git"
	done
	# Default preferenes are no longer read from built-in extensions in Firefox 60
	echo >> "$APPDIR/defaults/preferences/prefs.js"
	cat "$CALLDIR/modules/zotero-word-for-windows-integration/defaults/preferences/zoteroWinWordIntegration.js" >> "$APPDIR/defaults/preferences/prefs.js"
	echo >> "$APPDIR/defaults/preferences/prefs.js"
	cat "$CALLDIR/modules/zotero-libreoffice-integration/defaults/preferences/zoteroOpenOfficeIntegration.js" >> "$APPDIR/defaults/preferences/prefs.js"
	echo >> "$APPDIR/defaults/preferences/prefs.js"
	echo

	# Delete extraneous files
	find "$APPDIR" -depth -type d -name .git -exec rm -rf {} \;
	find "$APPDIR" \( -name .DS_Store -or -name '.git*' -or -name '.travis.yml' -or -name update.rdf -or -name '*.bak' \) -exec rm -f {} \;
	find "$APPDIR/extensions" -depth -type d -name build -exec rm -rf {} \;
	find "$APPDIR" \( -name '*.exe' -or -name '*.dll' \) -exec chmod 755 {} \;
	
	if [ $PACKAGE == 1 ]; then
		if [ $WIN_NATIVE == 1 ]; then
			INSTALLER_PATH="$DIST_DIR/Zotero-${VERSION}_setup.exe"
			
			echo 'Creating Windows installer'
			# Copy installer files
			cp -r "$CALLDIR/win/installer" "$BUILD_DIR/win_installer"
			
			# Build and sign uninstaller
			perl -pi -e "s/\{\{VERSION}}/$VERSION/" "$BUILD_DIR/win_installer/defines.nsi"
			"`cygpath -u \"${NSIS_DIR}makensis.exe\"`" /V1 "`cygpath -w \"$BUILD_DIR/win_installer/uninstaller.nsi\"`"
			mkdir "$APPDIR/uninstall"
			mv "$BUILD_DIR/win_installer/helper.exe" "$APPDIR/uninstall"
			
			# Sign zotero.exe, dlls, updater, uninstaller and PDF tools
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "Zotero" /du "$SIGNATURE_URL" \
					/t http://timestamp.verisign.com/scripts/timstamp.dll \
					"`cygpath -w \"$APPDIR/zotero.exe\"`"
				for dll in "$APPDIR/"*.dll "$APPDIR/"*.dll; do
					"`cygpath -u \"$SIGNTOOL\"`" sign /n "$SIGNTOOL_CERT_SUBJECT" /d "Zotero" \
						/du "$SIGNATURE_URL" "`cygpath -w \"$dll\"`"
				done
				"`cygpath -u \"$SIGNTOOL\"`" sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "Zotero Updater" /du "$SIGNATURE_URL" \
					/t http://timestamp.verisign.com/scripts/timstamp.dll \
					"`cygpath -w \"$APPDIR/updater.exe\"`"
				"`cygpath -u \"$SIGNTOOL\"`" sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "Zotero Uninstaller" /du "$SIGNATURE_URL" \
					/t http://timestamp.verisign.com/scripts/timstamp.dll \
					"`cygpath -w \"$APPDIR/uninstall/helper.exe\"`"
				"`cygpath -u \"$SIGNTOOL\"`" sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "PDF Converter" /du "$SIGNATURE_URL" \
					/t http://timestamp.verisign.com/scripts/timstamp.dll \
					"`cygpath -w \"$APPDIR/pdftotext.exe\"`"
				"`cygpath -u \"$SIGNTOOL\"`" sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "PDF Info" /du "$SIGNATURE_URL" \
					/t http://timestamp.verisign.com/scripts/timstamp.dll \
					"`cygpath -w \"$APPDIR/pdfinfo.exe\"`"
			fi
			
			# Stage installer
			INSTALLER_STAGE_DIR="$BUILD_DIR/win_installer/staging"
			mkdir "$INSTALLER_STAGE_DIR"
			cp -R "$APPDIR" "$INSTALLER_STAGE_DIR/core"
			
			# Build and sign setup.exe
			"`cygpath -u \"${NSIS_DIR}makensis.exe\"`" /V1 "`cygpath -w \"$BUILD_DIR/win_installer/installer.nsi\"`"
			mv "$BUILD_DIR/win_installer/setup.exe" "$INSTALLER_STAGE_DIR"
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "Zotero Setup" /du "$SIGNATURE_URL" \
					/t http://timestamp.verisign.com/scripts/timstamp.dll \
					"`cygpath -w \"$INSTALLER_STAGE_DIR/setup.exe\"`"
			fi
			
			# Compress application
			cd "$INSTALLER_STAGE_DIR" && 7z a -r -t7z "`cygpath -w \"$BUILD_DIR/app_win32.7z\"`" \
				-mx -m0=BCJ2 -m1=LZMA:d24 -m2=LZMA:d19 -m3=LZMA:d19  -mb0:1 -mb0s1:2 -mb0s2:3 > /dev/null
				
			# Compress 7zSD.sfx
			upx --best -o "`cygpath -w \"$BUILD_DIR/7zSD.sfx\"`" \
				"`cygpath -w \"$CALLDIR/win/installer/7zstub/firefox/7zSD.sfx\"`" > /dev/null
			
			# Combine 7zSD.sfx and app.tag into setup.exe
			cat "$BUILD_DIR/7zSD.sfx" "$CALLDIR/win/installer/app.tag" \
				"$BUILD_DIR/app_win32.7z" > "$INSTALLER_PATH"
			
			# Sign Zotero_setup.exe
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" sign /a \
					/d "Zotero Setup" /du "$SIGNATURE_URL" \
					/t http://timestamp.verisign.com/scripts/timstamp.dll \
					"`cygpath -w \"$INSTALLER_PATH\"`"
			fi
			
			chmod 755 "$INSTALLER_PATH"
		else
			echo 'Not building on Windows; only building zip file'
		fi
		cd "$STAGE_DIR" && zip -rqX "$DIST_DIR/Zotero-${VERSION}_win32.zip" Zotero_win32
	fi
fi

# Linux
if [ $BUILD_LINUX == 1 ]; then
	for arch in "i686" "x86_64"; do
		RUNTIME_PATH=`eval echo '$LINUX_'$arch'_RUNTIME_PATH'`
		
		# Set up directory
		echo 'Building Zotero_linux-'$arch
		APPDIR="$STAGE_DIR/Zotero_linux-$arch"
		rm -rf "$APPDIR"
		mkdir "$APPDIR"
		
		# Merge relevant assets from Firefox
		cp -r "$RUNTIME_PATH/"!(application.ini|browser|defaults|devtools-files|crashreporter|crashreporter.ini|firefox-bin|pingsender|precomplete|removed-files|run-mozilla.sh|update-settings.ini|updater|updater.ini) "$APPDIR"
		
		# Use our own launcher that calls the original Firefox executable with -app
		mv "$APPDIR"/firefox "$APPDIR"/zotero-bin
		cp "$CALLDIR/linux/zotero" "$APPDIR"/zotero
		
		# Copy Ubuntu launcher files
		cp "$CALLDIR/linux/zotero.desktop" "$APPDIR"
		cp "$CALLDIR/linux/set_launcher_icon" "$APPDIR"
		
		# Use our own updater, because Mozilla's requires updates signed by Mozilla
		cp "$CALLDIR/linux/updater-$arch" "$APPDIR"/updater

		# Copy PDF tools and data
		cp "$CALLDIR/pdftools/pdftotext-linux-$arch" "$APPDIR/pdftotext"
		cp "$CALLDIR/pdftools/pdfinfo-linux-$arch" "$APPDIR/pdfinfo"
		cp -R "$CALLDIR/pdftools/poppler-data" "$APPDIR/"
		
		cp -R "$BUILD_DIR/zotero/"* "$BUILD_DIR/application.ini" "$APPDIR"
		
		# Modify platform-specific prefs
		perl -pi -e 's/pref\("browser\.preferences\.instantApply", false\);/pref\("browser\.preferences\.instantApply", true);/' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
		perl -pi -e 's/%GECKO_VERSION%/'"$GECKO_VERSION_LINUX"'/g' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
		
		# Add Unix-specific Standalone assets
		cd "$CALLDIR/assets/unix"
		zip -0 -r -q "$APPDIR/zotero.jar" *
		
		# Add devtools
		if [ $DEVTOOLS -eq 1 ]; then
			cp -r "$RUNTIME_PATH"/devtools-files/chrome/* "$APPDIR/chrome/"
			cp "$RUNTIME_PATH/devtools-files/components/interfaces.xpt" "$APPDIR/components/"
		fi
		
		# Add word processor plug-ins
		mkdir "$APPDIR/extensions"
		cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
		perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
		echo
		echo -n "zoteroOpenOfficeIntegration@zotero.org Version: "
		perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
		echo
		rm -rf "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/.git"
		# Default preferenes are no longer read from built-in extensions in Firefox 60
		echo >> "$APPDIR/defaults/preferences/prefs.js"
		cat "$CALLDIR/modules/zotero-libreoffice-integration/defaults/preferences/zoteroOpenOfficeIntegration.js" >> "$APPDIR/defaults/preferences/prefs.js"
		echo >> "$APPDIR/defaults/preferences/prefs.js"
		
		# Delete extraneous files
		find "$APPDIR" -depth -type d -name .git -exec rm -rf {} \;
		find "$APPDIR" \( -name .DS_Store -or -name update.rdf \) -exec rm -f {} \;
		find "$APPDIR/extensions" -depth -type d -name build -exec rm -rf {} \;
		
		if [ $PACKAGE == 1 ]; then
			# Create tar
			rm -f "$DIST_DIR/Zotero-${VERSION}_linux-$arch.tar.bz2"
			cd "$STAGE_DIR"
			tar -cjf "$DIST_DIR/Zotero-${VERSION}_linux-$arch.tar.bz2" "Zotero_linux-$arch"
		fi
	done
fi

rm -rf $BUILD_DIR
