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
source "${HERE}/../test-boilerplate.sh"

MODULE_MAP="${HERE}/swift.modulemap"

function all_at_once {
  echo "[${TEST}] all_at_once"
  prepare

  protoc \
    --proto_path="${PROTO_DIR}" \
    --plugin="${PROTOC_GEN_GRPC_SWIFT}" \
    --grpc-swift_opt=ProtoPathModuleMappings="${MODULE_MAP}" \
    --grpc-swift_out="${OUTPUT_DIR}" \
    "${PROTO_DIR}"/*.proto

  validate
}

function one_at_a_time {
  echo "[${TEST}] one_at_a_time"
  prepare

  protoc \
    --proto_path="${PROTO_DIR}" \
    --plugin="${PROTOC_GEN_GRPC_SWIFT}" \
    --grpc-swift_opt=ProtoPathModuleMappings="${MODULE_MAP}" \
    --grpc-swift_out="${OUTPUT_DIR}" \
    "${PROTO_DIR}"/a.proto

  protoc \
    --proto_path="${PROTO_DIR}" \
    --plugin="${PROTOC_GEN_GRPC_SWIFT}" \
    --grpc-swift_opt=ProtoPathModuleMappings="${MODULE_MAP}" \
    --grpc-swift_out="${OUTPUT_DIR}" \
    "${PROTO_DIR}"/b.proto

  validate
}

one_at_a_time
all_at_once
