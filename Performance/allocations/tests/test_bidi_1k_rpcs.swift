/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import Dispatch
import GRPC
import NIO

class BidiPingPongBenchmark: Benchmark {
  let rpcs: Int
  let requests: Int
  let request: Echo_EchoRequest
  let channelKind: ChannelKind

  private var group: EventLoopGroup!
  private var server: Server!
  private var channel: GRPCChannel!

  init(rpcs: Int, requests: Int, request: String, channelKind: ChannelKind) {
    self.rpcs = rpcs
    self.requests = requests
    self.request = .with { $0.text = request }
    self.channelKind = channelKind
  }

  func setUp() throws {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.server = try makeEchoServer(group: self.group).wait()
    self.channel = self.channelKind.makeChannel(
      group: self.group,
      port: self.server.channel.localAddress!.port!
    )
  }

  func tearDown() throws {
    try self.channel.close().wait()
    try self.server.close().wait()
    try self.group.syncShutdownGracefully()
  }

  func run() throws -> Int {
    let echo = Echo_EchoClient(channel: self.channel)
    var statusCodeSum = 0

    // We'll use this semaphore to make sure we're ping-ponging request-response
    // pairs on the RPC. Doing so makes the number of allocations much more
    // stable.
    let waiter = DispatchSemaphore(value: 1)

    for _ in 0 ..< self.rpcs {
      let update = echo.update { _ in
        waiter.signal()
      }

      for _ in 0 ..< self.requests {
        waiter.wait()
        update.sendMessage(self.request, promise: nil)
      }
      waiter.wait()
      update.sendEnd(promise: nil)

      let status = try update.status.wait()
      statusCodeSum += status.code.rawValue
      waiter.signal()
    }

    return statusCodeSum
  }
}

func run(identifier: String) {
  measure(identifier: identifier + "_10_requests") {
    let benchmark = BidiPingPongBenchmark(
      rpcs: 1000,
      requests: 10,
      request: "",
      channelKind: .clientConnection
    )
    return try! benchmark.runOnce()
  }

  measure(identifier: identifier + "_10_requests_channelpool") {
    let benchmark = BidiPingPongBenchmark(
      rpcs: 1000,
      requests: 10,
      request: "",
      channelKind: .pooledChannel
    )
    return try! benchmark.runOnce()
  }

  measure(identifier: identifier + "_1_request") {
    let benchmark = BidiPingPongBenchmark(
      rpcs: 1000,
      requests: 1,
      request: "",
      channelKind: .clientConnection
    )
    return try! benchmark.runOnce()
  }

  measure(identifier: identifier + "_1_request_channelpool") {
    let benchmark = BidiPingPongBenchmark(
      rpcs: 1000,
      requests: 1,
      request: "",
      channelKind: .pooledChannel
    )
    return try! benchmark.runOnce()
  }
}
