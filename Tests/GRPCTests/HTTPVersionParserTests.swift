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

import NIOCore
import XCTest

@testable import GRPC

class HTTPVersionParserTests: GRPCTestCase {
  private let preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  func testHTTP2ExactlyTheRightBytes() {
    let buffer = ByteBuffer(string: self.preface)
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP2ConnectionPreface(buffer), .accepted)
  }

  func testHTTP2TheRightBytesAndMore() {
    var buffer = ByteBuffer(string: self.preface)
    buffer.writeRepeatingByte(42, count: 1024)
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP2ConnectionPreface(buffer), .accepted)
  }

  func testHTTP2NoBytes() {
    let empty = ByteBuffer()
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP2ConnectionPreface(empty), .notEnoughBytes)
  }

  func testHTTP2NotEnoughBytes() {
    var buffer = ByteBuffer(string: self.preface)
    buffer.moveWriterIndex(to: buffer.writerIndex - 1)
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP2ConnectionPreface(buffer), .notEnoughBytes)
  }

  func testHTTP2EnoughOfTheWrongBytes() {
    let buffer = ByteBuffer(string: String(self.preface.reversed()))
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP2ConnectionPreface(buffer), .rejected)
  }

  func testHTTP1RequestLine() {
    let buffer = ByteBuffer(staticString: "GET https://grpc.io/index.html HTTP/1.1\r\n")
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP1RequestLine(buffer), .accepted)
  }

  func testHTTP1RequestLineAndMore() {
    let buffer = ByteBuffer(staticString: "GET https://grpc.io/index.html HTTP/1.1\r\nMore")
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP1RequestLine(buffer), .accepted)
  }

  func testHTTP1RequestLineWithoutCRLF() {
    let buffer = ByteBuffer(staticString: "GET https://grpc.io/index.html HTTP/1.1")
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP1RequestLine(buffer), .notEnoughBytes)
  }

  func testHTTP1NoBytes() {
    let empty = ByteBuffer()
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP1RequestLine(empty), .notEnoughBytes)
  }

  func testHTTP1IncompleteRequestLine() {
    let buffer = ByteBuffer(staticString: "GET https://grpc.io/index.html")
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP1RequestLine(buffer), .notEnoughBytes)
  }

  func testHTTP1MalformedVersion() {
    let buffer = ByteBuffer(staticString: "GET https://grpc.io/index.html ptth/1.1\r\n")
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP1RequestLine(buffer), .rejected)
  }

  func testTooManyIncorrectBytes() {
    let buffer = ByteBuffer(repeating: UInt8(ascii: "\r"), count: 2048)
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP2ConnectionPreface(buffer), .rejected)
    XCTAssertEqual(HTTPVersionParser.prefixedWithHTTP1RequestLine(buffer), .rejected)
  }
}
