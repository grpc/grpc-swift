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
import NIO
import GRPC
import Foundation

class PercentEncoding: Benchmark {
  let message: String
  let allocator = ByteBufferAllocator()

  let iterations: Int

  init(iterations: Int, requiresEncoding: Bool) {
    self.iterations = iterations
    if requiresEncoding {
      // The message is used in the interop-tests.
      self.message = "\t\ntest with whitespace\r\nand Unicode BMP ☺ and non-BMP 😈\t\n"
    } else {
      // The message above is 62 bytes long.
      self.message = String(repeating: "a", count: 62)
     }
  }

  func setUp() throws {
  }

  func tearDown() throws {
  }

  func run() throws {
    var totalLength: Int = 0

    for _ in 0..<self.iterations {
      var buffer = self.allocator.buffer(capacity: 0)

      let marshalled = GRPCStatusMessageMarshaller.marshall(self.message)!
      let length = buffer.writeString(marshalled)
      let unmarshalled = GRPCStatusMessageMarshaller.unmarshall(buffer.readString(length: length)!)

      totalLength += unmarshalled.count
    }
  }
}
