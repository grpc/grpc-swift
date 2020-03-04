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
import Foundation
import GRPC
import NIO

class ServerProvidingBenchmark: Benchmark {
  private let providers: [CallHandlerProvider]
  private let threadCount: Int
  private var group: EventLoopGroup!
  private(set) var server: Server!

  init(providers: [CallHandlerProvider], threadCount: Int = 1) {
    self.providers = providers
    self.threadCount = threadCount
  }

  func setUp() throws {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: self.threadCount)
    self.server = try Server.insecure(group: self.group)
      .withServiceProviders(self.providers)
      .bind(host: "127.0.0.1", port: 0)
      .wait()
  }

  func tearDown() throws {
    try self.server.close().wait()
    try self.group.syncShutdownGracefully()
  }

  func run() throws {
    // no-op
  }
}
