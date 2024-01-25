/*
 * Copyright 2022, gRPC Authors All rights reserved.
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

@testable import GRPC

internal final class CoalescingLengthPrefixedMessageWriterTests: GRPCTestCase {
  private let loop = EmbeddedEventLoop()

  private func makeWriter(
    compression: CompressionAlgorithm? = .none
  ) -> CoalescingLengthPrefixedMessageWriter {
    return .init(compression: compression, allocator: .init())
  }

  private func testSingleSmallWrite(withPromise: Bool) throws {
    var writer = self.makeWriter()

    let promise = withPromise ? self.loop.makePromise(of: Void.self) : nil
    writer.append(buffer: .smallEnoughToCoalesce, compress: false, promise: promise)

    let (result, maybePromise) = try XCTUnwrap(writer.next())
    try result.assertValue { buffer in
      var buffer = buffer
      let (compressed, length) = try XCTUnwrap(buffer.readMessageHeader())
      XCTAssertFalse(compressed)
      XCTAssertEqual(length, UInt32(ByteBuffer.smallEnoughToCoalesce.readableBytes))
      XCTAssertEqual(buffer.readSlice(length: Int(length)), .smallEnoughToCoalesce)
      XCTAssertEqual(buffer.readableBytes, 0)
    }

    // No more bufers.
    XCTAssertNil(writer.next())

    if withPromise {
      XCTAssertNotNil(maybePromise)
    } else {
      XCTAssertNil(maybePromise)
    }

    // Don't leak the promise.
    maybePromise?.succeed(())
  }

  private func testMultipleSmallWrites(withPromise: Bool) throws {
    var writer = self.makeWriter()
    let messages = 100

    for _ in 0 ..< messages {
      let promise = withPromise ? self.loop.makePromise(of: Void.self) : nil
      writer.append(buffer: .smallEnoughToCoalesce, compress: false, promise: promise)
    }

    let (result, maybePromise) = try XCTUnwrap(writer.next())
    try result.assertValue { buffer in
      var buffer = buffer

      // Read all the messages.
      for _ in 0 ..< messages {
        let (compressed, length) = try XCTUnwrap(buffer.readMessageHeader())
        XCTAssertFalse(compressed)
        XCTAssertEqual(length, UInt32(ByteBuffer.smallEnoughToCoalesce.readableBytes))
        XCTAssertEqual(buffer.readSlice(length: Int(length)), .smallEnoughToCoalesce)
      }

      XCTAssertEqual(buffer.readableBytes, 0)
    }

    // No more bufers.
    XCTAssertNil(writer.next())

    if withPromise {
      XCTAssertNotNil(maybePromise)
    } else {
      XCTAssertNil(maybePromise)
    }

    // Don't leak the promise.
    maybePromise?.succeed(())
  }

  func testSingleSmallWriteWithPromise() throws {
    try self.testSingleSmallWrite(withPromise: true)
  }

  func testSingleSmallWriteWithoutPromise() throws {
    try self.testSingleSmallWrite(withPromise: false)
  }

  func testMultipleSmallWriteWithPromise() throws {
    try self.testMultipleSmallWrites(withPromise: true)
  }

  func testMultipleSmallWriteWithoutPromise() throws {
    try self.testMultipleSmallWrites(withPromise: false)
  }

  func testSingleLargeMessage() throws {
    var writer = self.makeWriter()
    writer.append(buffer: .tooBigToCoalesce, compress: false, promise: nil)

    let (result1, promise1) = try XCTUnwrap(writer.next())
    XCTAssertNil(promise1)
    try result1.assertValue { buffer in
      var buffer = buffer
      let (compress, length) = try XCTUnwrap(buffer.readMessageHeader())
      XCTAssertFalse(compress)
      XCTAssertEqual(Int(length), ByteBuffer.tooBigToCoalesce.readableBytes)
      XCTAssertEqual(buffer.readableBytes, 0)
    }

    let (result2, promise2) = try XCTUnwrap(writer.next())
    XCTAssertNil(promise2)
    result2.assertValue { buffer in
      XCTAssertEqual(buffer, .tooBigToCoalesce)
    }

    XCTAssertNil(writer.next())
  }

  func testMessagesBeforeLargeAreCoalesced() throws {
    var writer = self.makeWriter()
    // First two should be coalesced. The third should be split as two buffers.
    writer.append(buffer: .smallEnoughToCoalesce, compress: false, promise: nil)
    writer.append(buffer: .smallEnoughToCoalesce, compress: false, promise: nil)
    writer.append(buffer: .tooBigToCoalesce, compress: false, promise: nil)

    let (result1, _) = try XCTUnwrap(writer.next())
    try result1.assertValue { buffer in
      var buffer = buffer
      for _ in 0 ..< 2 {
        let (compress, length) = try XCTUnwrap(buffer.readMessageHeader())
        XCTAssertFalse(compress)
        XCTAssertEqual(Int(length), ByteBuffer.smallEnoughToCoalesce.readableBytes)
        XCTAssertEqual(buffer.readSlice(length: Int(length)), .smallEnoughToCoalesce)
      }
      XCTAssertEqual(buffer.readableBytes, 0)
    }

    let (result2, _) = try XCTUnwrap(writer.next())
    try result2.assertValue { buffer in
      var buffer = buffer
      let (compress, length) = try XCTUnwrap(buffer.readMessageHeader())
      XCTAssertFalse(compress)
      XCTAssertEqual(Int(length), ByteBuffer.tooBigToCoalesce.readableBytes)
      XCTAssertEqual(buffer.readableBytes, 0)
    }

    let (result3, _) = try XCTUnwrap(writer.next())
    result3.assertValue { buffer in
      XCTAssertEqual(buffer, .tooBigToCoalesce)
    }

    XCTAssertNil(writer.next())
  }

  func testCompressedMessagesAreAlwaysCoalesced() throws {
    var writer = self.makeWriter(compression: .gzip)
    writer.append(buffer: .smallEnoughToCoalesce, compress: false, promise: nil)
    writer.append(buffer: .tooBigToCoalesce, compress: true, promise: nil)

    let (result, _) = try XCTUnwrap(writer.next())
    try result.assertValue { buffer in
      var buffer = buffer

      let (compress1, length1) = try XCTUnwrap(buffer.readMessageHeader())
      XCTAssertFalse(compress1)
      XCTAssertEqual(Int(length1), ByteBuffer.smallEnoughToCoalesce.readableBytes)
      XCTAssertEqual(buffer.readSlice(length: Int(length1)), .smallEnoughToCoalesce)

      let (compress2, length2) = try XCTUnwrap(buffer.readMessageHeader())
      XCTAssertTrue(compress2)
      // Can't assert the length or the content, only that the length must be equal
      // to the number of remaining bytes.
      XCTAssertEqual(Int(length2), buffer.readableBytes)
    }

    XCTAssertNil(writer.next())
  }
}

extension Result {
  func assertValue(_ body: (Success) throws -> Void) rethrows {
    switch self {
    case let .success(success):
      try body(success)
    case let .failure(error):
      XCTFail("Unexpected failure: \(error)")
    }
  }
}

extension ByteBuffer {
  fileprivate static let smallEnoughToCoalesce = Self(repeating: 42, count: 128)
  fileprivate static let tooBigToCoalesce = Self(
    repeating: 42,
    count: CoalescingLengthPrefixedMessageWriter.singleBufferSizeLimit + 1
  )

  mutating func readMessageHeader() -> (Bool, UInt32)? {
    if let (compressed, length) = self.readMultipleIntegers(as: (UInt8, UInt32).self) {
      return (compressed != 0, length)
    } else {
      return nil
    }
  }
}
