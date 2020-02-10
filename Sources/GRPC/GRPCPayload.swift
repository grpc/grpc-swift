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

/// A data type which may be serialized into and out from a `ByteBuffer` in order to be sent between
/// gRPC peers.
public protocol GRPCPayload {
  /// Initializes a new payload by deserializing the bytes from the given `ByteBuffer`.
  ///
  /// - Parameter serializedByteBuffer: A buffer containing the serialized bytes of this payload.
  /// - Throws: If the payload could not be deserialized from the buffer.
  init(serializedByteBuffer: inout ByteBuffer) throws

  /// Serializes the payload into the given `ByteBuffer`.
  ///
  /// - Parameter buffer: The buffer to write the serialized payload into.
  /// - Throws: If the payload could not be serialized.
  /// - Important: Implementers must *NOT* clear or read bytes from `buffer`.
  func serialize(into buffer: inout ByteBuffer) throws
}
