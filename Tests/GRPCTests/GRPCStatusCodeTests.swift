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
@testable import GRPC
import EchoModel
import NIO
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import XCTest
import Logging

class GRPCStatusCodeTests: GRPCTestCase {
  var channel: EmbeddedChannel!
  var status: EventLoopFuture<GRPCStatus>!

  override func setUp() {
    super.setUp()

    let logger = Logger(label: "io.grpc.testing")

    self.channel = EmbeddedChannel()
    let statusPromise = self.channel.eventLoop.makePromise(of: GRPCStatus.self)
    self.status = statusPromise.futureResult

    try! self.channel.pipeline.addHandlers([
      _GRPCClientChannelHandler<Echo_EchoRequest, Echo_EchoResponse>(streamID: .init(1), callType: .unary, logger: logger),
      GRPCClientUnaryResponseChannelHandler<Echo_EchoResponse>(
        initialMetadataPromise: channel.eventLoop.makePromise(),
        trailingMetadataPromise: channel.eventLoop.makePromise(),
        responsePromise: channel.eventLoop.makePromise(),
        statusPromise: statusPromise,
        errorDelegate: nil,
        timeout: .infinite,
        logger: logger
      )
    ]).wait()
  }

  override func tearDown() {
  }

  func headersFrame(status: HTTPResponseStatus) -> HTTP2Frame {
    let headers: HPACKHeaders = [":status": "\(status.code)"]
    return .init(streamID: .init(1), payload: .headers(.init(headers: headers)))
  }

  func sendRequestHead() {
    let requestHead = _GRPCRequestHead(
      method: "POST",
      scheme: "http",
      path: "/foo/bar",
      host: "localhost",
      timeout: .infinite,
      customMetadata: [:]
    )
    let clientRequestHead: _GRPCClientRequestPart<Echo_EchoRequest> = .head(requestHead)
    XCTAssertNoThrow(try self.channel.writeOutbound(clientRequestHead))
  }

  func doTestResponseStatus(_ status: HTTPResponseStatus, expected: GRPCStatus.Code) throws {
    // Send the request head so we're in a valid state to receive headers.
    self.sendRequestHead()
    XCTAssertNoThrow(try self.channel.writeInbound(self.headersFrame(status: status)))
    XCTAssertEqual(try self.status.map { $0.code }.wait(), expected)
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
    let statusCode: GRPCStatus.Code = .doNotUse
    let statusMessage = "Not the HTTP error phrase"

    let headers: HPACKHeaders = [
      ":status": "\(HTTPResponseStatus.imATeapot.code)",
      GRPCHeaderName.statusCode: "\(statusCode.rawValue)",
      GRPCHeaderName.statusMessage: statusMessage
    ]

    self.sendRequestHead()
    let headerFrame = HTTP2Frame(streamID: .init(1), payload: .headers(.init(headers: headers)))
    XCTAssertNoThrow(try self.channel.writeInbound(headerFrame))
    let status = try self.status.wait()

    XCTAssertEqual(status.code, statusCode)
    XCTAssertEqual(status.message, statusMessage)
  }
}
