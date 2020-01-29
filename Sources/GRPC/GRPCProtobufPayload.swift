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

/// GRPCProtobufPayload which allows Protobuf Messages to be passed into the library
public protocol GRPCProtobufPayload: GRPCPayload, Message {}

public extension GRPCProtobufPayload {
  
  /// Initializer that confirms the type Message to GRPCPayload by accessing the data
  /// in the buffer into a message
  init(serializedByteBuffer: inout NIO.ByteBuffer) throws {
    try self.init(serializedData: serializedByteBuffer.readData(length: serializedByteBuffer.readableBytes)!)
  }

  /// Serializes the Message into ByteBuffer
  func serialize(into buffer: inout NIO.ByteBuffer) throws {
    let data = try self.serializedData()
    buffer.writeBytes(data)
  }
}
