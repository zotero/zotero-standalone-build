#!/bin/bash
set -euo pipefail

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

function usage {
	cat >&2 <<DONE
Usage: $0 -p platforms [-s]
Options
 -p PLATFORMS        Platforms to build (m=Mac, w=Windows, l=Linux)
 -s                  Skip download; Firefox must already be extracted in xulrunner/ directory
DONE
	exit 1
}

BUILD_MAC=0
BUILD_WIN32=0
BUILD_LINUX=0
skip_download=0
while getopts "p:s" opt; do
	case $opt in
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
		
		s)
			skip_download=1
			;;
	esac
	shift $((OPTIND-1)); OPTIND=1
done

# Require at least one platform
if [[ $BUILD_MAC == 0 ]] && [[ $BUILD_WIN32 == 0 ]] && [[ $BUILD_LINUX == 0 ]]; then
	usage
fi

#
# Make various modifications to omni.ja
#
function modify_omni {
	local platform=$1
	
	mkdir omni
	mv omni.ja omni
	cd omni
	# omni.ja is an "optimized" ZIP file, so use a script from Mozilla to avoid a warning from unzip
	# here and to make it work after rezipping below
	python2.7 "$CALLDIR/scripts/optimizejars.py" --deoptimize ./ ./ ./
	unzip omni.ja
	rm omni.ja
	
	# Modify various constants (e.g., to allow unsigned add-ons)
	if [ -f modules/addons/AddonConstants.jsm ]; then
		perl -pi -e 's/value: true/value: false/' modules/addons/AddonConstants.jsm
		# Delete binary version of file
		rm -f jsloader/resource/gre/modules/addons/AddonConstants.jsm
	else
		perl -pi -e 's/MOZ_REQUIRE_SIGNING:/MOZ_REQUIRE_SIGNING: false \&\&/' modules/AppConstants.jsm
		perl -pi -e 's/MOZ_ALLOW_LEGACY_EXTENSIONS:/MOZ_ALLOW_LEGACY_EXTENSIONS: true, _: /' modules/AppConstants.jsm
		perl -pi -e 's/MOZ_DATA_REPORTING:/MOZ_DATA_REPORTING: false \&\&/' modules/AppConstants.jsm
		perl -pi -e 's/MOZ_TELEMETRY_REPORTING:/MOZ_TELEMETRY_REPORTING: false \&\&/' modules/AppConstants.jsm
		perl -pi -e 's/MOZ_TELEMETRY_ON_BY_DEFAULT:/MOZ_TELEMETRY_ON_BY_DEFAULT: false \&\&/' modules/AppConstants.jsm
		perl -pi -e 's/MOZ_CRASHREPORTER:/MOZ_CRASHREPORTER: false \&\&/' modules/AppConstants.jsm
		# Delete binary version of file
		rm -f jsloader/resource/gre/modules/AppConstants.jsm
	fi
	
	# Update URL for built-in add-ons list
	echo '{"system": []}' > modules/addons/built_in_addons.json
	perl -pi -e 's/const BUILT_IN_ADDONS_URI.+/const BUILT_IN_ADDONS_URI = "resource:\/\/gre\/modules\/addons\/built_in_addons.json";/' modules/addons/XPIProvider.jsm
	
	# Disable transaction timeout
	perl -pi -e 's/let timeoutPromise/\/*let timeoutPromise/' modules/Sqlite.jsm
	perl -pi -e 's/return Promise.race\(\[transactionPromise, timeoutPromise\]\);/*\/return transactionPromise;/' modules/Sqlite.jsm
	rm -f jsloader/resource/gre/modules/Sqlite.jsm
	
	# Disable unwanted components
	cat components/components.manifest | grep -vi telemetry > components/components2.manifest
	mv components/components2.manifest components/components.manifest
	
	# Allow proxy password saving
	perl -pi -e 's/get _inPrivateBrowsing\(\) {/get _inPrivateBrowsing() {if (true) { return false; }/' components/nsLoginManagerPrompter.js
	
	# Change text in update dialog
	perl -pi -e 's/A security and stability update for/A new version of/' chrome/en-US/locale/en-US/mozapps/update/updates.properties
	perl -pi -e 's/updateType_major=New Version/updateType_major=New Major Version/' chrome/en-US/locale/en-US/mozapps/update/updates.properties
	perl -pi -e 's/updateType_minor=Security Update/updateType_minor=New Version/' chrome/en-US/locale/en-US/mozapps/update/updates.properties
	perl -pi -e 's/update for &brandShortName; as soon as possible/update as soon as possible/' chrome/en-US/locale/en-US/mozapps/update/updates.dtd
	
	# Set available locales
	cp "$CALLDIR/assets/multilocale.txt" res/multilocale.txt
	
	# Force Lucida Grande on non-Retina displays, since San Francisco is used otherwise starting in
	# Catalina, and it looks terrible
	if [[ $platform == 'mac' ]]; then
		echo "* { font-family: Lucida Grande, Lucida Sans Unicode, Lucida Sans, Geneva, -apple-system, sans-serif !important; }" >> chrome/toolkit/skin/classic/global/global.css
	fi
	
	# Modify Add-ons window
	echo >> chrome/toolkit/content/mozapps/extensions/extensions.css
	echo '#category-theme { display: none; }' >> chrome/toolkit/content/mozapps/extensions/extensions.css
	echo '#category-plugin { display: none; }' >> chrome/toolkit/content/mozapps/extensions/extensions.css
	# Hide add-on warning in list view unless explicitly allowed (in standalone.js)
	echo '.addon > .warning:not(.allowed-warning) image { display: none; }' >> chrome/toolkit/content/mozapps/extensions/extensions.css
	echo '.addon > .warning:not(.allowed-warning) label[anonid="warning"] { display: none; }' >> chrome/toolkit/content/mozapps/extensions/extensions.css
	# Always hide add-on warning text link, since it would go to Mozilla
	echo '.addon > .warning .text-link { display: none; }' >> chrome/toolkit/content/mozapps/extensions/extensions.css
	# Always hide add-on warning in detail view
	echo '.detail-view-container #warning-container { display: none; }' >> chrome/toolkit/content/mozapps/extensions/extensions.css
	# Hide legacy label
	echo '.legacy-warning { display: none; }' >> chrome/toolkit/content/mozapps/extensions/extensions.css
	
	zip -qr9XD omni.ja *
	mv omni.ja ..
	cd ..
	python2.7 "$CALLDIR/scripts/optimizejars.py" --optimize ./ ./ ./
	rm -rf omni
}

# Add devtools server from browser omni.ja
function extract_devtools {
	set +e
	unzip browser/omni.ja 'chrome/devtools/*' -d devtools-files
	unzip browser/omni.ja 'chrome/en-US/locale/en-US/devtools/*' -d devtools-files
	mv devtools-files/chrome/en-US/locale devtools-files/chrome
	rmdir devtools-files/chrome/en-US
	unzip browser/omni.ja 'components/interfaces.xpt' -d devtools-files
	set -e
}

mkdir -p xulrunner
cd xulrunner

if [ $BUILD_MAC == 1 ]; then
	GECKO_VERSION="$GECKO_VERSION_MAC"
	DOWNLOAD_URL="https://ftp.mozilla.org/pub/firefox/releases/$GECKO_VERSION"
	if [ $skip_download -eq 0 ]; then
		rm -rf Firefox.app
		
		if [ -e "Firefox-Modified-$GECKO_VERSION.dmg" ]; then
			echo "Using Firefox-Modified-$GECKO_VERSION.dmg"
			cp "Firefox-Modified-$GECKO_VERSION.dmg" "Firefox%20$GECKO_VERSION.dmg"
		else
			curl -O "$DOWNLOAD_URL/mac/en-US/Firefox%20$GECKO_VERSION.dmg"
		fi
		
		set +e
		hdiutil detach -quiet /Volumes/Firefox 2>/dev/null
		set -e
		hdiutil attach -quiet "Firefox%20$GECKO_VERSION.dmg"
		cp -a /Volumes/Firefox/Firefox.app .
		hdiutil detach -quiet /Volumes/Firefox
	fi
	
	pushd Firefox.app/Contents/Resources
	modify_omni mac
	extract_devtools
	popd
	
	if [ $skip_download -eq 0 ]; then
		rm "Firefox%20$GECKO_VERSION.dmg"
	fi
fi

if [ $BUILD_WIN32 == 1 ]; then
	GECKO_VERSION="$GECKO_VERSION_WIN"
	DOWNLOAD_URL="https://ftp.mozilla.org/pub/firefox/releases/$GECKO_VERSION"
	
	XDIR=firefox-win32
	
	if [ $skip_download -eq 0 ]; then
		rm -rf $XDIR
		mkdir $XDIR
		
		curl -O "$DOWNLOAD_URL/win32/en-US/Firefox%20Setup%20$GECKO_VERSION.exe"
		
		7z x Firefox%20Setup%20$GECKO_VERSION.exe -o$XDIR 'core/*'
		mv $XDIR/core $XDIR-core
		rm -rf $XDIR
		mv $XDIR-core $XDIR
	fi
	
	cd $XDIR
	modify_omni win32
	extract_devtools
	cd ..
	
	if [ $skip_download -eq 0 ]; then
		rm "Firefox%20Setup%20$GECKO_VERSION.exe"
	fi
fi

if [ $BUILD_LINUX == 1 ]; then
	GECKO_VERSION="$GECKO_VERSION_LINUX"
	DOWNLOAD_URL="https://ftp.mozilla.org/pub/firefox/releases/$GECKO_VERSION"
	
	if [ $skip_download -eq 0 ]; then
		rm -rf firefox
		
		curl -O "$DOWNLOAD_URL/linux-i686/en-US/firefox-$GECKO_VERSION.tar.bz2"
		rm -rf firefox-i686
		tar xvf firefox-$GECKO_VERSION.tar.bz2
		mv firefox firefox-i686
	fi
	
	cd firefox-i686
	modify_omni linux32
	extract_devtools
	cd ..
	
	if [ $skip_download -eq 0 ]; then
		rm "firefox-$GECKO_VERSION.tar.bz2"
		
		curl -O "$DOWNLOAD_URL/linux-x86_64/en-US/firefox-$GECKO_VERSION.tar.bz2"
		rm -rf firefox-x86_64
		tar xvf firefox-$GECKO_VERSION.tar.bz2
		mv firefox firefox-x86_64
	fi
	
	cd firefox-x86_64
	modify_omni linux64
	extract_devtools
	cd ..
	
	if [ $skip_download -eq 0 ]; then
		rm "firefox-$GECKO_VERSION.tar.bz2"
	fi
fi

echo Done