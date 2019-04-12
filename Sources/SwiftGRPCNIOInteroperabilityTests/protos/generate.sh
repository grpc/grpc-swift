#!/bin/sh

PLUGIN_SWIFT=../../../../protoc-gen-swift
PLUGIN_SWIFTGRPC=../../../../protoc-gen-swiftgrpc
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
  --swiftgrpc_opt=NIO=true,FileNaming=${FILE_NAMING},Visibility=${VISIBILITY}

protoc "src/proto/grpc/testing/empty.proto" \
  --plugin=${PLUGIN_SWIFT} \
  --plugin=${PLUGIN_SWIFTGRPC} \
  --swift_out=${OUTPUT} \
  --swift_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY} \
  --swiftgrpc_out=${OUTPUT} \
  --swiftgrpc_opt=NIO=true,FileNaming=${FILE_NAMING},Visibility=${VISIBILITY}

protoc "src/proto/grpc/testing/messages.proto" \
  --plugin=${PLUGIN_SWIFT} \
  --plugin=${PLUGIN_SWIFTGRPC} \
  --swift_out=${OUTPUT} \
  --swift_opt=FileNaming=${FILE_NAMING},Visibility=${VISIBILITY} \
  --swiftgrpc_out=${OUTPUT} \
  --swiftgrpc_opt=NIO=true,FileNaming=${FILE_NAMING},Visibility=${VISIBILITY}

echo "The following modifications must be made to the generated 'Grpc_Testing_TestServiceProvider_NIO' protocol code in ${OUTPUT}/test.grpc.swift:"
echo "1. remove 'unimplementedCall(request:context:)'"
echo "2. remove the 'UnimplementedCall' case from 'handleMethod(:request:serverHandler:GRPCChannelHandler:channel:errorDelegate)'"
