#!/bin/bash -e

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

# To speed up the CI we cache any downloads and the interop test server
# binaries. Cached items will have their version appended to their name so that
# the cache will be invalidated when versions change. When we copy them out of
# the cache the version numbers should be removed.

# Update .travis.yml if these change.
DOWNLOAD_CACHE="$HOME"/download_cache
BIN_CACHE="$HOME"/bin_cache

# Only applies to Linux, we get Swift from Xcode on macOS.
SWIFT_VERSION=5.0.2
PROTOBUF_VERSION=3.9.1
# We need this to build gRPC C++ for the interop test server(s).
BAZEL_VERSION=0.28.1
GRPC_VERSION=1.23.0

# Install the protoc compiler.
install_protoc() {
  echo -en 'travis_fold:start:install.protoc\\r'
  if [ "$TRAVIS_OS_NAME" = "osx" ]; then
    PROTOC_URL=https://github.com/google/protobuf/releases/download/v${PROTOBUF_VERSION}/protoc-${PROTOBUF_VERSION}-osx-x86_64.zip
  else
    PROTOC_URL=https://github.com/google/protobuf/releases/download/v${PROTOBUF_VERSION}/protoc-${PROTOBUF_VERSION}-linux-x86_64.zip
  fi

  PROTOC_ZIP=protoc."$PROTOBUF_VERSION".zip

  if [ ! -f "$DOWNLOAD_CACHE/$PROTOC_ZIP" ]; then
    echo "Downloading protoc from: $PROTOC_URL"
    curl -fSsL $PROTOC_URL -o "$DOWNLOAD_CACHE/$PROTOC_ZIP"
  else
    echo "Skipping protoc download, using cached version"
  fi

  unzip -q "$DOWNLOAD_CACHE/$PROTOC_ZIP" -d local
  echo -en 'travis_fold:end:install.protoc\\r'
}

# Install Swift.
install_swift() {
  echo -en 'travis_fold:start:install.swift\\r'
  # Use the Swift provided by Xcode on macOS.
  if [ "$TRAVIS_OS_NAME" != "osx" ]; then
    SWIFT_URL=https://swift.org/builds/swift-${SWIFT_VERSION}-release/ubuntu1804/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu18.04.tar.gz

    SWIFT_TAR_GZ=swift."$SWIFT_VERSION".tar.gz

    if [ ! -f "$DOWNLOAD_CACHE/$SWIFT_TAR_GZ" ]; then
      echo "Downloading swift from: $SWIFT_URL"
      curl -fSsL $SWIFT_URL -o "$DOWNLOAD_CACHE/$SWIFT_TAR_GZ"
    else
      echo "Skipping Swift download, using cached version"
    fi

    tar -xzf "$DOWNLOAD_CACHE/$SWIFT_TAR_GZ" --strip-components=2 --directory=local
  fi
  echo -en 'travis_fold:end:install.swift\\r'
}

# We need to install bazel to so we can build the gRPC interop test server.
install_bazel() {
  echo -en 'travis_fold:start:install.bazel\\r'
  # See:
  # - https://docs.bazel.build/versions/master/install-os-x.html
  # - https://docs.bazel.build/versions/master/install-ubuntu.html
  if [ "$TRAVIS_OS_NAME" = "osx" ]; then
    BAZEL_URL=https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-installer-darwin-x86_64.sh
  else
    BAZEL_URL=https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-installer-linux-x86_64.sh
  fi

  BAZEL_INSTALLER_SH=bazel-installer."$BAZEL_VERSION".sh

  if [ ! -f "$DOWNLOAD_CACHE/$BAZEL_INSTALLER_SH" ]; then
    echo "Downloading Bazel from: $BAZEL_URL"
    curl -fSsL $BAZEL_URL -o "$DOWNLOAD_CACHE/$BAZEL_INSTALLER_SH"
  else
    echo "Skipping Bazel download, using cached version"
  fi

  chmod +x "$DOWNLOAD_CACHE/$BAZEL_INSTALLER_SH"
  "$DOWNLOAD_CACHE/$BAZEL_INSTALLER_SH" --prefix="$HOME/local"

  echo -en 'travis_fold:end:install.bazel\\r'
}

# Build the gRPC C++ interop test server and reconnect interop test server.
build_grpc_cpp_server() {
  echo -en 'travis_fold:start:install.grpc_cpp_server\\r'
  GRPC_URL=https://github.com/grpc/grpc/archive/v${GRPC_VERSION}.tar.gz

  GRPC_INTEROP_SERVER=interop_server-"${GRPC_VERSION}"
  GRPC_RECONNECT_INTEROP_SERVER=reconnect_interop_server-"${GRPC_VERSION}"

  # If the servers don't exist: download and build them.
  if [ ! -f "$BIN_CACHE/$GRPC_INTEROP_SERVER" ] || [ ! -f "$BIN_CACHE/$GRPC_RECONNECT_INTEROP_SERVER" ]; then
    GRPC_TAR_GZ=grpc."$GRPC_VERSION".tar.gz

    # Do we already have gRPC?
    if [ ! -f "$DOWNLOAD_CACHE/$GRPC_TAR_GZ" ]; then
      echo "Downloading Bazel from: $BAZEL_URL"
      curl -fSsL $GRPC_URL -o "$DOWNLOAD_CACHE/$GRPC_TAR_GZ"
    else
      echo "Skipping Bazel download, using cached version"
    fi

    echo "Downloading gRPC from: $GRPC_URL"
    mkdir grpc
    tar -xzf "$DOWNLOAD_CACHE/$GRPC_TAR_GZ" --strip-components=1 --directory=grpc

    # Build the servers and put them in $BIN_CACHE
    (
      cd grpc
      # Build the interop_server and the reconnect_interop_server
      # Only update progress every second to avoid spamming the logs.
      "$HOME"/local/bin/bazel build \
        --show_progress_rate_limit=1 \
        test/cpp/interop:interop_server \
        test/cpp/interop:reconnect_interop_server

      # Put them in the $BIN_CACHE
      cp ./bazel-bin/test/cpp/interop/interop_server "$BIN_CACHE/$GRPC_INTEROP_SERVER"
      cp ./bazel-bin/test/cpp/interop/reconnect_interop_server "$BIN_CACHE/$GRPC_RECONNECT_INTEROP_SERVER"
    )
  else
    echo "Skipping download and build of gRPC C++, using cached binaries"
  fi

  # We should have cached servers now, copy them to $HOME/local/bin
  cp "$BIN_CACHE/$GRPC_INTEROP_SERVER" "$HOME"/local/bin/interop_server
  cp "$BIN_CACHE/$GRPC_RECONNECT_INTEROP_SERVER" "$HOME"/local/bin/reconnect_interop_server

  echo -en 'travis_fold:end:install.grpc_cpp_server\\r'
}

cd
mkdir -p local "$DOWNLOAD_CACHE" "$BIN_CACHE"

install_protoc
install_swift

if [ "$RUN_INTEROP_TESTS" = "true" ]; then
  install_bazel
  build_grpc_cpp_server
fi

# Verify installation
find local
