#!/bin/sh

SWIFT_BRANCH=swift-3.0.2-release
SWIFT_VERSION=swift-3.0.2-RELEASE
SWIFT_PLATFORM=ubuntu14.04
SWIFT_URL=https://swift.org/builds/$SWIFT_BRANCH/$(echo "$SWIFT_PLATFORM" | tr -d .)/$SWIFT_VERSION/$SWIFT_VERSION-$SWIFT_PLATFORM.tar.gz

echo $SWIFT_URL
pwd

cd
pwd
mkdir -p swift
curl -fSsL $SWIFT_URL -o swift.tar.gz 
tar -xzf swift.tar.gz --strip-components=2 --directory=swift
