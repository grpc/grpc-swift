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

# Use this script to generate the Protocol Buffer and gRPC support files
# needed to build the example.
#
# Note that it requires protoc, protoc-gen-swift, and
# protoc-gen-swiftgrpc binaries. You can get protoc-gen-swift
# and protoc-gen-swiftgrpc by running `swift build` at the
# root of the grpc-swift repository.

if [ ! -d "googleapis" ]; then
  curl -L -O https://github.com/googleapis/googleapis/archive/master.zip
  unzip master.zip
  rm -f master.zip
  mv googleapis-master googleapis
fi

protoc \
	google/cloud/speech/v1/cloud_speech.proto \
	google/api/annotations.proto \
	google/api/http.proto \
	google/rpc/status.proto \
	google/longrunning/operations.proto \
	google/protobuf/descriptor.proto \
 	-Igoogleapis \
	--swift_out=googleapis \
	--swiftgrpc_out=googleapis

# move Swift files to the sources directory
mkdir -p Speech/Generated
find googleapis -name "*.swift" -exec mv {} Speech/Generated \;
