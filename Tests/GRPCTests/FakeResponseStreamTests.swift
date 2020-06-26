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
@testable import GRPC
import EchoModel
import NIO
import NIOHPACK
import XCTest

class FakeResponseStreamTests: GRPCTestCase {
  private typealias Request = Echo_EchoRequest
  private typealias Response = Echo_EchoResponse

  private typealias ResponsePart = _GRPCClientResponsePart<Response>

  func testUnarySendMessage() {
    let unary = FakeUnaryResponse<Request, Response>()
    unary.activate()
    XCTAssertNoThrow(try unary.sendMessage(.with { $0.text = "foo"}))

    unary.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertInitialMetadata()
    }

    unary.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertMessage {
        XCTAssertEqual($0, .with { $0.text = "foo" })
      }
    }

    unary.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertTrailingMetadata()
    }

    unary.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertStatus()
    }
  }

  func testUnarySendError() {
    let unary = FakeUnaryResponse<Request, Response>()
    unary.activate()
    XCTAssertNoThrow(try unary.sendError(GRPCError.RPCNotImplemented(rpc: "uh oh!")))

    // Expect trailers and then an error.
    unary.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertTrailingMetadata()
    }

    XCTAssertThrowsError(try unary.channel.throwIfErrorCaught())
  }

  func testUnaryIgnoresExtraMessages() {
    let unary = FakeUnaryResponse<Request, Response>()
    unary.activate()
    XCTAssertNoThrow(try unary.sendError(GRPCError.RPCNotImplemented(rpc: "uh oh!")))

    // Expected.
    unary.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertTrailingMetadata()
    }
    XCTAssertThrowsError(try unary.channel.throwIfErrorCaught())

    // Send another error; this should on-op.
    XCTAssertThrowsError(try unary.sendError(GRPCError.RPCCancelledByClient())) { error in
      XCTAssertTrue(error is FakeResponseProtocolViolation)
    }
    XCTAssertNil(try unary.channel.readInbound(as: ResponsePart.self))
    XCTAssertNoThrow(try unary.channel.throwIfErrorCaught())

    // Send a message; this should on-op.
    XCTAssertThrowsError(try unary.sendMessage(.with { $0.text = "ignored" })) { error in
      XCTAssertTrue(error is FakeResponseProtocolViolation)
    }
    XCTAssertNil(try unary.channel.readInbound(as: ResponsePart.self))
    XCTAssertNoThrow(try unary.channel.throwIfErrorCaught())
  }

  func testStreamingSendMessage() {
    let streaming = FakeStreamingResponse<Request, Response>()
    streaming.activate()

    XCTAssertNoThrow(try streaming.sendMessage(.with { $0.text = "1" }))
    XCTAssertNoThrow(try streaming.sendMessage(.with { $0.text = "2" }))
    XCTAssertNoThrow(try streaming.sendMessage(.with { $0.text = "3" }))
    XCTAssertNoThrow(try streaming.sendEnd())

    streaming.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertInitialMetadata()
    }

    for expected in ["1", "2", "3"] {
      streaming.channel.verifyInbound(as: ResponsePart.self) { part in
        part.assertMessage { message in
          XCTAssertEqual(message, .with { $0.text = expected })
        }
      }
    }

    streaming.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertTrailingMetadata()
    }

    streaming.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertStatus()
    }
  }

  func testStreamingSendInitialMetadata() {
    let streaming = FakeStreamingResponse<Request, Response>()
    streaming.activate()

    XCTAssertNoThrow(try streaming.sendInitialMetadata(["foo": "bar"]))
    streaming.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertInitialMetadata { metadata in
        XCTAssertEqual(metadata, ["foo": "bar"])
      }
    }

    // This should be dropped.
    XCTAssertThrowsError(try streaming.sendInitialMetadata(["bar": "baz"])) { error in
      XCTAssertTrue(error is FakeResponseProtocolViolation)
    }

    // Trailers and status.
    XCTAssertNoThrow(try streaming.sendEnd(trailingMetadata: ["bar": "foo"]))

    streaming.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertTrailingMetadata { metadata in
        XCTAssertEqual(metadata, ["bar": "foo"])
      }
    }

    streaming.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertStatus()
    }
  }


  func streamingSendError() {
    let streaming = FakeStreamingResponse<Request, Response>()
    streaming.activate()

    XCTAssertNoThrow(try streaming.sendMessage(.with { $0.text = "1" }))
    XCTAssertNoThrow(try streaming.sendError(GRPCError.RPCCancelledByClient()))

    streaming.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertInitialMetadata()
    }

    streaming.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertMessage { message in
        XCTAssertEqual(message, .with { $0.text = "1" })
      }
    }

    streaming.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertTrailingMetadata()
    }

    XCTAssertThrowsError(try streaming.channel.throwIfErrorCaught())
  }

  func testStreamingIgnoresExtraMessages() {
    let streaming = FakeStreamingResponse<Request, Response>()
    streaming.activate()
    XCTAssertNoThrow(try streaming.sendError(GRPCError.RPCNotImplemented(rpc: "uh oh!")))

    // Expected.
    streaming.channel.verifyInbound(as: ResponsePart.self) { part in
      part.assertTrailingMetadata()
    }
    XCTAssertThrowsError(try streaming.channel.throwIfErrorCaught())

    // Send another error; this should on-op.
    XCTAssertThrowsError(try streaming.sendError(GRPCError.RPCCancelledByClient())) { error in
      XCTAssertTrue(error is FakeResponseProtocolViolation)
    }
    XCTAssertNil(try streaming.channel.readInbound(as: ResponsePart.self))
    XCTAssertNoThrow(try streaming.channel.throwIfErrorCaught())

    // Send a message; this should on-op.
    XCTAssertThrowsError(try streaming.sendMessage(.with { $0.text = "ignored" })) { error in
      XCTAssertTrue(error is FakeResponseProtocolViolation)
    }
    XCTAssertNil(try streaming.channel.readInbound(as: ResponsePart.self))
    XCTAssertNoThrow(try streaming.channel.throwIfErrorCaught())
  }
}

fileprivate extension EmbeddedChannel {
  func verifyInbound<Inbound>(as: Inbound.Type = Inbound.self, _ verify: (Inbound) -> () = { _ in }) {
    do {
      if let inbound = try self.readInbound(as: Inbound.self) {
        verify(inbound)
      } else {
        XCTFail("Nothing to read")
      }
    } catch {
      XCTFail("Unable to readInbound: \(error)")
    }
  }
}

fileprivate extension _GRPCClientResponsePart {
  func assertInitialMetadata(_ verify: (HPACKHeaders) -> () = { _ in }) {
    switch self {
    case .initialMetadata(let headers):
      verify(headers)
    default:
      XCTFail("Expected initial metadata but got: \(self)")
    }
  }

  func assertMessage(_ verify: (Response) -> () = { _ in }) {
    switch self {
    case .message(let context):
      verify(context.message)
    default:
      XCTFail("Expected message but got: \(self)")
    }
  }

  func assertTrailingMetadata(_ verify: (HPACKHeaders) -> () = { _ in }) {
    switch self {
    case .trailingMetadata(let headers):
      verify(headers)
    default:
      XCTFail("Expected trailing metadata but got: \(self)")
    }
  }

  func assertStatus(_ verify: (GRPCStatus) -> () = { _ in }) {
    switch self {
    case .status(let status):
      verify(status)
    default:
      XCTFail("Expected status but got: \(self)")
    }
  }
}
