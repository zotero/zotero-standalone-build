#!/bin/bash
FROM=4.0.23
TO=4.0.25.3
USE_LOCAL_TO=1
CALLDIR=`pwd`
DISTDIR=$CALLDIR/../dist
STAGEDIR=$CALLDIR/staging

for version in "$FROM" "$TO"; do
	versiondir=$STAGEDIR/$version
	
	if [ -d $versiondir ]; then
		continue
	fi
	
	if [[ $version == $TO && $USE_LOCAL_TO == "1" ]]; then
		ln -s $CALLDIR/../staging $versiondir
		continue
	fi
	
	echo "Getting Zotero $version..."
	mkdir -p $versiondir
	cd $versiondir
	
	# Download archives
	MAC_ARCHIVE="Zotero-${version}.dmg"
	WIN_ARCHIVE="Zotero-${version}_win32.zip"
	LINUX_X86_ARCHIVE="Zotero-${version}_linux-i686.tar.bz2"
	LINUX_X86_64_ARCHIVE="Zotero-${version}_linux-x86_64.tar.bz2"
	
	for archive in "$MAC_ARCHIVE" "$WIN_ARCHIVE" "$LINUX_X86_ARCHIVE" "$LINUX_X86_64_ARCHIVE"; do
		rm -f $archive
		wget -nv http://download.zotero.org/standalone/$version/$archive
	done
	
	# Unpack Zotero.app
	hdiutil detach -quiet /Volumes/Zotero 2>/dev/null
	hdiutil attach -quiet "$MAC_ARCHIVE"
	cp -R /Volumes/Zotero/Zotero.app $versiondir
	rm "$MAC_ARCHIVE"
	hdiutil detach -quiet /Volumes/Zotero
	
	# Unpack Win32 zip
	unzip -q "$WIN_ARCHIVE"
	rm "$WIN_ARCHIVE"
	
	# Unpack Linux tarballs
	for build in "$LINUX_X86_ARCHIVE" "$LINUX_X86_64_ARCHIVE"; do
		tar -xjf "$build"
		rm "$build"
	done
done

for build in "mac" "win32" "linux-i686" "linux-x86_64"; do
	if [[ $build == "mac" ]]; then
		dir="Zotero.app"
	else
		dir="Zotero_$build"
		touch "$STAGEDIR/$TO/$dir/precomplete"
		cp "$CALLDIR/removed-files_$build" "$STAGEDIR/$TO/$dir/removed-files"
	fi
	"$CALLDIR/make_incremental_update.sh" "$DISTDIR/Zotero-${TO}-${FROM}_$build.mar" "$STAGEDIR/$FROM/$dir" "$STAGEDIR/$TO/$dir"
	"$CALLDIR/make_full_update.sh" "$DISTDIR/Zotero-${TO}-full_$build.mar" "$STAGEDIR/$TO/$dir"
done

cd "$DISTDIR"
shasum -a 512 * > sha512sums
ls -la > files