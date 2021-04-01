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
import GRPC
import NIO

class UnaryPingPongBenchmark: Benchmark {
  let rpcs: Int
  let request: Echo_EchoRequest

  private var group: EventLoopGroup!
  private var server: Server!
  private var client: ClientConnection!

  init(rpcs: Int, request: String) {
    self.rpcs = rpcs
    self.request = .with { $0.text = request }
  }

  func setUp() throws {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.server = try makeEchoServer(group: self.group).wait()
    self.client = makeClientConnection(
      group: self.group,
      port: self.server.channel.localAddress!.port!
    )
  }

  func tearDown() throws {
    try self.client.close().wait()
    try self.server.close().wait()
    try self.group.syncShutdownGracefully()
  }

  func run() throws -> Int {
    let echo = Echo_EchoClient(channel: self.client)
    var responseLength = 0

    for _ in 0 ..< self.rpcs {
      let get = echo.get(self.request)
      let response = try get.response.wait()
      responseLength += response.text.count
    }

    return responseLength
  }
}

func run(identifier: String) {
  measure(identifier: identifier) {
    let benchmark = UnaryPingPongBenchmark(rpcs: 1000, request: "")
    return try! benchmark.runOnce()
  }
}
