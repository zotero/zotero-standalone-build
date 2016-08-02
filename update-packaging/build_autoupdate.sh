#!/bin/bash -e
CALLDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function usage {
	cat >&2 <<DONE
Usage: $0 -f [-i FROM_VERSION] VERSION
Options
 -f                  Perform full build
 -i FROM             Perform incremental build
 -s S3_PATH          Path within S3 standalone directory (e.g., 'beta' for /standalone/beta)
 -p PLATFORM         Platforms to build (m=Mac, w=Windows, l=Linux)
 -l                  Use local TO directory instead of downloading TO files from S3
DONE
	exit 1
}

BUILD_FULL=0
BUILD_INCREMENTAL=0
FROM=""
BUILD_MAC=0
BUILD_WIN32=0
BUILD_LINUX=0
S3_PATH=""
USE_LOCAL_TO=0
while getopts "i:s:p:fl" opt; do
	case $opt in
		i)
			FROM="$OPTARG"
			BUILD_INCREMENTAL=1
			;;
		s)
			S3_PATH="$OPTARG"
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
		f)
			BUILD_FULL=1
			;;
		l)
			USE_LOCAL_TO=1
			;;
		*)
			usage
			;;
	esac
	shift $((OPTIND-1)); OPTIND=1
done

shift $(($OPTIND - 1))
TO=$1

if [ -z "$TO" ]; then
	usage
fi

if [ -z "$FROM" ] && [ $BUILD_FULL -eq 0 ]; then
	usage
fi

# Require at least one platform
if [[ $BUILD_MAC == 0 ]] && [[ $BUILD_WIN32 == 0 ]] && [[ $BUILD_LINUX == 0 ]]; then
	usage
fi

DISTDIR=$CALLDIR/../dist
STAGEDIR=$CALLDIR/staging

for version in "$FROM" "$TO"; do
	echo "Getting Zotero version $version"
	echo
	if [ -z "$version" ]; then
		continue
	fi
	
	versiondir="$STAGEDIR/$version"
	
	if [ -d "$versiondir" ]; then
		if [ -h "$versiondir" ]; then
			rm "$versiondir"
		fi
	fi
	
	#
	# Use main build script's staging directory for TO files rather than downloading the given version.
	#
	# The caller must ensure that the files in ../staging match the version given.
	if [[ $version == $TO && $USE_LOCAL_TO == "1" ]]; then
		if [ ! -d "$CALLDIR/../staging" ]; then
			echo "Can't find local TO dir $CALLDIR/../staging"
			exit 1
		fi
		
		echo "Using files from $CALLDIR/../staging"
		ln -s $CALLDIR/../staging "$versiondir"
		continue
	fi
	
	#
	# Otherwise, download version from S3
	#
	mkdir -p "$versiondir"
	cd "$versiondir"
	
	MAC_ARCHIVE="Zotero-${version}.dmg"
	WIN_ARCHIVE="Zotero-${version}_win32.zip"
	LINUX_X86_ARCHIVE="Zotero-${version}_linux-i686.tar.bz2"
	LINUX_X86_64_ARCHIVE="Zotero-${version}_linux-x86_64.tar.bz2"
	
	for archive in "$MAC_ARCHIVE" "$WIN_ARCHIVE" "$LINUX_X86_ARCHIVE" "$LINUX_X86_64_ARCHIVE"; do
		if [[ $archive = "$MAC_ARCHIVE" ]] && [[ $BUILD_MAC != 1 ]]; then
			continue
		fi
		if [[ $archive = "$WIN_ARCHIVE" ]] && [[ $BUILD_WIN != 1 ]]; then
			continue
		fi
		if [[ $archive = "$LINUX_X86_ARCHIVE" ]] && [[ $BUILD_LINUX != 1 ]]; then
			continue
		fi
		if [[ $archive = "$LINUX_X86_64_ARCHIVE" ]] && [[ $BUILD_LINUX != 1 ]]; then
			continue
		fi
		
		rm -f $archive
		ENCODED_VERSION=`python -c 'import urllib2; print urllib2.quote("'$version'")'`
		ENCODED_ARCHIVE=`python -c 'import urllib2; print urllib2.quote("'$archive'")'`
		URL="https://zotero-download.s3.amazonaws.com/standalone/$S3_PATH/$ENCODED_VERSION/$ENCODED_ARCHIVE"
		echo "Fetching $URL"
		wget -nv $URL
	done
	
	# Unpack Zotero.app
	if [ $BUILD_MAC == 1 ]; then
		set +e
		hdiutil detach -quiet /Volumes/Zotero 2>/dev/null
		set -e
		hdiutil attach -quiet "$MAC_ARCHIVE"
		cp -R /Volumes/Zotero/Zotero.app "$versiondir"
		rm "$MAC_ARCHIVE"
		hdiutil detach -quiet /Volumes/Zotero
	fi
	
	# Unpack Win32 zip
	if [ $BUILD_WIN32 == 1 ]; then
		unzip -q "$WIN_ARCHIVE"
		rm "$WIN_ARCHIVE"
	fi
	
	# Unpack Linux tarballs
	if [ $BUILD_LINUX == 1 ]; then
		for build in "$LINUX_X86_ARCHIVE" "$LINUX_X86_64_ARCHIVE"; do
			tar -xjf "$build"
			rm "$build"
		done
	fi
	
	echo
done

for build in "mac" "win32" "linux-i686" "linux-x86_64"; do
	if [[ $build == "mac" ]]; then
		if [[ $BUILD_MAC == 0 ]]; then
			continue
		fi
		dir="Zotero.app"
	else
		if [[ $build == "win32" ]] && [[ $BUILD_WIN32 == 0 ]]; then
			continue
		fi
		if [[ $build == "linux-i686" ]] || [[ $build == "linux-x86_64" ]] && [[ $BUILD_LINUX == 0 ]]; then
			continue
		fi
		dir="Zotero_$build"
		touch "$STAGEDIR/$TO/$dir/precomplete"
		cp "$CALLDIR/removed-files_$build" "$STAGEDIR/$TO/$dir/removed-files"
	fi
	if [[ $BUILD_INCREMENTAL == 1 ]]; then
		echo
		echo "Building incremental update from $FROM to $TO"
		"$CALLDIR/make_incremental_update.sh" "$DISTDIR/Zotero-${TO}-${FROM}_$build.mar" "$STAGEDIR/$FROM/$dir" "$STAGEDIR/$TO/$dir"
	fi
	if [[ $BUILD_FULL == 1 ]]; then
		echo
		echo "Building full update for $TO"
		"$CALLDIR/make_full_update.sh" "$DISTDIR/Zotero-${TO}-full_$build.mar" "$STAGEDIR/$TO/$dir"
	fi
done

cd "$DISTDIR"
shasum -a 512 * > sha512sums
ls -lan > files

echo
cat sha512sums
echo
cat files
