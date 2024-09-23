#!/bin/bash
#
# Copyright 2024, gRPC Authors All rights reserved.
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

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
root="$here/../.."
protoc=$(which protoc)

# Build the protoc plugins.
swift build -c release --product protoc-gen-swift

# Grab the plugin paths.
bin_path=$(swift build -c release --show-bin-path)
protoc_gen_swift="$bin_path/protoc-gen-swift"

# Generates messages by invoking protoc with the Swift plugin.
# Parameters:
# - $1: .proto file
# - $2: proto path
# - $3: output path
# - $4 onwards: options to forward to the plugin
function generate_message {
  local proto=$1
  local args=("--plugin=$protoc_gen_swift" "--proto_path=$2" "--swift_out=$3")

  for option in "${@:4}"; do
    args+=("--swift_opt=$option")
  done

  invoke_protoc "${args[@]}" "$proto"
}

function invoke_protoc {
  # Setting -x when running the script produces a lot of output, instead boil
  # just echo out the protoc invocations.
  echo "$protoc" "$@"
  "$protoc" "$@"
}

#------------------------------------------------------------------------------

function generate_rpc_code_for_tests {
  local protos=(
    "$here/upstream/grpc/service_config/service_config.proto"
    "$here/upstream/grpc/lookup/v1/rls.proto"
    "$here/upstream/grpc/lookup/v1/rls_config.proto"
    "$here/upstream/google/rpc/code.proto"
  )
  local output="$root/Tests/GRPCCoreTests/Configuration/Generated"

  for proto in "${protos[@]}"; do
    generate_message "$proto" "$here/upstream" "$output" "Visibility=Internal" "FileNaming=DropPath"
  done
}

#------------------------------------------------------------------------------

# Tests
generate_rpc_code_for_tests
