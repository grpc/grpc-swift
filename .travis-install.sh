#!/bin/sh
#
# Copyright 2017, gRPC Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Install dependencies that aren't available as Ubuntu packages (or already present on macOS).
#
# Everything goes into $HOME/local.
#
# Scripts should add
# - $HOME/local/bin to PATH
# - $HOME/local/lib to LD_LIBRARY_PATH
#

cd
mkdir -p local

if [[ "${TRAVIS_OS_NAME}" == "osx" ]]; then
  PROTOC_URL=https://github.com/google/protobuf/releases/download/v3.5.1/protoc-3.5.1-osx-x86_64.zip
else
  # Install swift
  SWIFT_URL=https://swift.org/builds/swift-${SWIFT_VERSION}-release/ubuntu1404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu14.04.tar.gz
  echo $SWIFT_URL
  curl -fSsL $SWIFT_URL -o swift.tar.gz
  tar -xzf swift.tar.gz --strip-components=2 --directory=local

  PROTOC_URL=https://github.com/google/protobuf/releases/download/v3.5.1/protoc-3.5.1-linux-x86_64.zip
fi

# Install protoc
echo $PROTOC_URL
curl -fSsL $PROTOC_URL -o protoc.zip
unzip -q protoc.zip -d local

# Verify installation
find local
