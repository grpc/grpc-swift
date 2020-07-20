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
import XCTest
import NIO
import NIOHTTP1
import GRPC
import EchoModel
import EchoImplementation
import Logging

class GRPCServerRequestRoutingHandlerTests: GRPCTestCase {
  var channel: EmbeddedChannel!

  override func setUp() {
    super.setUp()

    let provider = EchoProvider()
    let handler = GRPCServerRequestRoutingHandler(
      servicesByName: [provider.serviceName: provider],
      encoding: .disabled,
      errorDelegate: nil,
      logger: self.logger
    )

    self.channel = EmbeddedChannel(handler: handler)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.channel.finish())
    super.tearDown()
  }

  func testInvalidGRPCContentTypeReturnsUnsupportedMediaType() throws {
    let requestHead = HTTPRequestHead(
      version: .init(major: 2, minor: 0),
      method: .POST,
      uri: "/echo.Echo/Get",
      headers: ["content-type": "not-grpc"]
    )

    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.head(requestHead)))

    let firstResponsePart = try self.channel.readOutbound(as: HTTPServerResponsePart.self)
    switch firstResponsePart {
    case .some(.head(let head)):
      XCTAssertEqual(head.status, .unsupportedMediaType)
    default:
      XCTFail("Unexpected response part: \(String(describing: firstResponsePart))")
    }

    let secondResponsePart = try self.channel.readOutbound(as: HTTPServerResponsePart.self)
    switch secondResponsePart {
    case .some(.end(nil)):
      ()
    default:
      XCTFail("Unexpected response part: \(String(describing: secondResponsePart))")
    }
  }

  func testUnimplementedMethodReturnsUnimplementedStatus() throws {
    let requestHead = HTTPRequestHead(
      version: .init(major: 2, minor: 0),
      method: .POST,
      uri: "/foo/Bar",
      headers: ["content-type": "application/grpc"]
    )

    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.head(requestHead)))

    let firstResponsePart = try self.channel.readOutbound(as: HTTPServerResponsePart.self)
    switch firstResponsePart {
    case .some(.head(let head)):
      XCTAssertEqual(head.status, .ok)
      XCTAssertEqual(head.headers.first(name: "grpc-status"), "\(GRPCStatus.Code.unimplemented.rawValue)")
    default:
      XCTFail("Unexpected response part: \(String(describing: firstResponsePart))")
    }

    let secondResponsePart = try self.channel.readOutbound(as: HTTPServerResponsePart.self)
    switch secondResponsePart {
    case .some(.end(nil)):
      ()
    default:
      XCTFail("Unexpected response part: \(String(describing: secondResponsePart))")
    }
  }

  func testImplementedMethodReconfiguresPipeline() throws {
    let requestHead = HTTPRequestHead(
      version: .init(major: 2, minor: 0),
      method: .POST,
      uri: "/echo.Echo/Get",
      headers: ["content-type": "application/grpc"]
    )

    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.head(requestHead)))

    // The router should be removed from the pipeline.
    let router = self.channel.pipeline.handler(type: GRPCServerRequestRoutingHandler.self)
    XCTAssertThrowsError(try router.wait())

    // There should now be a unary call handler.
    let unary = self.channel.pipeline.handler(type: UnaryCallHandler<Echo_EchoRequest, Echo_EchoResponse>.self)
    XCTAssertNoThrow(try unary.wait())
  }
}
