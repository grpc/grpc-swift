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
import struct Foundation.Data
import GRPC
import Logging
import NIO
import NIOHPACK
import NIOHTTP2

/// Tests the throughput on the client side by firing a unary request through an embedded channel
/// and writing back enough gRPC as HTTP/2 frames to get through the state machine.
///
/// This only measures the handlers in the child channel.
class EmbeddedClientThroughput: Benchmark {
  private let requestCount: Int
  private let requestText: String
  private let maximumResponseFrameSize: Int

  private var logger: Logger!
  private var requestHead: _GRPCRequestHead!
  private var request: Echo_EchoRequest!
  private var responseDataChunks: [ByteBuffer]!

  init(requests: Int, text: String, maxResponseFrameSize: Int = .max) {
    self.requestCount = requests
    self.requestText = text
    self.maximumResponseFrameSize = maxResponseFrameSize
  }

  func setUp() throws {
    self.logger = Logger(label: "io.grpc.testing", factory: { _ in SwiftLogNoOpLogHandler() })

    self.requestHead = _GRPCRequestHead(
      method: "POST",
      scheme: "http",
      path: "/echo.Echo/Get",
      host: "localhost",
      deadline: .distantFuture,
      customMetadata: [:],
      encoding: .disabled
    )

    self.request = .with {
      $0.text = self.requestText
    }

    let response = Echo_EchoResponse.with {
      $0.text = self.requestText
    }

    let serializedResponse = try response.serializedData()
    var buffer = ByteBufferAllocator().buffer(capacity: serializedResponse.count + 5)
    buffer.writeInteger(UInt8(0)) // compression byte
    buffer.writeInteger(UInt32(serializedResponse.count))
    buffer.writeContiguousBytes(serializedResponse)

    self.responseDataChunks = []
    while buffer.readableBytes > 0,
      let slice = buffer.readSlice(length: min(maximumResponseFrameSize, buffer.readableBytes)) {
      self.responseDataChunks.append(slice)
    }
  }

  func tearDown() throws {}

  func run() throws {
    for _ in 0 ..< self.requestCount {
      let channel = EmbeddedChannel()

      try channel._configureForEmbeddedThroughputTest(
        callType: .unary,
        logger: self.logger,
        requestType: Echo_EchoRequest.self,
        responseType: Echo_EchoResponse.self
      ).wait()

      // Trigger the request handler.
      channel.pipeline.fireChannelActive()

      // Write the request parts.
      try channel.writeOutbound(_GRPCClientRequestPart<Echo_EchoRequest>.head(self.requestHead))
      try channel
        .writeOutbound(
          _GRPCClientRequestPart<Echo_EchoRequest>
            .message(.init(self.request, compressed: false))
        )
      try channel.writeOutbound(_GRPCClientRequestPart<Echo_EchoRequest>.end)

      // Read out the request frames.
      var requestFrames = 0
      while let _ = try channel.readOutbound(as: HTTP2Frame.FramePayload.self) {
        requestFrames += 1
      }
      precondition(requestFrames == 3) // headers, data, empty data (end-stream)

      // Okay, let's build a response.

      // Required headers.
      let responseHeaders: HPACKHeaders = [
        ":status": "200",
        "content-type": "application/grpc+proto",
      ]

      let headerFrame = HTTP2Frame.FramePayload.headers(.init(headers: responseHeaders))
      try channel.writeInbound(headerFrame)

      // The response data.
      for chunk in self.responseDataChunks {
        let frame = HTTP2Frame.FramePayload.data(.init(data: .byteBuffer(chunk)))
        try channel.writeInbound(frame)
      }

      // Required trailers.
      let responseTrailers: HPACKHeaders = [
        "grpc-status": "0",
        "grpc-message": "ok",
      ]
      let trailersFrame = HTTP2Frame.FramePayload.headers(.init(headers: responseTrailers))
      try channel.writeInbound(trailersFrame)

      // And read them back out.
      var responseParts = 0
      while let _ = try channel.readInbound(as: _GRPCClientResponsePart<Echo_EchoResponse>.self) {
        responseParts += 1
      }

      precondition(responseParts == 4, "received \(responseParts) response parts")
    }
  }
}
