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
import NIO
import NIOHTTP2
import NIOHPACK
import GRPC
import EchoModel
import Logging

/// Tests the throughput on the client side by firing a unary request through an embedded channel
/// and writing back enough gRPC as HTTP/2 frames to get through the state machine.
///
/// This only measures the handlers in the child channel.
class EmbeddedClientThroughput: Benchmark {
  private let requestCount: Int
  private let requestText: String

  private var logger: Logger!
  private var requestHead: _GRPCRequestHead!
  private var request: Echo_EchoRequest!

  init(requests: Int, text: String) {
    self.requestCount = requests
    self.requestText = text
  }

  func setUp() throws {
    self.logger = Logger(label: "io.grpc.testing")

    self.requestHead = _GRPCRequestHead(
      method: "POST",
      scheme: "http",
      path: "/echo.Echo/Get",
      host: "localhost",
      timeout: .infinite,
      customMetadata: [:],
      encoding: .disabled
    )

    self.request = .with {
      $0.text = self.requestText
    }
  }

  func tearDown() throws {
  }

  func run() throws {
    for _ in 0..<self.requestCount {
      let channel = EmbeddedChannel()
      try channel.pipeline.addHandlers([
        _GRPCClientChannelHandler<Echo_EchoRequest, Echo_EchoResponse>(streamID: .init(1), callType: .unary, logger: self.logger),
        _UnaryRequestChannelHandler(requestHead: self.requestHead, request: .init(self.request, compressed: false))
      ]).wait()

      // Trigger the request handler.
      channel.pipeline.fireChannelActive()

      // Read out the request frames.
      var requestFrames = 0
      while let _ = try channel.readOutbound(as: HTTP2Frame.self) {
        requestFrames += 1
      }
      assert(requestFrames == 3)  // headers, data, empty data (end-stream)

      // Okay, let's build a response.

      // Required headers.
      let responseHeaders: HPACKHeaders = [
        ":status": "200",
        "content-type": "application/grpc+proto"
      ]
      let headerFrame = HTTP2Frame(streamID: .init(1), payload: .headers(.init(headers: responseHeaders)))

      // Some data.
      let response = try Echo_EchoResponse.with { $0.text = self.requestText }.serializedData()
      var buffer = channel.allocator.buffer(capacity: response.count + 5)
      buffer.writeInteger(UInt8(0))  // compression byte
      buffer.writeInteger(UInt32(response.count))
      buffer.writeBytes(response)
      let dataFrame = HTTP2Frame(streamID: .init(1), payload: .data(.init(data: .byteBuffer(buffer))))

      // Required trailers.
      let responseTrailers: HPACKHeaders = [
        "grpc-status": "0",
        "grpc-message": "ok"
      ]
      let trailersFrame = HTTP2Frame(streamID: .init(1), payload: .headers(.init(headers: responseTrailers)))

      // Now write the response frames back into the channel.
      try channel.writeInbound(headerFrame)
      try channel.writeInbound(dataFrame)
      try channel.writeInbound(trailersFrame)

      // And read them back out.
      var responseParts = 0
      while let _ = try channel.readOutbound(as: _GRPCClientResponsePart<Echo_EchoResponse>.self) {
        responseParts += 1
      }

      assert(responseParts == 4, "received \(responseParts) response parts")
    }
  }
}
