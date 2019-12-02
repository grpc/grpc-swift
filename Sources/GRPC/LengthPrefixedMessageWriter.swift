/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation
import NIO

public struct LengthPrefixedMessageWriter {
  public static let metadataLength = 5

  private let compression: CompressionMechanism

  public init(compression: CompressionMechanism) {
    precondition(compression.supported, "compression mechanism \(compression) is not supported")
    self.compression = compression
  }

  /// Writes the data into a `ByteBuffer` as a gRPC length-prefixed message.
  ///
  /// - Parameters:
  ///   - message: The serialized Protobuf message to write.
  ///   - buffer: The buffer to write the message into.
  /// - Returns: A `ByteBuffer` containing a gRPC length-prefixed message.
  /// - Precondition: `compression.supported` is `true`.
  /// - Note: See `LengthPrefixedMessageReader` for more details on the format.
  func write(_ message: Data, into buffer: inout ByteBuffer) {
    buffer.reserveCapacity(LengthPrefixedMessageWriter.metadataLength + message.count)

    //! TODO: Add compression support, use the length and compressed content.
    buffer.writeInteger(Int8(compression.requiresFlag ? 1 : 0))
    buffer.writeInteger(UInt32(message.count))
    buffer.writeBytes(message)
  }
}
