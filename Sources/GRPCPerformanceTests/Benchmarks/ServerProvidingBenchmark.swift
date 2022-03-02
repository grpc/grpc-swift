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

class ServerProvidingBenchmark: Benchmark {
  private let providers: [CallHandlerProvider]
  private let threadCount: Int
  private let useNIOTSIfAvailable: Bool
  private let useTLS: Bool
  private var group: EventLoopGroup!
  private(set) var server: Server!

  init(
    providers: [CallHandlerProvider],
    useNIOTSIfAvailable: Bool,
    useTLS: Bool,
    threadCount: Int = 1
  ) {
    self.providers = providers
    self.useNIOTSIfAvailable = useNIOTSIfAvailable
    self.useTLS = useTLS
    self.threadCount = threadCount
  }

  func setUp() throws {
    if self.useNIOTSIfAvailable {
      self.group = PlatformSupport.makeEventLoopGroup(loopCount: self.threadCount)
    } else {
      self.group = MultiThreadedEventLoopGroup(numberOfThreads: self.threadCount)
    }

    if self.useTLS {
      #if canImport(NIOSSL)
      self.server = try Server.usingTLSBackedByNIOSSL(
        on: self.group,
        certificateChain: [SampleCertificate.server.certificate],
        privateKey: SamplePrivateKey.server
      ).withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
        .withServiceProviders(self.providers)
        .bind(host: "127.0.0.1", port: 0)
        .wait()
      #else
      fatalError("NIOSSL must be imported to use TLS")
      #endif
    } else {
      self.server = try Server.insecure(group: self.group)
        .withServiceProviders(self.providers)
        .bind(host: "127.0.0.1", port: 0)
        .wait()
    }
  }

  func tearDown() throws {
    try self.server.close().wait()
    try self.group.syncShutdownGracefully()
  }

  func run() throws -> Int {
    return 0
  }
}
