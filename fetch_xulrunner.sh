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
DONE
	exit 1
}

BUILD_MAC=0
BUILD_WIN32=0
BUILD_LINUX=0
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
	esac
	shift $((OPTIND-1)); OPTIND=1
done

# Require at least one platform
if [[ $BUILD_MAC == 0 ]] && [[ $BUILD_WIN32 == 0 ]] && [[ $BUILD_LINUX == 0 ]]; then
	usage
fi

#
# Make various modifications to the stock Firefox app
#
function modify_omni {
	local platform=$1
	
	mkdir omni
	mv omni.ja omni
	cd omni
	# omni.ja is an "optimized" ZIP file, so use a script from Mozilla to avoid a warning from unzip
	# here and to make it work after rezipping below
	python3 "$CALLDIR/scripts/optimizejars.py" --deoptimize ./ ./ ./
	rm -f omni.ja.log
	unzip omni.ja
	rm omni.ja
	
	perl -pi -e 's/BROWSER_CHROME_URL:.+/BROWSER_CHROME_URL: "chrome:\/\/zotero\/content\/zoteroPane.xhtml",/' modules/AppConstants.jsm
	
	# https://firefox-source-docs.mozilla.org/toolkit/components/telemetry/internals/preferences.html
	#
	# It's not clear that most of these do anything anymore when not compiled in, but just in case
	perl -pi -e 's/MOZ_REQUIRE_SIGNING:/MOZ_REQUIRE_SIGNING: false \&\&/' modules/AppConstants.jsm
	perl -pi -e 's/MOZ_DATA_REPORTING:/MOZ_DATA_REPORTING: false \&\&/' modules/AppConstants.jsm
	perl -pi -e 's/MOZ_SERVICES_HEALTHREPORT:/MOZ_SERVICES_HEALTHREPORT: false \&\&/' modules/AppConstants.jsm
	perl -pi -e 's/MOZ_TELEMETRY_REPORTING:/MOZ_TELEMETRY_REPORTING: false \&\&/' modules/AppConstants.jsm
	perl -pi -e 's/MOZ_TELEMETRY_ON_BY_DEFAULT:/MOZ_TELEMETRY_ON_BY_DEFAULT: false \&\&/' modules/AppConstants.jsm
	perl -pi -e 's/MOZ_CRASHREPORTER:/MOZ_CRASHREPORTER: false \&\&/' modules/AppConstants.jsm
	perl -pi -e 's/MOZ_UPDATE_CHANNEL:.+/MOZ_UPDATE_CHANNEL: "none",/' modules/AppConstants.jsm
	perl -pi -e 's/"https:\/\/[^\/]+mozilla.com.+"/""/' modules/AppConstants.jsm
	
	perl -pi -e 's/pref\("network.captive-portal-service.enabled".+/pref("network.captive-portal-service.enabled", false);/' greprefs.js
	perl -pi -e 's/pref\("network.connectivity-service.enabled".+/pref("network.connectivity-service.enabled", false);/' greprefs.js
	perl -pi -e 's/pref\("toolkit.telemetry.server".+/pref("toolkit.telemetry.server", "");/' greprefs.js
	perl -pi -e 's/pref\("toolkit.telemetry.unified".+/pref("toolkit.telemetry.unified", false);/' greprefs.js
	
	#  
	#  # Disable transaction timeout
	#  perl -pi -e 's/let timeoutPromise/\/*let timeoutPromise/' modules/Sqlite.jsm
	#  perl -pi -e 's/return Promise.race\(\[transactionPromise, timeoutPromise\]\);/*\/return transactionPromise;/' modules/Sqlite.jsm
	#  rm -f jsloader/resource/gre/modules/Sqlite.jsm
	#  
	# Disable unwanted components
	cat components/components.manifest | egrep -vi '(RemoteSettings|services-|telemetry|URLDecorationAnnotationsService)' > components/components2.manifest
	mv components/components2.manifest components/components.manifest
	
	# Remove unwanted files
	rm modules/FxAccounts*
	# Causes a startup error -- try an empty file or a shim instead?
	#rm modules/Telemetry*
	rm modules/URLDecorationAnnotationsService.jsm
	rm -rf modules/services-*
	
	# Clear most WebExtension manifest properties
	if ! grep -qE 'manifest = normalized.value' modules/Extension.jsm; then echo "'manifest = normalized.value' not found"; exit 1; fi
	perl -pi -e 's/manifest = normalized.value;/manifest = normalized.value;
    if (this.type == "extension") {
      if (!manifest.applications?.gecko?.id
          || !manifest.applications?.gecko?.update_url) {
        return null;
      }
      manifest.browser_specific_settings = [];
      manifest.content_scripts = [];
      manifest.permissions = [];
      manifest.host_permissions = [];
      manifest.web_accessible_resources = undefined;
      manifest.experiment_apis = {};
    }/' modules/Extension.jsm
    
	# No idea why this is necessary, but without it initialization fails with "TypeError: "constructor" is read-only"
	perl -pi -e 's/LoginStore.prototype.constructor = LoginStore;/\/\/LoginStore.prototype.constructor = LoginStore;/' modules/LoginStore.jsm
	#  
	#  # Allow proxy password saving
	#  perl -pi -e 's/get _inPrivateBrowsing\(\) \{/get _inPrivateBrowsing() {if (true) { return false; }/' components/nsLoginManagerPrompter.js
	#  
	#  # Change text in update dialog
	#  perl -pi -e 's/A security and stability update for/A new version of/' chrome/en-US/locale/en-US/mozapps/update/updates.properties
	#  perl -pi -e 's/updateType_major=New Version/updateType_major=New Major Version/' chrome/en-US/locale/en-US/mozapps/update/updates.properties
	#  perl -pi -e 's/updateType_minor=Security Update/updateType_minor=New Version/' chrome/en-US/locale/en-US/mozapps/update/updates.properties
	#  perl -pi -e 's/update for &brandShortName; as soon as possible/update as soon as possible/' chrome/en-US/locale/en-US/mozapps/update/updates.dtd
	#  
	# Set available locales
	cp "$CALLDIR/assets/multilocale.txt" res/multilocale.txt
	#  
	#  # Force Lucida Grande on non-Retina displays, since San Francisco is used otherwise starting in
	#  # Catalina, and it looks terrible
	#  if [[ $platform == 'mac' ]]; then
	#  	echo "* { font-family: Lucida Grande, Lucida Sans Unicode, Lucida Sans, Geneva, -apple-system, sans-serif !important; }" >> chrome/toolkit/skin/classic/global/global.css
	#  fi
	
	#
	# Modify Add-ons window
	#
	file="chrome/toolkit/content/mozapps/extensions/aboutaddons.css"
	echo >> $file
	# Hide search bar, Themes and Plugins tabs, and sidebar footer
	echo '.main-search, button[name="theme"], button[name="plugin"], sidebar-footer { display: none; }' >> $file
	echo '.main-heading { margin-top: 2em; }' >> $file
	# Hide Details/Permissions tabs in addon details so we only show details
	echo 'addon-details > button-group { display: none !important; }' >> $file
	# Hide "Debug Addons" and "Manage Extension Shortcuts"
	echo 'panel-item[action="debug-addons"], panel-item[action="reset-update-states"] + panel-item-separator, panel-item[action="manage-shortcuts"] { display: none }' >> $file
	
	file="chrome/toolkit/content/mozapps/extensions/aboutaddons.js"
	# Hide unsigned-addon warning
	perl -pi -e 's/if \(!isCorrectlySigned\(addon\)\) \{/if (!isCorrectlySigned(addon)) {return {};/' $file
	# Hide Private Browsing setting in addon details
	perl -pi -e 's/pbRow\./\/\/pbRow./' $file
	perl -pi -e 's/let isAllowed = await isAllowedInPrivateBrowsing/\/\/let isAllowed = await isAllowedInPrivateBrowsing/' $file
	# Use our own strings for the removal prompt
	perl -pi -e 's/let \{ BrowserAddonUI \} = windowRoot.ownerGlobal;//' $file
	perl -pi -e 's/await BrowserAddonUI.promptRemoveExtension/promptRemoveExtension/' $file
	
	# Hide Recommendations tab in sidebar and recommendations in main pane
	perl -pi -e 's/function isDiscoverEnabled\(\) \{/function isDiscoverEnabled() {return false;/' chrome/toolkit/content/mozapps/extensions/aboutaddonsCommon.js
	perl -pi -e 's/pref\("extensions.htmlaboutaddons.recommendations.enabled".+/pref("extensions.htmlaboutaddons.recommendations.enabled", false);/' greprefs.js
	
	# Hide Report option
	perl -pi -e 's/pref\("extensions.abuseReport.enabled".+/pref("extensions.abuseReport.enabled", false);/' greprefs.js
	
	zip -qr9XD omni.ja *
	mv omni.ja ..
	cd ..
	python3 "$CALLDIR/scripts/optimizejars.py" --optimize ./ ./ ./
	rm -rf omni
	
	# Unzip browser/omni.ja and leave unzipped
	cd browser
	mkdir omni
	mv omni.ja omni
	cd omni
	ls -la
	set +e
	unzip omni.ja
	set -e
	rm omni.ja
	
	# Remove Firefox overrides (e.g., to use Firefox-specific strings for connection errors)
	egrep -v '(override)' chrome/chrome.manifest > chrome/chrome.manifest2
	mv chrome/chrome.manifest2 chrome/chrome.manifest
	
	# Remove WebExtension APIs
	egrep -v ext-browser.json components/components.manifest > components/components.manifest2
	mv components/components.manifest2 components/components.manifest
}

mkdir -p xulrunner
cd xulrunner

if [ $BUILD_MAC == 1 ]; then
	GECKO_VERSION="$GECKO_VERSION_MAC"
	DOWNLOAD_URL="https://ftp.mozilla.org/pub/firefox/releases/$GECKO_VERSION"
	rm -rf Firefox.app
	
	if [ -e "Firefox $GECKO_VERSION.app.zip" ]; then
		echo "Using Firefox $GECKO_VERSION.app.zip"
		unzip "Firefox $GECKO_VERSION.app.zip"
	else
		curl -o Firefox.dmg "$DOWNLOAD_URL/mac/en-US/Firefox%20$GECKO_VERSION.dmg"
		set +e
		hdiutil detach -quiet /Volumes/Firefox 2>/dev/null
		set -e
		hdiutil attach -quiet Firefox.dmg
		cp -a /Volumes/Firefox/Firefox.app .
		hdiutil detach -quiet /Volumes/Firefox
	fi
	
	# Download custom components
	#echo
	#rm -rf MacOS
	#if [ -e "Firefox $GECKO_VERSION MacOS.zip" ]; then
	#	echo "Using Firefox $GECKO_VERSION MacOS.zip"
	#	unzip "Firefox $GECKO_VERSION MacOS.zip"
	#else
	#	echo "Downloading Firefox $GECKO_VERSION MacOS.zip"
	#	curl -o MacOS.zip "${custom_components_url}Firefox%20$GECKO_VERSION%20MacOS.zip"
	#	unzip MacOS.zip
	#fi
	#echo
	
	pushd Firefox.app/Contents/Resources
	modify_omni mac
	popd
	
	if [ ! -e "Firefox $GECKO_VERSION.app.zip" ]; then
		rm "Firefox.dmg"
	fi
	
	#if [ ! -e "Firefox $GECKO_VERSION MacOS.zip" ]; then
	#	rm "MacOS.zip"
	#fi
fi

if [ $BUILD_WIN32 == 1 ]; then
	GECKO_VERSION="$GECKO_VERSION_WIN"
	DOWNLOAD_URL="https://ftp.mozilla.org/pub/firefox/releases/$GECKO_VERSION"
	
	XDIR=firefox-win32
	
	rm -rf $XDIR
	mkdir $XDIR
	
	curl -O "$DOWNLOAD_URL/win32/en-US/Firefox%20Setup%20$GECKO_VERSION.exe"
	
	7z x Firefox%20Setup%20$GECKO_VERSION.exe -o$XDIR 'core/*'
	mv $XDIR/core $XDIR-core
	rm -rf $XDIR
	mv $XDIR-core $XDIR
	
	cd $XDIR
	modify_omni win32
	cd ..
	
	rm "Firefox%20Setup%20$GECKO_VERSION.exe"
fi

if [ $BUILD_LINUX == 1 ]; then
	GECKO_VERSION="$GECKO_VERSION_LINUX"
	DOWNLOAD_URL="https://ftp.mozilla.org/pub/firefox/releases/$GECKO_VERSION"
	
	rm -rf firefox
	
	curl -O "$DOWNLOAD_URL/linux-i686/en-US/firefox-$GECKO_VERSION.tar.bz2"
	rm -rf firefox-i686
	tar xvf firefox-$GECKO_VERSION.tar.bz2
	mv firefox firefox-i686
	
	pushd firefox-i686
	modify_omni linux32
	popd
	
	rm "firefox-$GECKO_VERSION.tar.bz2"
	
	curl -O "$DOWNLOAD_URL/linux-x86_64/en-US/firefox-$GECKO_VERSION.tar.bz2"
	rm -rf firefox-x86_64
	tar xvf firefox-$GECKO_VERSION.tar.bz2
	mv firefox firefox-x86_64
	
	pushd firefox-x86_64
	modify_omni linux64
	popd
	
	rm "firefox-$GECKO_VERSION.tar.bz2"
fi

echo Done
