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

# This script bundles up the gRPC and Protobuf protoc plugins into a zip file
# suitable for the 'gRPC-Swift-Plugins' CocoaPod.
#
# The contents of thie zip should look like this:
#
#   ├── LICENSE
#   └── bin
#       ├── protoc-gen-grpc-swift
#       └── protoc-gen-swift

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 RELEASE_VERSION"
  exit 1
fi

version=$1
zipfile="protoc-grpc-swift-plugins-${version}.zip"

# Where are we?
here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# The root of the repo is just above us.
root="${here}/.."

# Make a staging area.
stage=$(mktemp -d)
stage_bin="${stage}/bin"
mkdir -p "${stage_bin}"

# Make the plugins.
make -C "${root}" plugins

# Copy them to the stage.
cp "${root}/protoc-gen-grpc-swift" "${stage_bin}"
cp "${root}/protoc-gen-swift" "${stage_bin}"

# Copy the LICENSE to the stage.
cp "${root}/LICENSE" "${stage}"

# Zip it up.
pushd "${stage}" || exit
zip -r "${zipfile}" .
popd || exit

# Tell us where it is.
echo "Created ${stage}/${zipfile}"
