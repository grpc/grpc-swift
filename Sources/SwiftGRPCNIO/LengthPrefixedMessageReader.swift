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
import NIOHTTP1

internal class LengthPrefixedMessageReader {
  var buffer: ByteBuffer?
  var state: State = .expectingCompressedFlag
  var mode: Mode

  init(mode: Mode) {
    self.mode = mode
  }

  enum Mode { case client, server }

  enum State {
    case expectingCompressedFlag
    case expectingMessageLength
    case receivedMessageLength(UInt32)
  }

  func read(messageBuffer: inout ByteBuffer) throws -> ByteBuffer? {
    while true {
      switch state {
      case .expectingCompressedFlag:
        guard let compressionFlag: Int8 = messageBuffer.readInteger() else { return nil }

        try handleCompressionFlag(enabled: compressionFlag != 0)
        state = .expectingMessageLength

      case .expectingMessageLength:
        guard let messageLength: UInt32 = messageBuffer.readInteger() else { return nil }
        state = .receivedMessageLength(messageLength)

      case .receivedMessageLength(let messageLength):
        // We need to account for messages being spread across multiple `ByteBuffer`s so buffer them
        // into `buffer`. Note: when messages are contained within a single `ByteBuffer` we're just
        // taking a slice so don't incur any extra writes.
        guard messageBuffer.readableBytes >= messageLength else {
          let remainingBytes = messageLength - numericCast(messageBuffer.readableBytes)

          if var buffer = buffer {
            buffer.write(buffer: &messageBuffer)
            self.buffer = buffer
          } else {
            messageBuffer.reserveCapacity(numericCast(messageLength))
            self.buffer = messageBuffer
          }

          state = .receivedMessageLength(remainingBytes)
          return nil
        }

        // We know buffer.readableBytes >= messageLength, so it's okay to force unwrap here.
        var slice = messageBuffer.readSlice(length: numericCast(messageLength))!
        self.buffer?.write(buffer: &slice)
        let message = self.buffer ?? slice

        self.buffer = nil
        self.state = .expectingCompressedFlag
        return message
      }
    }
  }

  private func handleCompressionFlag(enabled: Bool) throws {
    switch mode {
    case .client:
      // TODO: handle this better; cancel the call?
      precondition(!enabled, "compression is not supported")

    case .server:
      if enabled {
        throw GRPCStatus(code: .unimplemented, message: "compression is not yet supported on the server")
      }
    }
  }
}
