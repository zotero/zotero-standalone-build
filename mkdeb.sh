#!/bin/bash

set -x
set -e

# easier for Juris-M to fork and keep updated
DISTBASE=Zotero
PACKAGE=zotero

# just for testing
if [ ! -z "$1" ]; then
  for ZARCH in "i686" "x86_64"; do
    rm -rf ${DISTBASE}_linux-$ZARCH
    mkdir -p ${DISTBASE}_linux-$ZARCH
    tar -xf ${DISTBASE}_linux-$ZARCH.tar --strip 1 -C ${DISTBASE}_linux-$ZARCH
  done
fi

GPGKEY=dpkg
if [ -f apt/version ]; then
  DEBVERSION=`cat apt/version`
fi

for ZARCH in "i686" "x86_64"; do
  DIST=${DISTBASE}_linux-$ZARCH
  VERSION=`awk -F= '/^Version=/ { print $2 }' $DIST/application.ini`
  MAINTAINER=`awk -F= '/^ID=/ { print $2 }' $DIST/application.ini`
  NAME=`awk -F= '/^Name=/ { print $2 }' $DIST/$PACKAGE.desktop`

  if [ "$ZARCH" = "x86_64" ]; then
    ARCH=amd64
  else
    ARCH=i386
  fi

  # clear to start
  rm -rf apt/build

  # Put Zotero in place
  mkdir -p apt/build/usr/lib/$PACKAGE
  cp -r $DIST/* apt/build/usr/lib/$PACKAGE

  # disable updates
  mkdir -p apt/build/usr/lib/$PACKAGE/defaults/pref
  cat << EOF > apt/build/usr/lib/$PACKAGE/defaults/pref/local-settings.js
pref("general.config.obscure_value", 0); // only needed if you do not want to obscure the content with ROT-13
pref("general.config.filename", "mozilla.cfg");
EOF
  cat << EOF > apt/build/usr/lib/$PACKAGE/mozilla.cfg
//
lockPref("app.update.enabled", false);
lockPref("app.update.auto", false);
EOF

  # symlink to bin
  mkdir -p apt/build/usr/local/bin
  ln -s /usr/lib/$PACKAGE/$PACKAGE apt/build/usr/local/bin/$PACKAGE

  # desktop file
  rm -f apt/build/usr/lib/$PACKAGE/set_launcher_icon
  mkdir -p apt/build/usr/share/applications
  mv apt/build/usr/lib/$PACKAGE/$PACKAGE.desktop apt/build/usr/share/applications/$PACKAGE.desktop
  awk -i inplace -v package=$PACKAGE '
    {
      if (/^Exec=/) print "Exec=/usr/lib/" package "/" package " --url %u"
      else if (/^Icon=/) print "Icon=/usr/lib/" package "/chrome/icons/default/default256.png"
      else print $0

      next
    }

    /^MimeType=/ { mimetype=1; next }
    END { if (!mimetype) print "MimeType=x-scheme-handler/" package }
  ' apt/build/usr/share/applications/$PACKAGE.desktop

  # dpkg control file
  # additional dependencies taken from `apt-cache depends firefox-esr`
  mkdir -p apt/build/DEBIAN
  cat << EOF > apt/build/DEBIAN/control
Package: $PACKAGE
Architecture: $ARCH
Depends: libatk1.0-0, libc6, libcairo-gobject2, libcairo2, libdbus-1-3, libdbus-glib-1-2, libfontconfig1, libfreetype6, libgcc1, libgdk-pixbuf2.0-0, libglib2.0-0, libgtk-3-0, libnss3-dev, libpango-1.0-0, libpangocairo-1.0-0, libstartup-notification0, libstdc++6, libx11-6, libx11-xcb1, libxcb-shm0, libxcb1, libxcomposite1, libxdamage1, libxext6, libxfixes3, libxrender1, libxt6
Maintainer: $MAINTAINER
Section: Science
Priority: optional
Version: $VERSION$DEBVERSION
Description: $NAME is a free, easy-to-use tool to help you collect, organize, cite, and share research
EOF

  ### apt/repo MAY EXIST to hold builds for different archs/versions

  # build package
  mkdir -p apt/repo
  DEB=${PACKAGE}_$VERSION${DEBVERSION}_$ARCH.deb
  fakeroot dpkg-deb --build -Zgzip apt/build apt/repo/$DEB
  dpkg-sig -k $GPGKEY --sign builder apt/repo/$DEB
done

# update repo -- any existing debs in apt/repo will be picked up too
gpg --armor --export $GPGKEY > apt/repo/deb.gpg.key
(cd apt/repo && apt-ftparchive packages . > Packages)
bzip2 -kf apt/repo/Packages
(cd apt/repo && apt-ftparchive release . > Release)
gpg --yes -abs -u $GPGKEY -o apt/repo/Release.gpg --digest-algo sha256 apt/repo/Release
gpg --yes -abs -u $GPGKEY --clearsign -o apt/repo/InRelease --digest-algo sha256 apt/repo/Release

# updload the contents of the "apt/repo" directory now
