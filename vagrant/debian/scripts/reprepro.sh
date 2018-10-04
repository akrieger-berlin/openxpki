#!/bin/bash

# Run this from inside your vagrant machine from a full shell
# as it will prompt you for the signing key password!

if [ ! -d /packages.openxpki.org ]; then
    echo "You must map the repository target to /packages.openxpki.org"
    exit;
fi;

DIST=`lsb_release -c -s`
if [ "$DIST" == "jessie" ]; then
    PACKAGE=debian
    SOURCE="deb http://packages.openxpki.org/v2/debian/ jessie release"
elif [ "$DIST" == "trusty" ]; then
    PACKAGE=ubuntu
    SOURCE="deb http://packages.openxpki.org/v2/ubuntu/ dists/trusty/release/binary-amd64/"
else
    echo "Unknown distro $DIST"; exit 1;
fi;

if [ -e "/packages.openxpki.org/$PACKAGE/conf" ]; then
    rm -r  /packages.openxpki.org/v2/$PACKAGE/
fi;

mkdir -p /packages.openxpki.org/v2/$PACKAGE/
ln -s /code-repo/package/debian/reprepro-$PACKAGE /packages.openxpki.org/v2/$PACKAGE/conf

# Install reprepro if not present
test -e /usr/bin/reprepro || sudo aptitude -y install reprepro

# Start and source gpg-agent
gpg-agent --daemon > ~/.gnupg/.agent
. ~/.gnupg/.agent

for f in `find /code-repo/package/debian/deb -maxdepth 2  -name "*.deb"`; do 
    reprepro --confdir /packages.openxpki.org/v2/$PACKAGE/conf/ includedeb $DIST $f;
done;

# Extra packages if present (like openca-tools)
if [ -d "/code-repo/package/debian/extra" ]; then
    find /code-repo/package/debian/extra -name "*.deb" | xargs -L1 --no-run-if-empty reprepro --confdir  /packages.openxpki.org/v2/$PACKAGE/conf/ includedeb $DIST;
fi

# Copy the release key it does not exist
test -e /packages.openxpki.org/v2/$PACKAGE/Release.key || cp /code-repo/package/debian/Release.key /packages.openxpki.org/v2/$PACKAGE/

# Add the apt config
echo $SOURCE > /packages.openxpki.org/v2/$PACKAGE/openxpki.list 

