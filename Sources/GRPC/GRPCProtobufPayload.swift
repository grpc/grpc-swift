/*
 * Copyright 2020, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import NIO
import SwiftProtobuf

/// Provides default implementations of `GRPCPayload` for `SwiftProtobuf.Message`s.
public protocol GRPCProtobufPayload: GRPCPayload, Message {}

public extension GRPCProtobufPayload {
  init(serializedByteBuffer: inout NIO.ByteBuffer) throws {
    try self.init(contiguousBytes: serializedByteBuffer.readableBytesView)
  }

  func serialize(into buffer: inout NIO.ByteBuffer) throws {
    let data = try self.serializedData()
    buffer.writeBytes(data)
  }
}

// SwiftProtobuf ships a bunch of different messages. We'll provide conformance to them here to
// avoid having to generate the conformance.
//
// See: https://github.com/grpc/grpc-swift/issues/801

extension Google_Protobuf_Any: GRPCProtobufPayload {}
extension Google_Protobuf_Api: GRPCProtobufPayload {}
extension Google_Protobuf_BoolValue: GRPCProtobufPayload {}
extension Google_Protobuf_BytesValue: GRPCProtobufPayload {}
extension Google_Protobuf_DescriptorProto: GRPCProtobufPayload {}
extension Google_Protobuf_DoubleValue: GRPCProtobufPayload {}
extension Google_Protobuf_Duration: GRPCProtobufPayload {}
extension Google_Protobuf_Empty: GRPCProtobufPayload {}
extension Google_Protobuf_Enum: GRPCProtobufPayload {}
extension Google_Protobuf_EnumDescriptorProto: GRPCProtobufPayload {}
extension Google_Protobuf_EnumOptions: GRPCProtobufPayload {}
extension Google_Protobuf_EnumValue: GRPCProtobufPayload {}
extension Google_Protobuf_EnumValueDescriptorProto: GRPCProtobufPayload {}
extension Google_Protobuf_EnumValueOptions: GRPCProtobufPayload {}
extension Google_Protobuf_ExtensionRangeOptions: GRPCProtobufPayload {}
extension Google_Protobuf_Field: GRPCProtobufPayload {}
extension Google_Protobuf_FieldDescriptorProto: GRPCProtobufPayload {}
extension Google_Protobuf_FieldMask: GRPCProtobufPayload {}
extension Google_Protobuf_FieldOptions: GRPCProtobufPayload {}
extension Google_Protobuf_FileDescriptorProto: GRPCProtobufPayload {}
extension Google_Protobuf_FileDescriptorSet: GRPCProtobufPayload {}
extension Google_Protobuf_FileOptions: GRPCProtobufPayload {}
extension Google_Protobuf_FloatValue: GRPCProtobufPayload {}
extension Google_Protobuf_GeneratedCodeInfo: GRPCProtobufPayload {}
extension Google_Protobuf_Int32Value: GRPCProtobufPayload {}
extension Google_Protobuf_Int64Value: GRPCProtobufPayload {}
extension Google_Protobuf_ListValue: GRPCProtobufPayload {}
extension Google_Protobuf_MessageOptions: GRPCProtobufPayload {}
extension Google_Protobuf_Method: GRPCProtobufPayload {}
extension Google_Protobuf_MethodDescriptorProto: GRPCProtobufPayload {}
extension Google_Protobuf_MethodOptions: GRPCProtobufPayload {}
extension Google_Protobuf_Mixin: GRPCProtobufPayload {}
extension Google_Protobuf_OneofDescriptorProto: GRPCProtobufPayload {}
extension Google_Protobuf_OneofOptions: GRPCProtobufPayload {}
extension Google_Protobuf_Option: GRPCProtobufPayload {}
extension Google_Protobuf_ServiceDescriptorProto: GRPCProtobufPayload {}
extension Google_Protobuf_ServiceOptions: GRPCProtobufPayload {}
extension Google_Protobuf_SourceCodeInfo: GRPCProtobufPayload {}
extension Google_Protobuf_SourceContext: GRPCProtobufPayload {}
extension Google_Protobuf_StringValue: GRPCProtobufPayload {}
extension Google_Protobuf_Struct: GRPCProtobufPayload {}
extension Google_Protobuf_Timestamp: GRPCProtobufPayload {}
extension Google_Protobuf_Type: GRPCProtobufPayload {}
extension Google_Protobuf_UInt32Value: GRPCProtobufPayload {}
extension Google_Protobuf_UInt64Value: GRPCProtobufPayload {}
extension Google_Protobuf_UninterpretedOption: GRPCProtobufPayload {}
extension Google_Protobuf_Value: GRPCProtobufPayload {}
