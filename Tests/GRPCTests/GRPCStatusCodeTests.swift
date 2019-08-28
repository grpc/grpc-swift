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
import NIOHTTP1
import NIOHTTP2
import XCTest
import Logging

class GRPCStatusCodeTests: GRPCTestCase {
  var channel: EmbeddedChannel!
  var metadataPromise: EventLoopPromise<HTTPHeaders>!
  var responsePromise: EventLoopPromise<Echo_EchoResponse>!
  var statusPromise: EventLoopPromise<GRPCStatus>!

  override func setUp() {
    super.setUp()

    self.channel = EmbeddedChannel()
    self.metadataPromise = self.channel.eventLoop.makePromise()
    self.responsePromise = self.channel.eventLoop.makePromise()
    self.statusPromise = self.channel.eventLoop.makePromise()

    let requestID = UUID().uuidString
    let logger = Logger(subsystem: .clientChannelCall, metadata: [MetadataKey.requestID: "\(requestID)"])
    try! self.channel.pipeline.addHandlers([
      HTTP1ToRawGRPCClientCodec(logger: logger),
      GRPCClientCodec<Echo_EchoRequest, Echo_EchoResponse>(logger: logger),
      GRPCClientUnaryResponseChannelHandler<Echo_EchoResponse>(
        initialMetadataPromise: self.metadataPromise,
        responsePromise: self.responsePromise,
        statusPromise: self.statusPromise,
        errorDelegate: nil,
        timeout: .infinite,
        logger: logger
      )
    ]).wait()
  }

  override func tearDown() {
    self.metadataPromise.fail(GRPCError.client(.cancelledByClient))
    self.responsePromise.fail(GRPCError.client(.cancelledByClient))
    self.statusPromise.fail(GRPCError.client(.cancelledByClient))
  }

  func responseHead(code: HTTPResponseStatus, headers: HTTPHeaders = HTTPHeaders()) -> HTTPClientResponsePart {
    return .head(HTTPResponseHead(version: HTTPVersion(major: 2, minor: 0), status: code, headers: headers))
  }

  func testTooManyRequests() throws {
    XCTAssertNoThrow(try self.channel.writeInbound(self.responseHead(code: .tooManyRequests)))
    XCTAssertEqual(try statusPromise.futureResult.map { $0.code }.wait(), .unavailable)
  }

  func testBadGateway() throws {
    XCTAssertNoThrow(try self.channel.writeInbound(self.responseHead(code: .badGateway)))
    XCTAssertEqual(try statusPromise.futureResult.map { $0.code }.wait(), .unavailable)
  }

  func testServiceUnavailable() throws {
    XCTAssertNoThrow(try self.channel.writeInbound(self.responseHead(code: .serviceUnavailable)))
    XCTAssertEqual(try statusPromise.futureResult.map { $0.code }.wait(), .unavailable)
  }

  func testGatewayTimeout() throws {
    XCTAssertNoThrow(try self.channel.writeInbound(self.responseHead(code: .gatewayTimeout)))
    XCTAssertEqual(try statusPromise.futureResult.map { $0.code }.wait(), .unavailable)
  }

  func testBadRequest() throws {
    XCTAssertNoThrow(try self.channel.writeInbound(self.responseHead(code: .badRequest)))
    XCTAssertEqual(try statusPromise.futureResult.map { $0.code }.wait(), .internalError)
  }

  func testUnauthorized() throws {
    XCTAssertNoThrow(try self.channel.writeInbound(self.responseHead(code: .unauthorized)))
    XCTAssertEqual(try statusPromise.futureResult.map { $0.code }.wait(), .unauthenticated)
  }

  func testForbidden() throws {
    XCTAssertNoThrow(try self.channel.writeInbound(self.responseHead(code: .forbidden)))
    XCTAssertEqual(try statusPromise.futureResult.map { $0.code }.wait(), .permissionDenied)
  }

  func testNotFound() throws {
    XCTAssertNoThrow(try self.channel.writeInbound(self.responseHead(code: .notFound)))
    XCTAssertEqual(try statusPromise.futureResult.map { $0.code }.wait(), .unimplemented)
  }

  func testStatusCodeAndMessageAreRespectedForNon200Responses() throws {
    let statusCode: GRPCStatus.Code = .doNotUse
    let statusMessage = "Not the HTTP error phrase"

    var headers = HTTPHeaders()
    headers.add(name: GRPCHeaderName.statusCode, value: "\(statusCode.rawValue)")
    headers.add(name: GRPCHeaderName.statusMessage, value: statusMessage)

    XCTAssertNoThrow(try self.channel.writeInbound(self.responseHead(code: .imATeapot, headers: headers)))
    let status = try statusPromise.futureResult.wait()

    XCTAssertEqual(status.code, statusCode)
    XCTAssertEqual(status.message, statusMessage)
  }
}
