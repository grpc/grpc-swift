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
root="$here/.."
protoc=$(which protoc)

# Build the protoc plugins.
swift build -c release --product protoc-gen-swift
swift build -c release --product protoc-gen-grpc-swift

# Grab the plugin paths.
bin_path=$(swift build -c release --show-bin-path)
protoc_gen_swift="$bin_path/protoc-gen-swift"
protoc_generate_grpc_swift="$bin_path/protoc-gen-grpc-swift"

# Genreates gRPC by invoking protoc with the gRPC Swift plugin.
# Parameters:
# - $1: .proto file
# - $2: proto path
# - $3: output path
# - $4 onwards: options to forward to the plugin
function generate_grpc {
  local proto=$1
  local args=("--plugin=$protoc_generate_grpc_swift" "--proto_path=${2}" "--grpc-swift_out=${3}")

  for option in "${@:4}"; do
    args+=("--grpc-swift_opt=$option")
  done

  invoke_protoc "${args[@]}" "$proto"
}

# Genreates messages by invoking protoc with the Swift plugin.
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

function generate_echo_example {
  local proto="$here/examples/echo/echo.proto"
  local output="$root/Sources/Examples/Echo/Model"

  generate_message "$proto" "$(dirname "$proto")" "$output" "Visibility=Public"
  generate_grpc "$proto" "$(dirname "$proto")" "$output" "Visibility=Public" "TestClient=true"
}

function generate_routeguide_example {
  local proto="$here/examples/route_guide/route_guide.proto"
  local output="$root/Sources/Examples/RouteGuide/Model"

  generate_message "$proto" "$(dirname "$proto")" "$output" "Visibility=Public"
  generate_grpc "$proto" "$(dirname "$proto")" "$output" "Visibility=Public"
}

function generate_helloworld_example {
  local proto="$here/upstream/grpc/examples/helloworld.proto"
  local output="$root/Sources/Examples/HelloWorld/Model"

  generate_message "$proto" "$(dirname "$proto")" "$output" "Visibility=Public"
  generate_grpc "$proto" "$(dirname "$proto")" "$output" "Visibility=Public"
}

function generate_reflection_service {
  local proto_v1="$here/upstream/grpc/reflection/v1/reflection.proto"
  local output_v1="$root/Sources/GRPCReflectionService/v1"

  # Messages were accidentally leaked into public API, they shouldn't be but we
  # can't undo that change until the next major version.
  generate_message "$proto_v1" "$(dirname "$proto_v1")" "$output_v1" "Visibility=Public"
  generate_grpc "$proto_v1" "$(dirname "$proto_v1")" "$output_v1" "Visibility=Internal" "Client=false"

  # Both protos have the same name so will generate Swift files with the same
  # name. SwiftPM can't handle this so rename them.
  mv "$output_v1/reflection.pb.swift" "$output_v1/reflection-v1.pb.swift"
  mv "$output_v1/reflection.grpc.swift" "$output_v1/reflection-v1.grpc.swift"

  local proto_v1alpha="$here/upstream/grpc/reflection/v1alpha/reflection.proto"
  local output_v1alpha="$root/Sources/GRPCReflectionService/v1alpha"

  # Messages were accidentally leaked into public API, they shouldn't be but we
  # can't undo that change until the next major version.
  generate_message "$proto_v1alpha" "$(dirname "$proto_v1alpha")" "$output_v1alpha" "Visibility=Public"
  generate_grpc "$proto_v1alpha" "$(dirname "$proto_v1alpha")" "$output_v1alpha" "Visibility=Internal" "Client=false"

  # Both protos have the same name so will generate Swift files with the same
  # name. SwiftPM can't handle this so rename them.
  mv "$output_v1alpha/reflection.pb.swift" "$output_v1alpha/reflection-v1alpha.pb.swift"
  mv "$output_v1alpha/reflection.grpc.swift" "$output_v1alpha/reflection-v1alpha.grpc.swift"
}

function generate_reflection_client_for_tests {
  local proto_v1="$here/upstream/grpc/reflection/v1/reflection.proto"
  local output_v1="$root/Tests/GRPCTests/GRPCReflectionServiceTests/Generated/v1"

  generate_message "$proto_v1" "$(dirname "$proto_v1")" "$output_v1" "Visibility=Internal"
  generate_grpc "$proto_v1" "$(dirname "$proto_v1")" "$output_v1" "Visibility=Internal" "Server=false"

  # Both protos have the same name so will generate Swift files with the same
  # name. SwiftPM can't handle this so rename them.
  mv "$output_v1/reflection.pb.swift" "$output_v1/reflection-v1.pb.swift"
  mv "$output_v1/reflection.grpc.swift" "$output_v1/reflection-v1.grpc.swift"

  local proto_v1alpha="$here/upstream/grpc/reflection/v1alpha/reflection.proto"
  local output_v1alpha="$root/Tests/GRPCTests/GRPCReflectionServiceTests/Generated/v1Alpha"

  generate_message "$proto_v1alpha" "$(dirname "$proto_v1alpha")" "$output_v1alpha" "Visibility=Internal"
  generate_grpc "$proto_v1alpha" "$(dirname "$proto_v1alpha")" "$output_v1alpha" "Visibility=Internal" "Server=false"

  # Both protos have the same name so will generate Swift files with the same
  # name. SwiftPM can't handle this so rename them.
  mv "$output_v1alpha/reflection.pb.swift" "$output_v1alpha/reflection-v1alpha.pb.swift"
  mv "$output_v1alpha/reflection.grpc.swift" "$output_v1alpha/reflection-v1alpha.grpc.swift"
}

function generate_normalization_for_tests {
  local proto="$here/tests/normalization/normalization.proto"
  local output="$root/Tests/GRPCTests/Codegen/Normalization"

  generate_message "$proto" "$(dirname "$proto")" "$output" "Visibility=Internal"
  generate_grpc "$proto" "$(dirname "$proto")" "$output" "Visibility=Internal" "KeepMethodCasing=true"
}

function generate_echo_reflection_data_for_tests {
  local proto="$here/examples/echo/echo.proto"
  local output="$root/Tests/GRPCTests/Codegen/Serialization"

  generate_grpc "$proto" "$(dirname "$proto")" "$output" "Client=false" "Server=false" "ReflectionData=true"
}

function generate_reflection_data_example {
  local protos=("$here/examples/echo/echo.proto" "$here/upstream/grpc/examples/helloworld.proto")
  local output="$root/Sources/Examples/ReflectionService/Generated"

  for proto in "${protos[@]}"; do
    generate_grpc "$proto" "$(dirname "$proto")" "$output" "Client=false" "Server=false" "ReflectionData=true"
  done
}

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

# Examples
generate_echo_example
generate_routeguide_example
generate_helloworld_example
generate_reflection_data_example

# Reflection service and tests
generate_reflection_service
generate_reflection_client_for_tests
generate_echo_reflection_data_for_tests

# Misc. tests
generate_normalization_for_tests
generate_rpc_code_for_tests
