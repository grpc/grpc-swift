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
import Logging
import NIOCore
import NIOEmbedded
import NIOHPACK
import NIOHTTP2

final class EmbeddedServerChildChannelBenchmark: Benchmark {
  private let text: String
  private let providers: [Substring: CallHandlerProvider]
  private let logger: Logger
  private let mode: Mode

  enum Mode {
    case unary(rpcs: Int)
    case clientStreaming(rpcs: Int, requestsPerRPC: Int)
    case serverStreaming(rpcs: Int, responsesPerRPC: Int)
    case bidirectional(rpcs: Int, requestsPerRPC: Int)

    var method: String {
      switch self {
      case .unary:
        return "Get"
      case .clientStreaming:
        return "Collect"
      case .serverStreaming:
        return "Expand"
      case .bidirectional:
        return "Update"
      }
    }
  }

  static func makeHeadersPayload(method: String) -> HTTP2Frame.FramePayload {
    return .headers(
      .init(headers: [
        ":path": "/echo.Echo/\(method)",
        ":method": "POST",
        "content-type": "application/grpc",
      ])
    )
  }

  private var headersPayload: HTTP2Frame.FramePayload!
  private var requestPayload: HTTP2Frame.FramePayload!
  private var requestPayloadWithEndStream: HTTP2Frame.FramePayload!

  private func makeChannel() throws -> EmbeddedChannel {
    let channel = EmbeddedChannel()
    try channel._configureForEmbeddedServerTest(
      servicesByName: self.providers,
      encoding: .disabled,
      normalizeHeaders: true,
      logger: self.logger
    ).wait()
    return channel
  }

  init(mode: Mode, text: String) {
    self.mode = mode
    self.text = text

    let echo = MinimalEchoProvider()
    self.providers = [echo.serviceName: echo]
    self.logger = Logger(label: "noop") { _ in
      SwiftLogNoOpLogHandler()
    }
  }

  func setUp() throws {
    var buffer = ByteBuffer()
    let requestText: String

    switch self.mode {
    case .unary, .clientStreaming, .bidirectional:
      requestText = self.text
    case let .serverStreaming(_, responsesPerRPC):
      // For server streaming the request is split on spaces. We'll build up a request based on text
      // and the number of responses we want.
      var text = String()
      text.reserveCapacity((self.text.count + 1) * responsesPerRPC)
      for _ in 0 ..< responsesPerRPC {
        text.append(self.text)
        text.append(" ")
      }
      requestText = text
    }

    let serialized = try Echo_EchoRequest.with { $0.text = requestText }.serializedData()
    buffer.reserveCapacity(5 + serialized.count)
    buffer.writeInteger(UInt8(0))  // not compressed
    buffer.writeInteger(UInt32(serialized.count))  // length
    buffer.writeData(serialized)

    self.requestPayload = .data(.init(data: .byteBuffer(buffer), endStream: false))
    self.requestPayloadWithEndStream = .data(.init(data: .byteBuffer(buffer), endStream: true))
    self.headersPayload = Self.makeHeadersPayload(method: self.mode.method)
  }

  func tearDown() throws {}

  func run() throws -> Int {
    switch self.mode {
    case let .unary(rpcs):
      return try self.run(rpcs: rpcs, requestsPerRPC: 1)
    case let .clientStreaming(rpcs, requestsPerRPC):
      return try self.run(rpcs: rpcs, requestsPerRPC: requestsPerRPC)
    case let .serverStreaming(rpcs, _):
      return try self.run(rpcs: rpcs, requestsPerRPC: 1)
    case let .bidirectional(rpcs, requestsPerRPC):
      return try self.run(rpcs: rpcs, requestsPerRPC: requestsPerRPC)
    }
  }

  func run(rpcs: Int, requestsPerRPC: Int) throws -> Int {
    var messages = 0
    for _ in 0 ..< rpcs {
      let channel = try self.makeChannel()
      try channel.writeInbound(self.headersPayload)
      for _ in 0 ..< (requestsPerRPC - 1) {
        messages += 1
        try channel.writeInbound(self.requestPayload)
      }
      messages += 1
      try channel.writeInbound(self.requestPayloadWithEndStream)

      while try channel.readOutbound(as: HTTP2Frame.FramePayload.self) != nil {
        ()
      }

      _ = try channel.finish()
    }

    return messages
  }
}
