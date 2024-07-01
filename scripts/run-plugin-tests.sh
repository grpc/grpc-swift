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

set -eu

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GRPC_PATH="${HERE}/.."

function generate_package_manifest {
  local version=$1
  local grpc_path=$2

  echo "// swift-tools-version: $version"
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
  echo "        .product(name: \"GRPC\", package: \"grpc-swift\"),"
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
  cat <<EOF
{
  "invocations": [
    {
      "protoFiles": ["Foo.proto"],
      "visibility": "internal"
    }
  ]
}
EOF
}

function generate_protobuf_plugin_config {
  generate_grpc_plugin_config
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
  local version=$1
  local grpc_path=$2
  local protoc_path dir

  protoc_path=$(which protoc)
  dir=$(mktemp -d)

  echo "Generating package in $dir ..."
  echo "Swift tools version: $version"
  echo "grpc-swift path: $grpc_path"
  echo "protoc path: $protoc_path"
  mkdir -p "$dir/Sources/Foo"

  generate_package_manifest "$version" "$grpc_path" > "$dir/Package.swift"
  generate_grpc_plugin_config > "$dir/Sources/Foo/grpc-swift-config.json"
  generate_protobuf_plugin_config > "$dir/Sources/Foo/swift-protobuf-config.json"
  generate_proto > "$dir/Sources/Foo/Foo.proto"
  generate_main > "$dir/Sources/Foo/main.swift"

  PROTOC_PATH=$protoc_path swift build --package-path "$dir"
}

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 SWIFT_TOOLS_VERSION"
  exit 1
fi

generate_and_build "$1" "${GRPC_PATH}"
