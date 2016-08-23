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

PROTOCOL="https"
CALLDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CALLDIR/config.sh"
SITE="$PROTOCOL://ftp.mozilla.org/pub/mozilla.org/xulrunner/releases/$GECKO_VERSION/runtimes/"

function usage {
	cat >&2 <<DONE
Usage: $0 -p platforms
Options
 -p PLATFORMS        Platforms to build (m=Mac, w=Windows, l=Linux)
DONE
	exit 1
}

BUILD_MAC=0
BUILD_WIN32=0
BUILD_LINUX=0
while getopts "p:" opt; do
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

# Modify AddonConstants.jsm in omni.ja to allow unsigned add-ons
#
# Theoretically there should be other ways of doing this without modifying omni.ja
# (e.g., an 'override' statement in chrome.manifest, a enterprise config.js file that clears
# SIGNED_TYPES in XPIProvider.jsm), but I couldn't get them to work.
function modify_omni {
	mkdir omni
	mv omni.ja omni
	cd omni
	# omni.ja is an "optimized" ZIP file, so use a script from Mozilla to avoid a warning from unzip
	# here and to make it work after rezipping below
	python "$CALLDIR/scripts/optimizejars.py" --deoptimize ./ ./ ./
	unzip omni.ja
	rm omni.ja
	perl -pi -e 's/value: true/value: false/' modules/addons/AddonConstants.jsm
	# Delete binary version of file
	rm jsloader/resource/gre/modules/addons/AddonConstants.jsm
	zip -qr9XD omni.ja *
	mv omni.ja ..
	cd ..
	python "$CALLDIR/scripts/optimizejars.py" --optimize ./ ./ ./
	rm -rf omni
}

rm -rf xulrunner
mkdir xulrunner
cd xulrunner

if [ $BUILD_MAC == 1 ]; then
	curl -O "$PROTOCOL://ftp.mozilla.org/pub/mozilla.org/firefox/releases/$GECKO_VERSION/mac/en-US/Firefox%20$GECKO_VERSION.dmg"
	set +e
	hdiutil detach -quiet /Volumes/Firefox 2>/dev/null
	set -e
	hdiutil attach -quiet "Firefox%20$GECKO_VERSION.dmg"
	cp -a /Volumes/Firefox/Firefox.app .
	hdiutil detach -quiet /Volumes/Firefox
	
	pushd Firefox.app/Contents/Resources
	modify_omni
	popd
	
	rm "Firefox%20$GECKO_VERSION.dmg"
fi

if [ $BUILD_WIN32 == 1 ]; then
	curl -O $SITE/xulrunner-$GECKO_VERSION.en-US.win32.zip
	
	unzip -q xulrunner-$GECKO_VERSION.en-US.win32.zip
	rm xulrunner-$GECKO_VERSION.en-US.win32.zip
	mv xulrunner xulrunner_win32

	# Extract XUL bundle from Firefox
	curl -O "$PROTOCOL://ftp.mozilla.org/pub/mozilla.org/firefox/releases/$GECKO_VERSION/win32/en-US/Firefox%20Setup%20$GECKO_VERSION.exe"
	if which 7z >/dev/null 2>&1; then
		Z7=7z
	elif [ -x "$EXE7ZIP" ]; then
		Z7="`cygpath -u "$EXE7ZIP"`"
	fi
	cd xulrunner_win32
	rm *.dll *.chk
	"$Z7" e "../Firefox%20Setup%20$GECKO_VERSION.exe" core/*.dll core/*.chk
	cd ..
	rm "Firefox%20Setup%20$GECKO_VERSION.exe"
fi

if [ $BUILD_LINUX == 1 ]; then
	rm -rf firefox
	
	curl -O "https://ftp.mozilla.org/pub/firefox/releases/$GECKO_VERSION/linux-i686/en-US/firefox-$GECKO_VERSION.tar.bz2"
	rm -rf firefox-i686
	tar xvf firefox-$GECKO_VERSION.tar.bz2
	mv firefox firefox-i686
	cd firefox-i686
	modify_omni
	cd ..
	rm "firefox-$GECKO_VERSION.tar.bz2"
	
	curl -O "https://ftp.mozilla.org/pub/firefox/releases/$GECKO_VERSION/linux-x86_64/en-US/firefox-$GECKO_VERSION.tar.bz2"
	rm -rf firefox-x86_64
	tar xvf firefox-$GECKO_VERSION.tar.bz2
	mv firefox firefox-x86_64
	cd firefox-x86_64
	modify_omni
	cd ..
	rm "firefox-$GECKO_VERSION.tar.bz2"
fi