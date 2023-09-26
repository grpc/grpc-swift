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

function log() { printf -- "** %s\n" "$*" >&2; }
function error() { printf -- "** ERROR: %s\n" "$*" >&2; }
function fatal() { error "$*"; exit 1; }

function usage() {
  echo >&2 "Usage:"
  echo >&2 "  $0 -[f|l]"
  echo >&2 ""
  echo >&2 "Options:"
  echo >&2 "  -f   Format source code in place"
  echo >&2 "  -l   Lint check without formatting the source code"
}

lint=false
while getopts ":lh" opt; do
  case "$opt" in
    l)
      lint=true
      ;;
    h)
      usage
      exit 1
      ;;
    \?)
      usage
      exit 1
      ;;
  esac
done

THIS_SCRIPT=$0
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO="$HERE/.."
SWIFTFORMAT_DIR="$HERE/.swift-format-source"
SWIFTFORMAT_VERSION=509.0.0

# Clone SwiftFormat if we don't already have it.
if [ ! -d "$SWIFTFORMAT_DIR" ]; then
  echo "- Cloning swift-format @ $SWIFTFORMAT_VERSION"
  git clone \
    --depth 1 \
    --branch "$SWIFTFORMAT_VERSION" \
    https://github.com/apple/swift-format.git \
    "$SWIFTFORMAT_DIR"
fi

cd "$SWIFTFORMAT_DIR"

# Figure out the path for the binary.
SWIFTFORMAT_BIN="$(swift build --show-bin-path -c release)/swift-format-$SWIFTFORMAT_VERSION"

# Build it if we don't already have it.
if [ ! -f "$SWIFTFORMAT_BIN" ]; then
  # We're not on the right tag, fetch and checkout the right one.
  echo "- Fetching swift-format @ $SWIFTFORMAT_VERSION"
  git fetch --depth 1 origin "refs/tags/$SWIFTFORMAT_VERSION:refs/tags/$SWIFTFORMAT_VERSION"
  git checkout "$SWIFTFORMAT_VERSION"

  # Now build and name the bin appropriately.
  echo "- Building swift-format @ $SWIFTFORMAT_VERSION"
  swift build -c release --product swift-format
  mv "$(swift build --show-bin-path -c release)/swift-format" "$SWIFTFORMAT_BIN"

  echo "- OK"
fi

if "$lint"; then
  "${SWIFTFORMAT_BIN}" lint \
    --parallel --recursive --strict \
    "${REPO}/Sources" "${REPO}/Tests" \
    && SWIFT_FORMAT_RC=$? || SWIFT_FORMAT_RC=$?

  if [[ "${SWIFT_FORMAT_RC}" -ne 0 ]]; then
    fatal "Running swift-format produced errors.

    To fix, run the following command:

    % $THIS_SCRIPT -f
    "
    exit "${SWIFT_FORMAT_RC}"
  fi

  log "Ran swift-format lint with no errors."
else
  "${SWIFTFORMAT_BIN}" format \
    --parallel --recursive --in-place \
    "${REPO}/Sources" "${REPO}/Tests" \
    && SWIFT_FORMAT_RC=$? || SWIFT_FORMAT_RC=$?

  if [[ "${SWIFT_FORMAT_RC}" -ne 0 ]]; then
    fatal "Running swift-format produced errors." "${SWIFT_FORMAT_RC}"
  fi

  log "Ran swift-format with no errors."
fi
