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
import GRPC
import Logging
import NIO
import NIOHPACK
import NIOHTTP2

final class EmbeddedServerUnaryBenchmark: Benchmark {
  private let count: Int
  private let text: String
  private let providers: [Substring: CallHandlerProvider]
  private let logger: Logger

  static let headersPayload = HTTP2Frame.FramePayload.headers(.init(headers: [
    ":path": "/echo.Echo/Get",
    ":method": "POST",
    "content-type": "application/grpc",
  ]))

  private var requestPayload: HTTP2Frame.FramePayload!

  init(count: Int, text: String) {
    self.count = count
    self.text = text

    let echo = EchoProvider()
    self.providers = [echo.serviceName: echo]
    self.logger = Logger(label: "noop") { _ in
      SwiftLogNoOpLogHandler()
    }
  }

  func setUp() throws {
    var buffer = ByteBuffer()
    let serialized = try Echo_EchoRequest.with { $0.text = self.text }.serializedData()
    buffer.reserveCapacity(5 + serialized.count)
    buffer.writeInteger(UInt8(0)) // not compressed
    buffer.writeInteger(UInt32(serialized.count)) // length
    buffer.writeData(serialized)
    self.requestPayload = .data(.init(data: .byteBuffer(buffer), endStream: true))
  }

  func tearDown() throws {}

  func run() throws {
    for _ in 0 ..< self.count {
      let channel = EmbeddedChannel()
      try channel._configureForEmbeddedServerTest(
        servicesByName: self.providers,
        encoding: .disabled,
        normalizeHeaders: true,
        logger: self.logger
      ).wait()

      try channel.writeInbound(Self.headersPayload)
      try channel.writeInbound(self.requestPayload)

      // headers, data, trailers
      _ = try channel.readOutbound(as: HTTP2Frame.FramePayload.self)
      _ = try channel.readOutbound(as: HTTP2Frame.FramePayload.self)
      _ = try channel.readOutbound(as: HTTP2Frame.FramePayload.self)
    }
  }
}
