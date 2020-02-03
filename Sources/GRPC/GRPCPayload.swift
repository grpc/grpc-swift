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

/// Data passed through the library is required to conform to this GRPCPayload protocol
public protocol GRPCPayload {
  
  /// Initializes a new payload object from a given `NIO.ByteBuffer`
  ///
  /// - Parameter serializedByteBuffer: A buffer containing the serialised bytes of this payload.
  /// - Throws: Should throw an error if the data wasn't serialized properly
  init(serializedByteBuffer: inout NIO.ByteBuffer) throws

  /// Serializes the payload into a `ByteBuffer`.
  ///
  /// - Parameters:
  ///   - buffer: The buffer to write the payload into.
  /// - Note: Implementers must *NOT* clear or read bytes from `buffer`.
  func serialize(into buffer: inout NIO.ByteBuffer) throws
}
