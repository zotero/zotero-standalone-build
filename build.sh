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
 -q                  quick build (skip compression and other optional steps for faster restarts during development)
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
quick_build=0
while getopts "d:f:p:c:tseq" opt; do
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
		q)
			quick_build=1
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

if [[ -z "${ZOTERO_INCLUDE_TESTS:-}" ]] || [[ $ZOTERO_INCLUDE_TESTS == "0" ]]; then
	include_tests=0
else
	include_tests=1
fi

# Bundle devtools with dev builds
if [ $UPDATE_CHANNEL == "beta" ] || [ $UPDATE_CHANNEL == "dev" ]; then
	DEVTOOLS=1
fi
if [ -z "$UPDATE_CHANNEL" ]; then UPDATE_CHANNEL="default"; fi
BUILD_ID=`date +%Y%m%d%H%M%S`

base_dir="$BUILD_DIR/base"
app_dir="$BUILD_DIR/base/app"
omni_dir="$BUILD_DIR/base/app/omni"

shopt -s extglob
mkdir -p "$app_dir"
rm -rf "$STAGE_DIR"
mkdir "$STAGE_DIR"
rm -rf "$DIST_DIR"
mkdir "$DIST_DIR"

# Save build id, which is needed for updates manifest
echo $BUILD_ID > "$DIST_DIR/build_id"

cd "$app_dir"

# Copy 'browser' files from Firefox
#
# omni.ja is left uncompressed within the Firefox application files by fetch_xulrunner
set +e
if [ $BUILD_MAC == 1 ]; then
	cp -Rp "$MAC_RUNTIME_PATH"/Contents/Resources/browser/omni "$app_dir"
elif [ $BUILD_WIN32 == 1 ]; then
	cp -Rp "$WIN32_RUNTIME_PATH"/browser/omni "$app_dir"
elif [ $BUILD_LINUX == 1 ]; then
	# Non-arch-specific files, so just use 64-bit version
	cp -Rp "$LINUX_x86_64_RUNTIME_PATH"/browser/omni "$app_dir"
fi
set -e
cd omni
# Move some Firefox files that would be overwritten out of the way
mv chrome.manifest chrome.manifest-fx
mv components components-fx
mv defaults defaults-fx

# Extract Zotero files
if [ -n "$ZIP_FILE" ]; then
	ZIP_FILE="`abspath $ZIP_FILE`"
	echo "Building from $ZIP_FILE"
	unzip -q $ZIP_FILE -d "$omni_dir"
else
	rsync_params=""
	if [ $include_tests -eq 0 ]; then
		rsync_params="--exclude /test"
	fi
	rsync -a $rsync_params "$SOURCE_DIR/" ./
fi

#
# Merge preserved files from Firefox
#
# components
mv components/* components-fx
rmdir components
mv components-fx components

# defaults
cp "$CALLDIR/assets/prefs.js" defaults-fx/preferences/zotero.js
cat defaults/preferences/zotero.js >> defaults-fx/preferences/zotero.js

# Remove telemetry prefs
grep -v telemetry defaults-fx/preferences/firefox.js > defaults-fx/preferences/firefox.js.tmp
mv defaults-fx/preferences/firefox.js.tmp defaults-fx/preferences/firefox.js

prefs_file=defaults/preferences/zotero.js
rm $prefs_file
rmdir defaults/preferences
rmdir defaults
mv defaults-fx defaults

# Platform-specific prefs
if [ $BUILD_MAC == 1 ]; then
	perl -pi -e 's/pref\("browser\.preferences\.instantApply", false\);/pref\("browser\.preferences\.instantApply", true);/' $prefs_file
	perl -pi -e 's/%GECKO_VERSION%/'"$GECKO_VERSION_MAC"'/g' $prefs_file
	# Fix horizontal mousewheel scrolling (this is set to 4 in the Fx60 .app greprefs.js, but
	# defaults to 1 in later versions of Firefox, and needs to be 1 to work on macOS)
	echo 'pref("mousewheel.with_shift.action", 1);' >> $prefs_file
elif [ $BUILD_WIN32 == 1 ]; then
	perl -pi -e 's/%GECKO_VERSION%/'"$GECKO_VERSION_WIN"'/g' $prefs_file
elif [ $BUILD_LINUX == 1 ]; then
	# Modify platform-specific prefs
	perl -pi -e 's/pref\("browser\.preferences\.instantApply", false\);/pref\("browser\.preferences\.instantApply", true);/' $prefs_file
	perl -pi -e 's/%GECKO_VERSION%/'"$GECKO_VERSION_LINUX"'/g' $prefs_file
fi

# Clear list of built-in add-ons
echo '{"dictionaries": {"en-US": "dictionaries/en-US.dic"}, "system": []}' > chrome/browser/content/browser/built_in_addons.json

# chrome.manifest
mv chrome.manifest zotero.manifest
mv chrome.manifest-fx chrome.manifest
# TEMP
#echo "manifest zotero.manifest" >> "$base_dir/chrome.manifest"
cat zotero.manifest >> chrome.manifest
rm zotero.manifest

# Update channel
perl -pi -e 's/pref\("app\.update\.channel", "[^"]*"\);/pref\("app\.update\.channel", "'"$UPDATE_CHANNEL"'");/' $prefs_file
echo -n "Channel: "
grep app.update.channel $prefs_file
echo

# Add devtools prefs
if [ $DEVTOOLS -eq 1 ]; then
	echo >> $prefs_file
	echo "// Dev Tools" >> $prefs_file
	echo 'pref("devtools.debugger.remote-enabled", true);' >> $prefs_file
	echo 'pref("devtools.debugger.remote-port", 6100);' >> $prefs_file
	if [ $UPDATE_CHANNEL != "beta" ]; then
		echo 'pref("devtools.debugger.prompt-connection", false);' >> $prefs_file
	fi
fi

# 5.0.96.3 / 5.0.97-beta.37+ddc7be75c
VERSION=`perl -ne 'print and last if s/.*<em:version>(.+)<\/em:version>.*/\1/;' install.rdf`
# 5.0.96 / 5.0.97
VERSION_NUMERIC=`perl -ne 'print and last if s/.*<em:version>(\d+\.\d+(\.\d+)?).*<\/em:version>.*/\1/;' install.rdf`
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
#cp -R "$CALLDIR/assets/branding/content" chrome/branding/content
cp -R "$CALLDIR"/assets/branding/locale/brand.{dtd,properties} chrome/en-US/locale/branding/
cp "$CALLDIR/assets/branding/locale/brand.ftl" localization/en-US/branding/brand.ftl

# Copy localization .ftl files
for locale in `ls chrome/locale/`; do
	mkdir -p localization/$locale/zotero
	cp chrome/locale/$locale/zotero/mozilla/*.ftl localization/$locale/zotero/
done

# Add to chrome manifest
echo "" >> chrome.manifest
cat "$CALLDIR/assets/chrome.manifest" >> chrome.manifest

# Move test files to root directory
if [ $include_tests -eq 1 ]; then
	cat test/chrome.manifest >> chrome.manifest
	rm test/chrome.manifest
	cp -R test/tests "$base_dir/tests"
fi

# Copy platform-specific assets
if [ $BUILD_MAC == 1 ]; then
	rsync -a "$CALLDIR/assets/mac/" ./
elif [ $BUILD_WIN32 == 1 ]; then
	rsync -a "$CALLDIR/assets/win/" ./
elif [ $BUILD_LINUX == 1 ]; then
	rsync -a "$CALLDIR/assets/unix/" ./
fi

if [ $BUILD_MAC == 1 ]; then
	mv chrome/content/zotero/standalone/hiddenWindow.xul chrome/browser/content/browser/hiddenWindowMac.xhtml
fi

# Delete files that shouldn't be distributed
find chrome -name .DS_Store -exec rm -f {} \;

# Zip browser and Zotero files into omni.ja
if [ $quick_build -eq 1 ]; then
	# If quick build, don't compress or optimize
	zip -qrXD omni.ja *
else
	zip -qr9XD omni.ja *
	python3 "$CALLDIR/scripts/optimizejars.py" --optimize ./ ./ ./
fi

mv omni.ja ..
rm -rf "$omni_dir"

# Copy updater.ini
cp "$CALLDIR/assets/updater.ini" "$base_dir"

# Adjust chrome.manifest
#perl -pi -e 's^(chrome|resource)/^jar:zotero.jar\!/$1/^g' "$BUILD_DIR/zotero/chrome.manifest"

# Copy icons
mkdir "$base_dir/chrome"
cp -R "$CALLDIR/assets/icons" "$base_dir/chrome/icons"

# Copy application.ini and modify
cp "$CALLDIR/assets/application.ini" "$app_dir/application.ini"
perl -pi -e "s/\{\{VERSION}}/$VERSION/" "$app_dir/application.ini"
perl -pi -e "s/\{\{BUILDID}}/$BUILD_ID/" "$app_dir/application.ini"

# Remove unnecessary files
find "$BUILD_DIR" -name .DS_Store -exec rm -f {} \;

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
	
	# Merge relevant assets from Firefox
	mkdir "$CONTENTSDIR/MacOS"
	cp -r "$MAC_RUNTIME_PATH/Contents/MacOS/"!(firefox|firefox-bin|crashreporter.app|pingsender|updater.app) "$CONTENTSDIR/MacOS"
	cp -r "$MAC_RUNTIME_PATH/Contents/Resources/"!(application.ini|browser|defaults|precomplete|removed-files|updater.ini|update-settings.ini|webapprt*|*.icns|*.lproj) "$CONTENTSDIR/Resources"

	# Use our own launcher
	unzip -q "$CALLDIR/mac/zotero.zip" -d "$CONTENTSDIR/MacOS"

	# TEMP: Modified versions of some Firefox components for Big Sur, placed in xulrunner/MacOS
	#cp "$MAC_RUNTIME_PATH/../MacOS/"{libc++.1.dylib,libnss3.dylib,XUL} "$CONTENTSDIR/MacOS/"

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
	
	# Copy app files
	rsync -a "$base_dir/" "$CONTENTSDIR/Resources/"
	
	# Add devtools
	#if [ $DEVTOOLS -eq 1 ]; then
	#	# Create devtools.jar
	#	cd "$BUILD_DIR"
	#	mkdir -p devtools/locale
	#	cp -r "$MAC_RUNTIME_PATH"/Contents/Resources/devtools-files/chrome/devtools/* devtools/
	#	cp -r "$MAC_RUNTIME_PATH"/Contents/Resources/devtools-files/chrome/locale/* devtools/locale/
	#	cd devtools
	#	zip -r -q ../devtools.jar *
	#	cd ..
	#	rm -rf devtools
	#	mv devtools.jar "$CONTENTSDIR/Resources/"
	#	
	#	cp "$MAC_RUNTIME_PATH/Contents/Resources/devtools-files/components/interfaces.xpt" "$CONTENTSDIR/Resources/components/"
	#fi
	
	# Add word processor plug-ins
	mkdir "$CONTENTSDIR/Resources/extensions"
	cp -RH "$CALLDIR/modules/zotero-word-for-mac-integration" "$CONTENTSDIR/Resources/extensions/zoteroMacWordIntegration@zotero.org"
	cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$CONTENTSDIR/Resources/extensions/zoteroOpenOfficeIntegration@zotero.org"
	echo
	for ext in "zoteroMacWordIntegration@zotero.org" "zoteroOpenOfficeIntegration@zotero.org"; do
		perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$CONTENTSDIR/Resources/extensions/$ext/install.rdf"
		echo -n "$ext Version: "
		perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$CONTENTSDIR/Resources/extensions/$ext/install.rdf"
		rm -rf "$CONTENTSDIR/Resources/extensions/$ext/.git" "$CONTENTSDIR/Resources/extensions/$ext/.github"
	done
	# Default preferenes are no longer read from built-in extensions in Firefox 60
	#echo >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	#cat "$CALLDIR/modules/zotero-word-for-mac-integration/defaults/preferences/zoteroMacWordIntegration.js" >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	#echo >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	#cat "$CALLDIR/modules/zotero-libreoffice-integration/defaults/preferences/zoteroOpenOfficeIntegration.js" >> "$CONTENTSDIR/Resources/defaults/preferences/prefs.js"
	#echo
	
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
	
	# Copy relevant assets from Firefox
	cp -R "$WIN32_RUNTIME_PATH"/!(application.ini|browser|defaults|devtools-files|crashreporter*|firefox.exe|maintenanceservice*|precomplete|removed-files|uninstall|update*) "$APPDIR"

	# Copy zotero_win32.exe, which is built directly from Firefox source
	#
	# After the initial build the temporary resource in "C:\mozilla-source\obj-i686-pc-mingw32\browser\app\module.res"
	# is modified with Visual Studio resource editor where icon and file details are changed.
	# Then firefox.exe is rebuilt again
	cp "$CALLDIR/win/zotero_win32.exe" "$APPDIR/zotero.exe"
	
	# Update .exe version number (only possible on Windows)
	if [ $WIN_NATIVE == 1 ]; then
		# FileVersion is limited to four integers, so it won't be properly updated for non-release
		# builds (e.g., we'll show 5.0.97.0 for 5.0.97-beta.37). ProductVersion will be the full
		# version string.
		rcedit "`cygpath -w \"$APPDIR/zotero.exe\"`" \
			--set-file-version "$VERSION_NUMERIC" \
			--set-product-version "$VERSION"
	fi
	
	# Use our own updater, because Mozilla's requires updates signed by Mozilla
	cp "$CALLDIR/win/updater.exe" "$APPDIR"
	cat "$CALLDIR/win/installer/updater_append.ini" >> "$APPDIR/updater.ini"

	# Copy PDF tools and data
	cp "$CALLDIR/pdftools/pdftotext-win.exe" "$APPDIR/pdftotext.exe"
	cp "$CALLDIR/pdftools/pdfinfo-win.exe" "$APPDIR/pdfinfo.exe"
	cp -R "$CALLDIR/pdftools/poppler-data" "$APPDIR/"
	
	# Copy app files
	rsync -a "$base_dir/" "$APPDIR/"
	
	# Add devtools
	#if [ $DEVTOOLS -eq 1 ]; then
	#	# Create devtools.jar
	#	cd "$BUILD_DIR"
	#	mkdir -p devtools/locale
	#	cp -r "$WIN32_RUNTIME_PATH"/devtools-files/chrome/devtools/* devtools/
	#	cp -r "$WIN32_RUNTIME_PATH"/devtools-files/chrome/locale/* devtools/locale/
	#	cd devtools
	#	zip -r -q ../devtools.jar *
	#	cd ..
	#	rm -rf devtools
	#	mv devtools.jar "$APPDIR"
	#	
	#	cp "$WIN32_RUNTIME_PATH/devtools-files/components/interfaces.xpt" "$APPDIR/components/"
	#fi
	
	# Add word processor plug-ins
	mkdir "$APPDIR/extensions"
	cp -RH "$CALLDIR/modules/zotero-word-for-windows-integration" "$APPDIR/extensions/zoteroWinWordIntegration@zotero.org"
	cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
	echo
	for ext in "zoteroWinWordIntegration@zotero.org" "zoteroOpenOfficeIntegration@zotero.org"; do
		perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$APPDIR/extensions/$ext/install.rdf"
		echo -n "$ext Version: "
		perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$APPDIR/extensions/$ext/install.rdf"
		rm -rf "$APPDIR/extensions/$ext/.git" "$APPDIR/extensions/$ext/.github"
	done
	# Default preferenes are no longer read from built-in extensions in Firefox 60
	#echo >> "$APPDIR/defaults/preferences/prefs.js"
	#cat "$CALLDIR/modules/zotero-word-for-windows-integration/defaults/preferences/zoteroWinWordIntegration.js" >> "$APPDIR/defaults/preferences/prefs.js"
	#echo >> "$APPDIR/defaults/preferences/prefs.js"
	#cat "$CALLDIR/modules/zotero-libreoffice-integration/defaults/preferences/zoteroOpenOfficeIntegration.js" >> "$APPDIR/defaults/preferences/prefs.js"
	#echo >> "$APPDIR/defaults/preferences/prefs.js"
	#echo

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
			
			# Sign zotero.exe, updater, uninstaller and PDF tools
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC" \
					/du "$SIGNATURE_URL" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
					/td SHA256 \
					"`cygpath -w \"$APPDIR/zotero.exe\"`"
				sleep $SIGNTOOL_DELAY

				#
				# Windows doesn't check DLL signatures
				#
				#for dll in "$APPDIR/"*.dll "$APPDIR/"*.dll; do
				#	"`cygpath -u \"$SIGNTOOL\"`" \
				#		sign /n "$SIGNTOOL_CERT_SUBJECT" \
				#		/d "$SIGNATURE_DESC" \
				#		/fd SHA256 \
				#		/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
				#		/td SHA256 \
				#		"`cygpath -w \"$dll\"`"
				#done
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC Updater" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
					/td SHA256 \
					"`cygpath -w \"$APPDIR/updater.exe\"`"
				sleep $SIGNTOOL_DELAY
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC Uninstaller" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
					/td SHA256 \
					"`cygpath -w \"$APPDIR/uninstall/helper.exe\"`"
				sleep $SIGNTOOL_DELAY
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC PDF Converter" \
					/fd SHA256 \
                                        /tr "$SIGNTOOL_TIMESTAMP_SERVER" \
                                        /td SHA256 \
					"`cygpath -w \"$APPDIR/pdftotext.exe\"`"
				sleep $SIGNTOOL_DELAY
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC PDF Info" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
					/td SHA256 \
					"`cygpath -w \"$APPDIR/pdfinfo.exe\"`"
				sleep $SIGNTOOL_DELAY
			fi
			
			# Stage installer
			INSTALLER_STAGE_DIR="$BUILD_DIR/win_installer/staging"
			mkdir "$INSTALLER_STAGE_DIR"
			cp -R "$APPDIR" "$INSTALLER_STAGE_DIR/core"
			
			# Build and sign setup.exe
			"`cygpath -u \"${NSIS_DIR}makensis.exe\"`" /V1 "`cygpath -w \"$BUILD_DIR/win_installer/installer.nsi\"`"
			mv "$BUILD_DIR/win_installer/setup.exe" "$INSTALLER_STAGE_DIR"
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC Setup" \
					/du "$SIGNATURE_URL" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
					/td SHA256 \
					"`cygpath -w \"$INSTALLER_STAGE_DIR/setup.exe\"`"
				sleep $SIGNTOOL_DELAY
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
				"`cygpath -u \"$SIGNTOOL\"`" \
					sign /n "$SIGNTOOL_CERT_SUBJECT" \
					/d "$SIGNATURE_DESC Setup" \
					/du "$SIGNATURE_URL" \
					/fd SHA256 \
					/tr "$SIGNTOOL_TIMESTAMP_SERVER" \
                                        /td SHA256 \
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
		cp -r "$RUNTIME_PATH/"!(application.ini|browser|defaults|devtools-files|crashreporter|crashreporter.ini|firefox|pingsender|precomplete|removed-files|run-mozilla.sh|update-settings.ini|updater|updater.ini) "$APPDIR"
		
		# Use our own launcher that calls the original Firefox executable with -app
		mv "$APPDIR"/firefox-bin "$APPDIR"/zotero-bin
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
		
		# Copy app files
		rsync -a "$base_dir/" "$APPDIR/"
		
		# Add devtools
		#if [ $DEVTOOLS -eq 1 ]; then
		#	# Create devtools.jar
		#	cd "$BUILD_DIR"
		#	mkdir -p devtools/locale
		#	cp -r "$RUNTIME_PATH"/devtools-files/chrome/devtools/* devtools/
		#	cp -r "$RUNTIME_PATH"/devtools-files/chrome/locale/* devtools/locale/
		#	cd devtools
		#	zip -r -q ../devtools.jar *
		#	cd ..
		#	rm -rf devtools
		#	mv devtools.jar "$APPDIR"
		#	
		#	cp "$RUNTIME_PATH/devtools-files/components/interfaces.xpt" "$APPDIR/components/"
		#fi
		
		# Add word processor plug-ins
		mkdir "$APPDIR/extensions"
		cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
		perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
		echo
		echo -n "zoteroOpenOfficeIntegration@zotero.org Version: "
		perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
		echo
		rm -rf "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/.git" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/.github"
		# Default preferenes are no longer read from built-in extensions in Firefox 60
		#echo >> "$APPDIR/defaults/preferences/prefs.js"
		#cat "$CALLDIR/modules/zotero-libreoffice-integration/defaults/preferences/zoteroOpenOfficeIntegration.js" >> "$APPDIR/defaults/preferences/prefs.js"
		#echo >> "$APPDIR/defaults/preferences/prefs.js"
		
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
