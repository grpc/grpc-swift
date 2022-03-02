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
import GRPC
import GRPCSampleData
import NIOCore
import NIOPosix

/// Tests unary throughput by sending requests on a single connection.
///
/// Requests are sent in batches of (up-to) 100 requests. This is due to
/// https://github.com/apple/swift-nio-http2/issues/87#issuecomment-483542401.
class Unary: ServerProvidingBenchmark {
  private let useNIOTSIfAvailable: Bool
  private let useTLS: Bool
  private var group: EventLoopGroup!
  private(set) var client: Echo_EchoClient!

  let requestCount: Int
  let requestText: String

  init(requests: Int, text: String, useNIOTSIfAvailable: Bool, useTLS: Bool) {
    self.useNIOTSIfAvailable = useNIOTSIfAvailable
    self.useTLS = useTLS
    self.requestCount = requests
    self.requestText = text
    super.init(
      providers: [MinimalEchoProvider()],
      useNIOTSIfAvailable: useNIOTSIfAvailable,
      useTLS: useTLS
    )
  }

  override func setUp() throws {
    try super.setUp()

    if self.useNIOTSIfAvailable {
      self.group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
    } else {
      self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    let channel: ClientConnection

    if self.useTLS {
      #if canImport(NIOSSL)
      channel = ClientConnection.usingTLSBackedByNIOSSL(on: self.group)
        .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
        .withTLS(serverHostnameOverride: "localhost")
        .connect(host: "127.0.0.1", port: self.server.channel.localAddress!.port!)
      #else
      fatalError("NIOSSL must be imported to use TLS")
      #endif
    } else {
      channel = ClientConnection.insecure(group: self.group)
        .connect(host: "127.0.0.1", port: self.server.channel.localAddress!.port!)
    }

    self.client = .init(channel: channel)
  }

  override func run() throws -> Int {
    var messages = 0
    let batchSize = 100

    for lowerBound in stride(from: 0, to: self.requestCount, by: batchSize) {
      let upperBound = min(lowerBound + batchSize, self.requestCount)

      let requests = (lowerBound ..< upperBound).map { _ in
        client.get(Echo_EchoRequest.with { $0.text = self.requestText }).response
      }

      messages += requests.count
      try EventLoopFuture.andAllSucceed(requests, on: self.group.next()).wait()
    }

    return messages
  }

  override func tearDown() throws {
    try self.client.channel.close().wait()
    try self.group.syncShutdownGracefully()
    try super.tearDown()
  }
}

/// Tests bidirectional throughput by sending requests over a single stream.
class Bidi: Unary {
  let batchSize: Int

  init(requests: Int, text: String, batchSize: Int, useNIOTSIfAvailable: Bool, useTLS: Bool) {
    self.batchSize = batchSize
    super.init(
      requests: requests,
      text: text,
      useNIOTSIfAvailable: useNIOTSIfAvailable,
      useTLS: useTLS
    )
  }

  override func run() throws -> Int {
    var messages = 0
    let update = self.client.update { _ in }

    for _ in stride(from: 0, to: self.requestCount, by: self.batchSize) {
      let batch = (0 ..< self.batchSize).map { _ in
        Echo_EchoRequest.with { $0.text = self.requestText }
      }
      messages += batch.count
      update.sendMessages(batch, promise: nil)
    }
    update.sendEnd(promise: nil)

    _ = try update.status.wait()
    return messages
  }
}
