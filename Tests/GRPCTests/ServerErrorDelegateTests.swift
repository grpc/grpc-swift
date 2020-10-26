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
import EchoImplementation
import EchoModel
import Foundation
import GRPC
import Logging
import NIO
import NIOHTTP1
import XCTest

private class ServerErrorDelegateMock: ServerErrorDelegate {
  private let transformLibraryErrorHandler: (Error) -> (GRPCStatusAndTrailers?)

  init(transformLibraryErrorHandler: @escaping ((Error) -> (GRPCStatusAndTrailers?))) {
    self.transformLibraryErrorHandler = transformLibraryErrorHandler
  }

  func transformLibraryError(_ error: Error) -> GRPCStatusAndTrailers? {
    return self.transformLibraryErrorHandler(error)
  }
}

class ServerErrorDelegateTests: GRPCTestCase {
  private var channel: EmbeddedChannel!
  private var errorDelegate: ServerErrorDelegate!

  override func tearDown() {
    XCTAssertNoThrow(try self.channel.finish())
    super.tearDown()
  }

  func testTransformLibraryError_whenTransformingErrorToStatus_unary() throws {
    try self.testTransformLibraryError_whenTransformingErrorToStatus(uri: "/echo.Echo/Get")
  }

  func testTransformLibraryError_whenTransformingErrorToStatus_clientStreaming() throws {
    try self.testTransformLibraryError_whenTransformingErrorToStatus(uri: "/echo.Echo/Collect")
  }

  func testTransformLibraryError_whenTransformingErrorToStatus_serverStreaming() throws {
    try self.testTransformLibraryError_whenTransformingErrorToStatus(uri: "/echo.Echo/Expand")
  }

  func testTransformLibraryError_whenTransformingErrorToStatus_bidirectionalStreaming() throws {
    try self.testTransformLibraryError_whenTransformingErrorToStatus(uri: "/echo.Echo/Update")
  }

  private func testTransformLibraryError_whenTransformingErrorToStatus(uri: String) throws {
    self.setupChannelAndDelegate { _ in
      GRPCStatusAndTrailers(status: .init(code: .notFound, message: "some error"))
    }
    let requestHead = HTTPRequestHead(
      version: .init(major: 2, minor: 0),
      method: .POST,
      uri: uri,
      headers: ["content-type": "application/grpc"]
    )

    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.head(requestHead)))
    self.channel.pipeline.fireErrorCaught(GRPCStatus(code: .aborted, message: nil))
    // This is the head
    XCTAssertNoThrow(try self.channel.readOutbound(as: HTTPServerResponsePart.self))
    let end = try self.channel.readOutbound(as: HTTPServerResponsePart.self)

    guard case let .some(.end(headers)) = end else {
      XCTFail("Expected headers but got \(end.debugDescription)")
      return
    }

    XCTAssertEqual(headers?.first(name: "grpc-status"), "5")
    XCTAssertEqual(headers?.first(name: "grpc-message"), "some error")
  }

  func testTransformLibraryError_whenTransformingErrorToStatusAndMetadata_unary() throws {
    try self
      .testTransformLibraryError_whenTransformingErrorToStatusAndMetadata(uri: "/echo.Echo/Get")
  }

  func testTransformLibraryError_whenTransformingErrorToStatusAndMetadata_clientStreaming() throws {
    try self
      .testTransformLibraryError_whenTransformingErrorToStatusAndMetadata(uri: "/echo.Echo/Collect")
  }

  func testTransformLibraryError_whenTransformingErrorToStatusAndMetadata_serverStreaming() throws {
    try self
      .testTransformLibraryError_whenTransformingErrorToStatusAndMetadata(uri: "/echo.Echo/Expand")
  }

  func testTransformLibraryError_whenTransformingErrorToStatusAndMetadata_bidirectionalStreaming(
  ) throws {
    try self
      .testTransformLibraryError_whenTransformingErrorToStatusAndMetadata(uri: "/echo.Echo/Update")
  }

  private func testTransformLibraryError_whenTransformingErrorToStatusAndMetadata(
    uri: String
  ) throws {
    self.setupChannelAndDelegate { _ in
      GRPCStatusAndTrailers(
        status: .init(code: .notFound, message: "some error"),
        trailers: ["some-metadata": "test"]
      )
    }
    let requestHead = HTTPRequestHead(
      version: .init(major: 2, minor: 0),
      method: .POST,
      uri: uri,
      headers: ["content-type": "application/grpc"]
    )

    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.head(requestHead)))
    self.channel.pipeline.fireErrorCaught(GRPCStatus(code: .aborted, message: nil))
    // This is the head
    XCTAssertNoThrow(try self.channel.readOutbound(as: HTTPServerResponsePart.self))
    let end = try self.channel.readOutbound(as: HTTPServerResponsePart.self)

    guard case let .some(.end(headers)) = end else {
      XCTFail("Expected headers but got \(end.debugDescription)")
      return
    }

    XCTAssertEqual(headers?.first(name: "grpc-status"), "5")
    XCTAssertEqual(headers?.first(name: "grpc-message"), "some error")
    XCTAssertEqual(headers?.first(name: "some-metadata"), "test")
  }

  private func setupChannelAndDelegate(transformLibraryErrorHandler: @escaping (
    (Error)
      -> (GRPCStatusAndTrailers?)
  )) {
    let provider = EchoProvider()
    self
      .errorDelegate =
      ServerErrorDelegateMock(transformLibraryErrorHandler: transformLibraryErrorHandler)
    let handler = GRPCServerRequestRoutingHandler(
      servicesByName: [provider.serviceName: provider],
      encoding: .disabled,
      errorDelegate: self.errorDelegate,
      logger: self.logger
    )

    self.channel = EmbeddedChannel(handler: handler)
  }
}
