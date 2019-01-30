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

enum MessageCompression {
  case none

  var enabled: Bool { return false }
}

internal class LengthPrefixedMessageWriter {
  func write(allocator: ByteBufferAllocator, compression: MessageCompression, message: Data) -> ByteBuffer {
    var buffer = allocator.buffer(capacity: 5 + message.count)

    buffer.write(integer: Int8(compression.enabled ? 1 : 0))
    buffer.write(integer: UInt32(message.count))
    buffer.write(bytes: message)

    return buffer
  }
}
