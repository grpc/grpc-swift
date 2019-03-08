#!/bin/sh

# Copyright 2019, gRPC Authors All rights reserved.
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

# This script may be used to update the vendored versions of SwiftGRPC's
# dependencies for use with Swift Package Manager.
# As part of this process, BoringSSL and gRPC Core are both vendored by
# invoking their respective vendoring scripts in this directory.
#
# Usage: `$ ./vendor-all.sh v1.14.0` # Or whatever the gRPC core version is

set -euxo pipefail

TMP_DIR=./tmp
GRPC_VERSION="$1"

mkdir -p $TMP_DIR
rm -rf $TMP_DIR/grpc
cd $TMP_DIR

# Clone gRPC Core, update its submodules, and check out the specified version.
git clone git@github.com:grpc/grpc.git
cd grpc
git submodule update --init --recursive
git checkout $GRPC_VERSION
cd ../..

# Update the vendored version of BoringSSL (removing previous versions).
./vendor-boringssl.sh

# Copy the vendoring template into the gRPC Core's directory of templates.
# Then, run the gRPC Core's generator on that template.
cp ./swift-vendoring.sh.template $TMP_DIR/grpc/templates
cd $TMP_DIR/grpc
./tools/buildgen/generate_projects.sh
cd ../..

# Finish copying the vendored version of the gRPC Core.
./vendor-grpc.sh

echo "UPDATED vendored dependencies to $GRPC_VERSION"
