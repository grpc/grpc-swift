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

# To speed up the CI we cache the interop test server binaries. We cache the
# binaries with the gRPC version appended to their name as a means of
# invalidating the cache when we bump versions.

# Update .travis.yml if this changes.
BIN_CACHE="$HOME"/bin_cache
ZIP_CACHE="$HOME"/zip_cache

PROTOBUF_VERSION=3.9.1
# We need this to build gRPC C++ for the interop test server(s).
BAZEL_VERSION=0.28.1
GRPC_VERSION=1.23.0

info() {
  printf '\033[0;34m%s\033[0m\n' "$1"
}

success() {
  printf '\033[0;32m%s\033[0m\n' "$1"
}

# Install the protoc compiler.
install_protoc() {
  echo -en 'travis_fold:start:install.protoc\\r'
  info "Installing protoc $PROTOBUF_VERSION"

  # Which protoc are we using?
  if [ "$TRAVIS_OS_NAME" = "osx" ]; then
    PROTOC_ZIP=protoc-${PROTOBUF_VERSION}-osx-x86_64.zip
  else
    PROTOC_ZIP=protoc-${PROTOBUF_VERSION}-linux-x86_64.zip
  fi

  CACHED_PROTOC_ZIP="$ZIP_CACHE/$PROTOC_ZIP"

  # Is it cached?
  if [ ! -f "$CACHED_PROTOC_ZIP" ]; then
    # No: download it.
    PROTOC_URL=https://github.com/google/protobuf/releases/download/v${PROTOBUF_VERSION}/${PROTOC_ZIP}
    info "Downloading protoc from: $PROTOC_URL"
    if curl -fSsL "$PROTOC_URL" -o "$CACHED_PROTOC_ZIP"; then
      info "Downloaded protoc from: $PROTOC_URL"
    else
      info "Downloading protoc failed, removing artifacts"
      rm "$CACHED_PROTOC_ZIP"
      exit 1
    fi
  else
    info "Using cached protoc"
  fi

  info "Extracting protoc from $CACHED_PROTOC_ZIP"
  unzip -q "$CACHED_PROTOC_ZIP" -d local
  success "Installed protoc $PROTOBUF_VERSION"
  echo -en 'travis_fold:end:install.protoc\\r'
}

# Install Swift.
install_swift() {
  echo -en 'travis_fold:start:install.swift\\r'

  # Use the Swift provided by Xcode on macOS.
  if [ "$TRAVIS_OS_NAME" != "osx" ]; then
    info "Installing Swift $SWIFT_VERSION"

    if [ -z "${SWIFT_URL}" ]; then
      SWIFT_URL=https://swift.org/builds/swift-${SWIFT_VERSION}-release/ubuntu1804/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu18.04.tar.gz
    fi

    info "Downloading Swift from $SWIFT_URL"
    curl -fSsL "$SWIFT_URL" -o swift.tar.gz

    info "Extracting Swift from swift.tar.gz"
    tar -xzf swift.tar.gz --strip-components=2 --directory=local
    success "Installed Swift $SWIFT_VERSION"
  else
    info "Skipping Swift installation: using Swift provided by Xcode"
  fi
  echo -en 'travis_fold:end:install.swift\\r'
}

# We need to install bazel to so we can build the gRPC interop test server.
install_bazel() {
  echo -en 'travis_fold:start:install.bazel\\r'

  info "Installing Bazel $BAZEL_VERSION"

  # See:
  # - https://docs.bazel.build/versions/master/install-os-x.html
  # - https://docs.bazel.build/versions/master/install-ubuntu.html
  if [ "$TRAVIS_OS_NAME" = "osx" ]; then
    BAZEL_URL=https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-installer-darwin-x86_64.sh
  else
    BAZEL_URL=https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-installer-linux-x86_64.sh
  fi

  info "Downloading Bazel from: $BAZEL_URL"
  curl -fSsL $BAZEL_URL -o bazel-installer.sh

  chmod +x bazel-installer.sh
  info "Running ./bazel-installer.sh"
  ./bazel-installer.sh --prefix="$HOME/local"
  success "Installed Bazel"
  echo -en 'travis_fold:end:install.bazel\\r'
}

# Build the gRPC C++ interop test server and reconnect interop test server.
build_grpc_cpp_server() {
  echo -en 'travis_fold:start:install.grpc_cpp_server\\r'

  info "Building gRPC $GRPC_VERSION C++ interop servers"
  GRPC_INTEROP_SERVER=interop_server-"$GRPC_VERSION"
  GRPC_RECONNECT_INTEROP_SERVER=reconnect_interop_server-"$GRPC_VERSION"

  # If the servers don't exist: download and build them.
  if [ ! -f "$BIN_CACHE/$GRPC_INTEROP_SERVER" ] || [ ! -f "$BIN_CACHE/$GRPC_RECONNECT_INTEROP_SERVER" ]; then
    GRPC_URL=https://github.com/grpc/grpc/archive/v${GRPC_VERSION}.tar.gz

    info "Downloading gRPC from: $GRPC_URL"
    curl -fSsL $GRPC_URL -o grpc.tar.gz

    # Extract it to grpc
    mkdir grpc
    info "Extracting grpc.tar.gz to grpc"
    tar -xzf grpc.tar.gz --strip-components=1 --directory=grpc

    # Build the interop servers and put them in $BIN_CACHE
    (
      cd grpc
      # Only update progress every second to avoid spamming the logs.
      "$HOME"/local/bin/bazel build \
        --show_progress_rate_limit=1 \
        test/cpp/interop:interop_server \
        test/cpp/interop:reconnect_interop_server

      # Put them in the $BIN_CACHE
      info "Copying interop server to $BIN_CACHE/$GRPC_INTEROP_SERVER"
      cp ./bazel-bin/test/cpp/interop/interop_server "$BIN_CACHE/$GRPC_INTEROP_SERVER"
      info "Copying interop reconnect server to $BIN_CACHE/$GRPC_RECONNECT_INTEROP_SERVER"
      cp ./bazel-bin/test/cpp/interop/reconnect_interop_server "$BIN_CACHE/$GRPC_RECONNECT_INTEROP_SERVER"
    )
  else
    info "Skipping download and build of gRPC C++, using cached binaries"
  fi

  # We should have cached servers now, copy them to $HOME/local/bin
  cp "$BIN_CACHE/$GRPC_INTEROP_SERVER" "$HOME"/local/bin/interop_server
  cp "$BIN_CACHE/$GRPC_RECONNECT_INTEROP_SERVER" "$HOME"/local/bin/reconnect_interop_server

  success "Copied gRPC interop servers"
  echo -en 'travis_fold:end:install.grpc_cpp_server\\r'
}

function install_swiftformat() {
  echo -en 'travis_fold:start:install.swiftformat\\r'
  info "Installing swiftformat"

  # If this version is updated, update the version in scripts/format.sh too.
  git clone --depth 1 --branch 0.46.3 "https://github.com/nicklockwood/SwiftFormat"
  cd SwiftFormat
  version=$(git rev-parse HEAD)

  if [ ! -f "$BIN_CACHE/swiftformat-$version" ]; then
    info "Building swiftformat"
    swift build --product swiftformat

    cp "$(swift build --show-bin-path)/swiftformat" "$BIN_CACHE/swiftformat-$version"
  else
    info "Skipping build of SwiftFormat, using cached binaries"
  fi

  # We should have cached swiftformat now, copy it to $HOME/local/bin
  cp "$BIN_CACHE/swiftformat-$version" "$HOME"/local/bin/swiftformat

  success "Installed swiftformat"
  echo -en 'travis_fold:end:install.swiftformat\\r'
}

cd
mkdir -p local/bin "$BIN_CACHE" "$ZIP_CACHE"

should_install_protoc=false
should_install_interop_server=false
should_install_swiftformat=false

while getopts "pif" optname; do
  case $optname in
    p)
      should_install_protoc=true
      ;;
    i)
      should_install_interop_server=true
      ;;
    f)
      should_install_swiftformat=true
      ;;
    \?)
      echo "Uknown option $optname"
      exit 2
      ;;
  esac
done

# Always install Swift.
install_swift

if $should_install_protoc; then
  install_protoc
fi

if $should_install_interop_server; then
  install_bazel
  build_grpc_cpp_server
fi

if $should_install_swiftformat; then
  # If we're building SwiftFormat we need to know where Swift lives.
  export PATH=$HOME/local/bin:$PATH
  install_swiftformat
fi

# Verify installation
info "Contents of $HOME/local:"
find "$HOME"/local
success "Install script completed"
