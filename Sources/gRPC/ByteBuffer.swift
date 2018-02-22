/*
 * Copyright 2016, gRPC Authors All rights reserved.
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
#if SWIFT_PACKAGE
  import CgRPC
#endif
import Foundation // for String.Encoding

/// Representation of raw data that may be sent and received using gRPC
public class ByteBuffer {
  /// Pointer to underlying C representation
  internal var underlyingByteBuffer: UnsafeMutableRawPointer!
  
  /// Creates a ByteBuffer from an underlying C representation.
  /// The ByteBuffer takes ownership of the passed-in representation.
  ///
  /// - Parameter underlyingByteBuffer: the underlying C representation
  internal init(underlyingByteBuffer: UnsafeMutableRawPointer) {
    self.underlyingByteBuffer = underlyingByteBuffer
  }
  
  /// Creates a byte buffer that contains a copy of the contents of `data`
  ///
  /// - Parameter data: the data to store in the buffer
  public init(data: Data) {
    data.withUnsafeBytes { bytes in
      underlyingByteBuffer = cgrpc_byte_buffer_create_by_copying_data(bytes, data.count)
    }
  }
  
  deinit {
    cgrpc_byte_buffer_destroy(underlyingByteBuffer)
  }
  
  /// Gets data from the contents of the ByteBuffer
  ///
  /// - Returns: data formed from the ByteBuffer contents
  public func data() -> Data? {
    var length: Int = 0
    guard let bytes = cgrpc_byte_buffer_copy_data(underlyingByteBuffer, &length) else {
      return nil
    }
    return Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes),
                count: length,
                deallocator: .free)
  }
}
