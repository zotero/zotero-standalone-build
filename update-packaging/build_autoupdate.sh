#!/bin/bash
FROM=2.1a3
TO=3.0b1
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
	for archive in "Zotero.dmg" "Zotero_win32.zip" "Zotero_linux-i686.tar.bz2" "Zotero_linux-x86_64.tar.bz2"; do
		rm -f $archive
		wget -nv http://www.zotero.org/download/standalone/$version/$archive
	done
	
	# Unpack Zotero.app
	hdiutil detach -quiet /Volumes/Zotero 2>/dev/null
	hdiutil attach -quiet Zotero.dmg
	cp -R /Volumes/Zotero/Zotero.app $versiondir
	rm Zotero.dmg
	hdiutil detach -quiet /Volumes/Zotero
	
	# Unpack Win32 zip
	unzip -q Zotero_win32.zip
	rm Zotero_win32.zip
	
	# Unpack Linux tarballs
	for build in "Zotero_linux-i686" "Zotero_linux-x86_64"; do
		tar -xjf $build.tar.bz2
		rm $build.tar.bz2
	done
done

for build in "mac" "win32" "linux-i686" "linux-x86_64"; do
	if [[ $build == "mac" ]]; then
		dir="Zotero.app"
	else
		dir="Zotero_$build"
	fi
	$CALLDIR/make_incremental_update.sh $DISTDIR/Zotero-${TO}-${FROM}_$build.mar $STAGEDIR/$FROM/$dir $STAGEDIR/$TO/$dir
	$CALLDIR/make_full_update.sh $DISTDIR/Zotero-${TO}-full_$build.mar $STAGEDIR/$TO/$dir
done
