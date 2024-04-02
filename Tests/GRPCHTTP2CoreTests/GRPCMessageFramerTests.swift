/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

import NIOCore
import NIOEmbedded
import XCTest

@testable import GRPCHTTP2Core

final class GRPCMessageFramerTests: XCTestCase {
  func testSingleWrite() throws {
    var framer = GRPCMessageFramer()
    framer.append(Array(repeating: 42, count: 128), promise: nil)

    var buffer = try XCTUnwrap(framer.next()).bytes
    let (compressed, length) = try XCTUnwrap(buffer.readMessageHeader())
    XCTAssertFalse(compressed)
    XCTAssertEqual(length, 128)
    XCTAssertEqual(buffer.readSlice(length: Int(length)), ByteBuffer(repeating: 42, count: 128))
    XCTAssertEqual(buffer.readableBytes, 0)

    // No more bufers.
    XCTAssertNil(try framer.next())
  }

  private func testSingleWrite(compressionMethod: Zlib.Method) throws {
    let compressor = Zlib.Compressor(method: compressionMethod)
    defer {
      compressor.end()
    }
    var framer = GRPCMessageFramer()

    let message = [UInt8](repeating: 42, count: 128)
    framer.append(message, promise: nil)

    var buffer = ByteBuffer()
    let testCompressor = Zlib.Compressor(method: compressionMethod)
    let compressedSize = try testCompressor.compress(message, into: &buffer)
    let compressedMessage = buffer.readSlice(length: compressedSize)
    defer {
      testCompressor.end()
    }

    buffer = try XCTUnwrap(framer.next(compressor: compressor)).bytes
    let (compressed, length) = try XCTUnwrap(buffer.readMessageHeader())
    XCTAssertTrue(compressed)
    XCTAssertEqual(length, UInt32(compressedSize))
    XCTAssertEqual(buffer.readSlice(length: Int(length)), compressedMessage)
    XCTAssertEqual(buffer.readableBytes, 0)

    // No more bufers.
    XCTAssertNil(try framer.next())
  }

  func testSingleWriteDeflateCompressed() throws {
    try self.testSingleWrite(compressionMethod: .deflate)
  }

  func testSingleWriteGZIPCompressed() throws {
    try self.testSingleWrite(compressionMethod: .gzip)
  }

  func testMultipleWrites() throws {
    var framer = GRPCMessageFramer()
    let eventLoop = EmbeddedEventLoop()

    // Create 100 messages and link a different promise with each of them.
    let messagesCount = 100
    var promises = [EventLoopPromise<Void>]()
    promises.reserveCapacity(messagesCount)
    for _ in 0 ..< messagesCount {
      let promise = eventLoop.makePromise(of: Void.self)
      promises.append(promise)
      framer.append(Array(repeating: 42, count: 128), promise: promise)
    }

    let nextFrame = try XCTUnwrap(framer.next())

    // Assert the messages have been framed all together in the same frame.
    var buffer = nextFrame.bytes
    for _ in 0 ..< messagesCount {
      let (compressed, length) = try XCTUnwrap(buffer.readMessageHeader())
      XCTAssertFalse(compressed)
      XCTAssertEqual(length, 128)
      XCTAssertEqual(buffer.readSlice(length: Int(length)), ByteBuffer(repeating: 42, count: 128))
    }
    XCTAssertEqual(buffer.readableBytes, 0)

    // Assert the promise returned from the framer is the promise linked to the
    // first message appended to the framer.
    let returnedPromise = nextFrame.promise
    XCTAssertEqual(returnedPromise?.futureResult, promises.first?.futureResult)

    // Succeed the returned promise to simulate a write into the channel
    // succeeding, and assert that all other promises have been chained and are
    // also succeeded as a result.
    returnedPromise?.succeed()
    XCTAssertEqual(promises.count, messagesCount)
    for promise in promises {
      try promise.futureResult.assertSuccess().wait()
    }

    // No more frames.
    XCTAssertNil(try framer.next())
  }
}

extension ByteBuffer {
  mutating func readMessageHeader() -> (Bool, UInt32)? {
    if let (compressed, length) = self.readMultipleIntegers(as: (UInt8, UInt32).self) {
      return (compressed != 0, length)
    } else {
      return nil
    }
  }
}
