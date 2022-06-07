#!/bin/sh

set -euo pipefail

CURRENT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PLUGIN_SWIFT=../../.build/release/protoc-gen-swift
PLUGIN_SWIFTGRPC=../../.build/release/protoc-gen-grpc-swift
PROTO="src/proto/grpc/testing/test.proto"

OUTPUT="Generated"
FILE_NAMING="DropPath"
VISIBILITY="Public"

(cd "${CURRENT_SCRIPT_DIR}" && protoc "src/proto/grpc/testing/test.proto" \
  --plugin=${PLUGIN_SWIFT} \
  --plugin=${PLUGIN_SWIFTGRPC} \
  --swift_out=${OUTPUT} \
  --swift_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY} \
  --grpc-swift_out=${OUTPUT} \
  --grpc-swift_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY})

(cd "${CURRENT_SCRIPT_DIR}" && protoc "src/proto/grpc/testing/empty.proto" \
  --plugin=${PLUGIN_SWIFT} \
  --plugin=${PLUGIN_SWIFTGRPC} \
  --swift_out=${OUTPUT} \
  --swift_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY} \
  --grpc-swift_out=${OUTPUT} \
  --grpc-swift_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY})

(cd "${CURRENT_SCRIPT_DIR}" && protoc "src/proto/grpc/testing/messages.proto" \
  --plugin=${PLUGIN_SWIFT} \
  --plugin=${PLUGIN_SWIFTGRPC} \
  --swift_out=${OUTPUT} \
  --swift_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY} \
  --grpc-swift_out=${OUTPUT} \
  --grpc-swift_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY})

# The generated code needs to be modified to support testing an unimplemented method.
# On the server side, the generated code needs to be removed so the server has no
# knowledge of it. Client code requires no modification, since it is required to call
# the unimplemented method.
(cd "${CURRENT_SCRIPT_DIR}" && patch -p3 < unimplemented_call.patch)
