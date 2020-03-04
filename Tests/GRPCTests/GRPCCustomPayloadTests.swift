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
import GRPC
import NIO
import XCTest

// These tests demonstrate how to use gRPC to create a service provider using your own payload type,
// or alternatively, how to avoid deserialization and just extract the raw bytes from a payload.
class GRPCCustomPayloadTests: GRPCTestCase {
  var group: EventLoopGroup!
  var server: Server!
  var client: AnyServiceClient!

  override func setUp() {
    super.setUp()
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    self.server = try! Server.insecure(group: self.group)
      .withServiceProviders([CustomPayloadProvider()])
      .bind(host: "localhost", port: 0)
      .wait()

    let channel = ClientConnection.insecure(group: self.group)
      .connect(host: "localhost", port: server.channel.localAddress!.port!)

    self.client = AnyServiceClient(channel: channel)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.client.channel.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
  }

  func testCustomPayload() throws {
    // This test demonstrates how to call a manually created bidirectional RPC with custom payloads.
    let statusExpectation = self.expectation(description: "status received")

    var responses: [CustomPayload] = []

    // Make a bidirectional stream using `CustomPayload` as the request and response type.
    // The service defined below is called "CustomPayload", and the method we call on it
    // is "AddOneAndReverseMessage"
    let rpc: BidirectionalStreamingCall<CustomPayload, CustomPayload> = self.client.makeBidirectionalStreamingCall(
      path: "/CustomPayload/AddOneAndReverseMessage",
      handler: { responses.append($0) }
    )

    // Make and send some requests:
    let requests: [CustomPayload] = [
      CustomPayload(message: "one", number: .random(in: Int64.min..<Int64.max)),
      CustomPayload(message: "two", number: .random(in: Int64.min..<Int64.max)),
      CustomPayload(message: "three", number: .random(in: Int64.min..<Int64.max))
    ]
    rpc.sendMessages(requests, promise: nil)
    rpc.sendEnd(promise: nil)

    // Wait for the RPC to finish before comparing responses.
    rpc.status.map { $0.code }.assertEqual(.ok, fulfill: statusExpectation)
    self.wait(for: [statusExpectation], timeout: 1.0)

    // Are the responses as expected?
    let expected = requests.map { request in
      CustomPayload(message: String(request.message.reversed()), number: request.number + 1)
    }
    XCTAssertEqual(responses, expected)
  }

  func testNoDeserializationOnTheClient() throws {
    // This test demonstrates how to skip the deserialization step on the client. It isn't necessary
    // to use a custom service provider to do this, although we do here.
    let statusExpectation = self.expectation(description: "status received")

    var responses: [IdentityPayload] = []
    // Here we use `IdentityPayload` for our response type: we define it below such that it does
    // not deserialize the bytes provided to it by gRPC.
    let rpc: BidirectionalStreamingCall<CustomPayload, IdentityPayload> = self.client.makeBidirectionalStreamingCall(
      path: "/CustomPayload/AddOneAndReverseMessage",
      handler: { responses.append($0) }
    )

    let request = CustomPayload(message: "message", number: 42)
    rpc.sendMessage(request, promise: nil)
    rpc.sendEnd(promise: nil)

    // Wait for the RPC to finish before comparing responses.
    rpc.status.map { $0.code }.assertEqual(.ok, fulfill: statusExpectation)
    self.wait(for: [statusExpectation], timeout: 1.0)

    guard var response = responses.first?.buffer else {
      XCTFail("RPC completed without a response")
      return
    }

    // We just took the raw bytes from the payload: we can still decode it because we know the
    // server returned a serialized `CustomPayload`.
    let actual = try CustomPayload(serializedByteBuffer: &response)
    XCTAssertEqual(actual.message, "egassem")
    XCTAssertEqual(actual.number, 43)
  }
}

// MARK: Custom Payload Service

fileprivate class CustomPayloadProvider: CallHandlerProvider {
  var serviceName: String = "CustomPayload"

  // Bidirectional RPC which returns a new `CustomPayload` for each `CustomPayload` received.
  // The returned payloads have their `message` reversed and their `number` incremented by one.
  fileprivate func addOneAndReverseMessage(
    context: StreamingResponseCallContext<CustomPayload>
  ) -> EventLoopFuture<(StreamEvent<CustomPayload>) -> Void> {
    return context.eventLoop.makeSucceededFuture({ event in
      switch event {
      case .message(let payload):
        let response = CustomPayload(
          message: String(payload.message.reversed()),
          number: payload.number + 1
        )
        _ = context.sendResponse(response)

      case .end:
        context.statusPromise.succeed(.ok)
      }
    })
  }

  func handleMethod(_ methodName: String, callHandlerContext: CallHandlerContext) -> GRPCCallHandler? {
    switch methodName {
    case "AddOneAndReverseMessage":
      return BidirectionalStreamingCallHandler<CustomPayload, CustomPayload>(callHandlerContext: callHandlerContext) { context in
        return self.addOneAndReverseMessage(context: context)
      }

    default:
      return nil
    }
  }
}

fileprivate struct IdentityPayload: GRPCPayload {
  var buffer: ByteBuffer

  init(serializedByteBuffer: inout ByteBuffer) throws {
    self.buffer = serializedByteBuffer
  }

  func serialize(into buffer: inout ByteBuffer) throws {
    // This will never be called, however, it could be implemented as a direct copy of the bytes
    // we hold, e.g.:
    //
    //   var copy = self.buffer
    //   buffer.writeBuffer(&copy)
    fatalError("Unimplemented")
  }
}

/// A toy custom payload which holds a `String` and an `Int64`.
///
/// The payload is serialized as:
/// - the `UInt32` encoded length of the message,
/// - the UTF-8 encoded bytes of the message, and
/// - the `Int64` bytes of the number.
fileprivate struct CustomPayload: GRPCPayload, Equatable {
  var message: String
  var number: Int64

  init(message: String, number: Int64) {
    self.message = message
    self.number = number
  }

  init(serializedByteBuffer: inout ByteBuffer) throws {
    guard let messageLength = serializedByteBuffer.readInteger(as: UInt32.self),
      let message = serializedByteBuffer.readString(length: Int(messageLength)),
      let number = serializedByteBuffer.readInteger(as: Int64.self) else {
        throw GRPCError.DeserializationFailure()
    }

    self.message = message
    self.number = number
  }

  func serialize(into buffer: inout ByteBuffer) throws {
    buffer.writeInteger(UInt32(self.message.count))
    buffer.writeString(self.message)
    buffer.writeInteger(self.number)
  }
}
