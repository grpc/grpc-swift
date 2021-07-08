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
import EchoModel
import Foundation
@testable import GRPC
import Logging
import NIO
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import XCTest

class GRPCStatusCodeTests: GRPCTestCase {
  var channel: EmbeddedChannel!

  override func setUp() {
    super.setUp()

    let handler = GRPCClientChannelHandler(
      callType: .unary,
      maximumReceiveMessageLength: .max,
      logger: GRPCLogger(wrapping: self.logger)
    )
    self.channel = EmbeddedChannel(handler: handler)
  }

  func headersFramePayload(status: HTTPResponseStatus) -> HTTP2Frame.FramePayload {
    let headers: HPACKHeaders = [":status": "\(status.code)"]
    return .headers(.init(headers: headers))
  }

  func sendRequestHead() {
    let requestHead = _GRPCRequestHead(
      method: "POST",
      scheme: "http",
      path: "/foo/bar",
      host: "localhost",
      deadline: .distantFuture,
      customMetadata: [:],
      encoding: .disabled
    )
    let clientRequestHead: _RawGRPCClientRequestPart = .head(requestHead)
    XCTAssertNoThrow(try self.channel.writeOutbound(clientRequestHead))
  }

  func doTestResponseStatus(_ status: HTTPResponseStatus, expected: GRPCStatus.Code) throws {
    // Send the request head so we're in a valid state to receive headers.
    self.sendRequestHead()
    XCTAssertThrowsError(
      try self.channel
        .writeInbound(self.headersFramePayload(status: status))
    ) { error in
      guard let withContext = error as? GRPCError.WithContext,
        let invalidHTTPStatus = withContext.error as? GRPCError.InvalidHTTPStatus else {
        XCTFail("Unexpected error: \(error)")
        return
      }

      XCTAssertEqual(invalidHTTPStatus.makeGRPCStatus().code, expected)
    }
  }

  func testTooManyRequests() throws {
    try self.doTestResponseStatus(.tooManyRequests, expected: .unavailable)
  }

  func testBadGateway() throws {
    try self.doTestResponseStatus(.badGateway, expected: .unavailable)
  }

  func testServiceUnavailable() throws {
    try self.doTestResponseStatus(.serviceUnavailable, expected: .unavailable)
  }

  func testGatewayTimeout() throws {
    try self.doTestResponseStatus(.gatewayTimeout, expected: .unavailable)
  }

  func testBadRequest() throws {
    try self.doTestResponseStatus(.badRequest, expected: .internalError)
  }

  func testUnauthorized() throws {
    try self.doTestResponseStatus(.unauthorized, expected: .unauthenticated)
  }

  func testForbidden() throws {
    try self.doTestResponseStatus(.forbidden, expected: .permissionDenied)
  }

  func testNotFound() throws {
    try self.doTestResponseStatus(.notFound, expected: .unimplemented)
  }

  func testStatusCodeAndMessageAreRespectedForNon200Responses() throws {
    let status = GRPCStatus(code: .unknown, message: "Not the HTTP error phrase")

    let headers: HPACKHeaders = [
      ":status": "\(HTTPResponseStatus.imATeapot.code)",
      GRPCHeaderName.statusCode: "\(status.code.rawValue)",
      GRPCHeaderName.statusMessage: status.message!,
    ]

    self.sendRequestHead()
    let headerFramePayload = HTTP2Frame.FramePayload.headers(.init(headers: headers))
    XCTAssertThrowsError(try self.channel.writeInbound(headerFramePayload)) { error in
      guard let withContext = error as? GRPCError.WithContext,
        let invalidHTTPStatus = withContext.error as? GRPCError.InvalidHTTPStatusWithGRPCStatus
      else {
        XCTFail("Unexpected error: \(error)")
        return
      }
      XCTAssertEqual(invalidHTTPStatus.makeGRPCStatus(), status)
    }
  }

  func testCodeFromRawValue() {
    XCTAssertEqual(GRPCStatus.Code(rawValue: 0), .ok)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 1), .cancelled)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 2), .unknown)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 3), .invalidArgument)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 4), .deadlineExceeded)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 5), .notFound)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 6), .alreadyExists)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 7), .permissionDenied)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 8), .resourceExhausted)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 9), .failedPrecondition)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 10), .aborted)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 11), .outOfRange)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 12), .unimplemented)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 13), .internalError)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 14), .unavailable)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 15), .dataLoss)
    XCTAssertEqual(GRPCStatus.Code(rawValue: 16), .unauthenticated)

    XCTAssertNil(GRPCStatus.Code(rawValue: -1))
    XCTAssertNil(GRPCStatus.Code(rawValue: 17))
  }
}
