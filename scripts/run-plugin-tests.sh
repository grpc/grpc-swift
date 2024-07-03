#!/bin/bash

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

set -eux

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GRPC_PATH="${HERE}/.."

function generate_package_manifest {
  local tools_version=$1
  local grpc_path=$2
  local grpc_version=$3

  echo "// swift-tools-version: $tools_version"
  echo "import PackageDescription"
  echo ""
  echo "let package = Package("
  echo "  name: \"Foo\","
  echo "  dependencies: ["
  echo "    .package(path: \"$grpc_path\"),"
  echo "    .package(url: \"https://github.com/apple/swift-protobuf\", from: \"1.26.0\")"
  echo "  ],"
  echo "  targets: ["
  echo "    .executableTarget("
  echo "      name: \"Foo\","
  echo "      dependencies: ["

  if [ "$grpc_version" == "v1" ]; then
    echo "        .product(name: \"GRPC\", package: \"grpc-swift\"),"
  elif [ "$grpc_version" == "v2" ]; then
    echo "        .product(name: \"_GRPCCore\", package: \"grpc-swift\"),"
    echo "        .product(name: \"_GRPCProtobuf\", package: \"grpc-swift\"),"
  fi

  echo "      ],"
  echo "      path: \"Sources/Foo\","
  echo "      plugins: ["
  echo "        .plugin(name: \"GRPCSwiftPlugin\", package: \"grpc-swift\"),"
  echo "        .plugin(name: \"SwiftProtobufPlugin\", package: \"swift-protobuf\"),"
  echo "      ]"
  echo "    ),"
  echo "  ]"
  echo ")"
}

function generate_grpc_plugin_config {
  local grpc_version=$1

  echo "{"
  echo "  \"invocations\": ["
  echo "    {"
  if [ "$grpc_version" == "v2" ]; then
    echo "      \"_V2\": true,"
  fi
  echo "      \"protoFiles\": [\"Foo.proto\"],"
  echo "      \"visibility\": \"internal\""
  echo "    }"
  echo "  ]"
  echo "}"
}

function generate_protobuf_plugin_config {
  echo "{"
  echo "  \"invocations\": ["
  echo "    {"
  echo "      \"protoFiles\": [\"Foo.proto\"],"
  echo "      \"visibility\": \"internal\""
  echo "    }"
  echo "  ]"
  echo "}"
}

function generate_proto {
  cat <<EOF
syntax = "proto3";

service Foo {
  rpc Bar(Baz) returns (Baz) {}
}

message Baz {}
EOF
}

function generate_main {
  echo "// This file was intentionally left blank."
}

function generate_and_build {
  local tools_version=$1
  local grpc_path=$2
  local grpc_version=$3
  local protoc_path dir

  protoc_path=$(which protoc)
  dir=$(mktemp -d)

  echo "Generating package in $dir ..."
  echo "Swift tools version: $tools_version"
  echo "grpc-swift version: $grpc_version"
  echo "grpc-swift path: $grpc_path"
  echo "protoc path: $protoc_path"
  mkdir -p "$dir/Sources/Foo"

  generate_package_manifest "$tools_version" "$grpc_path" "$grpc_version" > "$dir/Package.swift"

  generate_protobuf_plugin_config > "$dir/Sources/Foo/swift-protobuf-config.json"
  generate_proto > "$dir/Sources/Foo/Foo.proto"
  generate_main > "$dir/Sources/Foo/main.swift"
  generate_grpc_plugin_config "$grpc_version" > "$dir/Sources/Foo/grpc-swift-config.json"

  PROTOC_PATH=$protoc_path swift build --package-path "$dir"
}

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 SWIFT_TOOLS_VERSION GRPC_SWIFT_VERSION"
fi

if [ "$2" != "v1" ] && [ "$2" != "v2" ]; then
  echo "Invalid gRPC Swift version '$2' (must be 'v1' or 'v2')"
  exit 1
fi

generate_and_build "$1" "${GRPC_PATH}" "$2"
