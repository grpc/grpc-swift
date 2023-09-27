/*
 * Copyright 2023, gRPC Authors All rights reserved.
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
import NIOHTTP1
import XCTest

@testable import GRPC

internal final class WebCORSHandlerTests: XCTestCase {
  struct PreflightRequestSpec {
    var configuration: Server.Configuration.CORS
    var requestOrigin: Optional<String>
    var expectOrigin: Optional<String>
    var expectAllowedHeaders: [String]
    var expectAllowCredentials: Bool
    var expectMaxAge: Optional<String>
    var expectStatus: HTTPResponseStatus = .ok
  }

  func runPreflightRequestTest(spec: PreflightRequestSpec) throws {
    let channel = EmbeddedChannel(handler: WebCORSHandler(configuration: spec.configuration))

    var request = HTTPRequestHead(version: .http1_1, method: .OPTIONS, uri: "http://foo.example")
    if let origin = spec.requestOrigin {
      request.headers.add(name: "origin", value: origin)
    }
    request.headers.add(name: "access-control-request-method", value: "POST")
    try channel.writeRequestPart(.head(request))
    try channel.writeRequestPart(.end(nil))

    switch try channel.readResponsePart() {
    case let .head(response):
      XCTAssertEqual(response.version, request.version)

      if let expected = spec.expectOrigin {
        XCTAssertEqual(response.headers["access-control-allow-origin"], [expected])
      } else {
        XCTAssertFalse(response.headers.contains(name: "access-control-allow-origin"))
      }

      if spec.expectAllowedHeaders.isEmpty {
        XCTAssertFalse(response.headers.contains(name: "access-control-allow-headers"))
      } else {
        XCTAssertEqual(response.headers["access-control-allow-headers"], spec.expectAllowedHeaders)
      }

      if spec.expectAllowCredentials {
        XCTAssertEqual(response.headers["access-control-allow-credentials"], ["true"])
      } else {
        XCTAssertFalse(response.headers.contains(name: "access-control-allow-credentials"))
      }

      if let maxAge = spec.expectMaxAge {
        XCTAssertEqual(response.headers["access-control-max-age"], [maxAge])
      } else {
        XCTAssertFalse(response.headers.contains(name: "access-control-max-age"))
      }

      XCTAssertEqual(response.status, spec.expectStatus)

    case .body, .end, .none:
      XCTFail("Unexpected response part")
    }
  }

  func testOptionsPreflightAllowAllOrigins() throws {
    let spec = PreflightRequestSpec(
      configuration: .init(
        allowedOrigins: .all,
        allowedHeaders: ["x-grpc-web"],
        allowCredentialedRequests: false,
        preflightCacheExpiration: 60
      ),
      requestOrigin: "foo",
      expectOrigin: "*",
      expectAllowedHeaders: ["x-grpc-web"],
      expectAllowCredentials: false,
      expectMaxAge: "60"
    )
    try self.runPreflightRequestTest(spec: spec)
  }

  func testOptionsPreflightOriginBased() throws {
    let spec = PreflightRequestSpec(
      configuration: .init(
        allowedOrigins: .originBased,
        allowedHeaders: ["x-grpc-web"],
        allowCredentialedRequests: false,
        preflightCacheExpiration: 60
      ),
      requestOrigin: "foo",
      expectOrigin: "foo",
      expectAllowedHeaders: ["x-grpc-web"],
      expectAllowCredentials: false,
      expectMaxAge: "60"
    )
    try self.runPreflightRequestTest(spec: spec)
  }

  func testOptionsPreflightCustom() throws {
    struct Wrapper: GRPCCustomCORSAllowedOrigin {
      func check(origin: String) -> String? {
        if origin == "foo" {
          return "bar"
        } else {
          return nil
        }
      }
    }

    let spec = PreflightRequestSpec(
      configuration: .init(
        allowedOrigins: .custom(Wrapper()),
        allowedHeaders: ["x-grpc-web"],
        allowCredentialedRequests: false,
        preflightCacheExpiration: 60
      ),
      requestOrigin: "foo",
      expectOrigin: "bar",
      expectAllowedHeaders: ["x-grpc-web"],
      expectAllowCredentials: false,
      expectMaxAge: "60"
    )
    try self.runPreflightRequestTest(spec: spec)
  }

  func testOptionsPreflightAllowSomeOrigins() throws {
    let spec = PreflightRequestSpec(
      configuration: .init(
        allowedOrigins: .only(["bar", "foo"]),
        allowedHeaders: ["x-grpc-web"],
        allowCredentialedRequests: false,
        preflightCacheExpiration: 60
      ),
      requestOrigin: "foo",
      expectOrigin: "foo",
      expectAllowedHeaders: ["x-grpc-web"],
      expectAllowCredentials: false,
      expectMaxAge: "60"
    )
    try self.runPreflightRequestTest(spec: spec)
  }

  func testOptionsPreflightAllowNoHeaders() throws {
    let spec = PreflightRequestSpec(
      configuration: .init(
        allowedOrigins: .all,
        allowedHeaders: [],
        allowCredentialedRequests: false,
        preflightCacheExpiration: 60
      ),
      requestOrigin: "foo",
      expectOrigin: "*",
      expectAllowedHeaders: [],
      expectAllowCredentials: false,
      expectMaxAge: "60"
    )
    try self.runPreflightRequestTest(spec: spec)
  }

  func testOptionsPreflightNoMaxAge() throws {
    let spec = PreflightRequestSpec(
      configuration: .init(
        allowedOrigins: .all,
        allowedHeaders: [],
        allowCredentialedRequests: false,
        preflightCacheExpiration: 0
      ),
      requestOrigin: "foo",
      expectOrigin: "*",
      expectAllowedHeaders: [],
      expectAllowCredentials: false,
      expectMaxAge: nil
    )
    try self.runPreflightRequestTest(spec: spec)
  }

  func testOptionsPreflightNegativeMaxAge() throws {
    let spec = PreflightRequestSpec(
      configuration: .init(
        allowedOrigins: .all,
        allowedHeaders: [],
        allowCredentialedRequests: false,
        preflightCacheExpiration: -1
      ),
      requestOrigin: "foo",
      expectOrigin: "*",
      expectAllowedHeaders: [],
      expectAllowCredentials: false,
      expectMaxAge: nil
    )
    try self.runPreflightRequestTest(spec: spec)
  }

  func testOptionsPreflightWithCredentials() throws {
    let spec = PreflightRequestSpec(
      configuration: .init(
        allowedOrigins: .all,
        allowedHeaders: [],
        allowCredentialedRequests: true,
        preflightCacheExpiration: 60
      ),
      requestOrigin: "foo",
      expectOrigin: "*",
      expectAllowedHeaders: [],
      expectAllowCredentials: true,
      expectMaxAge: "60"
    )
    try self.runPreflightRequestTest(spec: spec)
  }

  func testOptionsPreflightWithDisallowedOrigin() throws {
    let spec = PreflightRequestSpec(
      configuration: .init(
        allowedOrigins: .only(["foo"]),
        allowedHeaders: [],
        allowCredentialedRequests: false,
        preflightCacheExpiration: 60
      ),
      requestOrigin: "bar",
      expectOrigin: nil,
      expectAllowedHeaders: [],
      expectAllowCredentials: false,
      expectMaxAge: nil,
      expectStatus: .forbidden
    )
    try self.runPreflightRequestTest(spec: spec)
  }
}

extension WebCORSHandlerTests {
  struct RegularRequestSpec {
    var configuration: Server.Configuration.CORS
    var requestOrigin: Optional<String>
    var expectOrigin: Optional<String>
    var expectAllowCredentials: Bool
  }

  func runRegularRequestTest(
    spec: RegularRequestSpec
  ) throws {
    let channel = EmbeddedChannel(handler: WebCORSHandler(configuration: spec.configuration))

    var request = HTTPRequestHead(version: .http1_1, method: .OPTIONS, uri: "http://foo.example")
    if let origin = spec.requestOrigin {
      request.headers.add(name: "origin", value: origin)
    }

    try channel.writeRequestPart(.head(request))
    try channel.writeRequestPart(.end(nil))
    XCTAssertEqual(try channel.readRequestPart(), .head(request))
    XCTAssertEqual(try channel.readRequestPart(), .end(nil))

    let response = HTTPResponseHead(version: request.version, status: .imATeapot)
    try channel.writeResponsePart(.head(response))
    try channel.writeResponsePart(.end(nil))

    switch try channel.readResponsePart() {
    case let .head(head):
      // Should not be modified.
      XCTAssertEqual(head.version, response.version)
      XCTAssertEqual(head.status, response.status)

      if let expected = spec.expectOrigin {
        XCTAssertEqual(head.headers["access-control-allow-origin"], [expected])
      } else {
        XCTAssertFalse(head.headers.contains(name: "access-control-allow-origin"))
      }

      if spec.expectAllowCredentials {
        XCTAssertEqual(head.headers["access-control-allow-credentials"], ["true"])
      } else {
        XCTAssertFalse(head.headers.contains(name: "access-control-allow-credentials"))
      }

    case .body, .end, .none:
      XCTFail("Unexpected response part")
    }

    XCTAssertEqual(try channel.readResponsePart(), .end(nil))
  }

  func testRegularRequestWithWildcardOrigin() throws {
    let spec = RegularRequestSpec(
      configuration: .init(
        allowedOrigins: .all,
        allowCredentialedRequests: false
      ),
      requestOrigin: "foo",
      expectOrigin: "*",
      expectAllowCredentials: false
    )
    try self.runRegularRequestTest(spec: spec)
  }

  func testRegularRequestWithLimitedOrigin() throws {
    let spec = RegularRequestSpec(
      configuration: .init(
        allowedOrigins: .only(["foo", "bar"]),
        allowCredentialedRequests: false
      ),
      requestOrigin: "foo",
      expectOrigin: "foo",
      expectAllowCredentials: false
    )
    try self.runRegularRequestTest(spec: spec)
  }

  func testRegularRequestWithNoOrigin() throws {
    let spec = RegularRequestSpec(
      configuration: .init(
        allowedOrigins: .all,
        allowCredentialedRequests: false
      ),
      requestOrigin: nil,
      expectOrigin: nil,
      expectAllowCredentials: false
    )
    try self.runRegularRequestTest(spec: spec)
  }

  func testRegularRequestWithCredentials() throws {
    let spec = RegularRequestSpec(
      configuration: .init(
        allowedOrigins: .all,
        allowCredentialedRequests: true
      ),
      requestOrigin: "foo",
      expectOrigin: "*",
      expectAllowCredentials: true
    )
    try self.runRegularRequestTest(spec: spec)
  }

  func testRegularRequestWithDisallowedOrigin() throws {
    let spec = RegularRequestSpec(
      configuration: .init(
        allowedOrigins: .only(["foo"]),
        allowCredentialedRequests: true
      ),
      requestOrigin: "bar",
      expectOrigin: nil,
      expectAllowCredentials: false
    )
    try self.runRegularRequestTest(spec: spec)
  }
}

extension EmbeddedChannel {
  fileprivate func writeRequestPart(_ part: HTTPServerRequestPart) throws {
    try self.writeInbound(part)
  }

  fileprivate func readRequestPart() throws -> HTTPServerRequestPart? {
    try self.readInbound()
  }

  fileprivate func writeResponsePart(_ part: HTTPServerResponsePart) throws {
    try self.writeOutbound(part)
  }

  fileprivate func readResponsePart() throws -> HTTPServerResponsePart? {
    try self.readOutbound()
  }
}
