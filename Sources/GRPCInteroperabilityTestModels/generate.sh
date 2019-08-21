#!/bin/sh

PLUGIN_SWIFT=../../.build/debug/protoc-gen-swift
PLUGIN_SWIFTGRPC=../../.build/debug/protoc-gen-swiftgrpc
PROTO="src/proto/grpc/testing/test.proto"

OUTPUT="Generated"
FILE_NAMING="DropPath"
VISIBILITY="Public"

protoc "src/proto/grpc/testing/test.proto" \
  --plugin=${PLUGIN_SWIFT} \
  --plugin=${PLUGIN_SWIFTGRPC} \
  --swift_out=${OUTPUT} \
  --swift_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY} \
  --swiftgrpc_out=${OUTPUT} \
  --swiftgrpc_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY}

protoc "src/proto/grpc/testing/empty.proto" \
  --plugin=${PLUGIN_SWIFT} \
  --plugin=${PLUGIN_SWIFTGRPC} \
  --swift_out=${OUTPUT} \
  --swift_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY} \
  --swiftgrpc_out=${OUTPUT} \
  --swiftgrpc_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY}

protoc "src/proto/grpc/testing/messages.proto" \
  --plugin=${PLUGIN_SWIFT} \
  --plugin=${PLUGIN_SWIFTGRPC} \
  --swift_out=${OUTPUT} \
  --swift_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY} \
  --swiftgrpc_out=${OUTPUT} \
  --swiftgrpc_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY}

echo "The generated code needs to be modified to support testing an unimplemented method."
echo "On the server side, the generated code needs to be removed so the server has no"
echo "knowledge of it. Client code requires no modification, since it is required to call"
echo "the unimplemented method.\n"

echo "In the generated 'Grpc_Testing_TestServiceProvider' protocol code in ${OUTPUT}/test.grpc.swift:"
echo "1. remove 'unimplementedCall(request:context:)'"
echo "2. remove the 'UnimplementedCall' case from 'handleMethod(:request:serverHandler:GRPCChannelHandler:channel:errorDelegate)'"
