#!/bin/bash

# Copyright 2020, gRPC Authors All rights reserved.
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

set -eu

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO="$HERE/.."
SWIFTFORMAT_DIR="$HERE/.swiftformat-source"

# Important: if this is changed then make sure to update the version
# in .travis-install.sh as well!
SWIFTFORMAT_VERSION=0.46.3

# Clone SwiftFormat if we don't already have it.
if [ ! -d "$SWIFTFORMAT_DIR" ]; then
  echo "- Cloning SwiftFormat @ $SWIFTFORMAT_VERSION"
  git clone \
    --depth 1 \
    --branch "$SWIFTFORMAT_VERSION" \
    https://github.com/nicklockwood/SwiftFormat.git \
    "$SWIFTFORMAT_DIR"
fi

cd "$SWIFTFORMAT_DIR"

# Figure out the path for the binary.
SWIFTFORMAT_BIN="$(swift build --show-bin-path -c release)/swiftformat-$SWIFTFORMAT_VERSION"

# Build it if we don't already have it.
if [ ! -f "$SWIFTFORMAT_BIN" ]; then
  # We're not on the right tag, fetch and checkout the right one.
  echo "- Fetching SwiftFormat @ $SWIFTFORMAT_VERSION"
  git fetch --depth 1 origin "refs/tags/$SWIFTFORMAT_VERSION:refs/tags/$SWIFTFORMAT_VERSION"
  git checkout "$SWIFTFORMAT_VERSION"

  # Now build and name the bin appropriately.
  echo "- Building SwiftFormat @ $SWIFTFORMAT_VERSION"
  swift build -c release --product swiftformat
  mv "$(swift build --show-bin-path -c release)/swiftformat" "$SWIFTFORMAT_BIN"

  echo "- OK"
fi

# Now run it.
$SWIFTFORMAT_BIN "$REPO"
