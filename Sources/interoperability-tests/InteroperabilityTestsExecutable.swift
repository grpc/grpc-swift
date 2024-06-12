/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

import ArgumentParser
import GRPCCore
import GRPCHTTP2Core
import GRPCHTTP2TransportNIOPosix
import InteroperabilityTests
import NIOPosix

@main
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct InteroperabilityTestsExecutable: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    abstract: "gRPC Swift Interoperability Runner",
    subcommands: [StartServer.self, ListTests.self, RunTest.self, RunAllTests.self]
  )

  struct StartServer: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "Start the gRPC Swift interoperability test server."
    )

    @Option(help: "The port to listen on for new connections")
    var port: Int

    func run() async throws {
      var transportConfig = HTTP2ServerTransport.Posix.Config.defaults
      transportConfig.compression.enabledAlgorithms = .all
      let transport = HTTP2ServerTransport.Posix(
        address: .ipv4(host: "0.0.0.0", port: self.port),
        config: transportConfig
      )
      let server = GRPCServer(transport: transport, services: [TestService()])
      try await server.run()
    }
  }

  struct ListTests: ParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "List all interoperability test names."
    )

    func run() throws {
      for testCase in InteroperabilityTestCase.allCases {
        print(testCase.name)
      }
    }
  }

  struct RunTest: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "Runs a gRPC interoperability test using a gRPC Swift client."
    )

    @Option(help: "The host the server is running on")
    var host: String

    @Option(help: "The port to connect to")
    var port: Int

    @Argument(help: "The name of the test to run")
    var testName: String

    func run() async throws {
      guard let testCase = InteroperabilityTestCase(rawValue: self.testName) else {
        throw InteroperabilityTestError.testNotFound(name: self.testName)
      }

      try await Self.runTest(
        testCase: testCase,
        host: self.host,
        port: self.port
      )
    }

    internal static func runTest(
      testCase: InteroperabilityTestCase,
      host: String,
      port: Int
    ) async throws {
      let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      defer {
        try! group.syncShutdownGracefully()
      }

      var transportConfig = HTTP2ClientTransport.Posix.Config.defaults
      transportConfig.compression.enabledAlgorithms = .all
      let serviceConfig = ServiceConfig(loadBalancingConfig: [.roundRobin])
      let transport = try HTTP2ClientTransport.Posix(
        target: .ipv4(host: "0.0.0.0", port: port),
        config: transportConfig,
        serviceConfig: serviceConfig,
        eventLoopGroup: group
      )
      let client = GRPCClient(transport: transport)

      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          try await client.run()
        }

        group.addTask {
          print("Running '\(testCase.name)' ... ", terminator: "")
          do {
            try await testCase.makeTest().run(client: client)
            print("PASSED")
          } catch {
            print("FAILED")
            throw InteroperabilityTestError.testFailed(cause: error)
          }
        }

        try await group.next()
        group.cancelAll()
      }
    }
  }

  struct RunAllTests: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "Runs all gRPC interoperability tests using a gRPC Swift client."
    )

    @Option(help: "The host the server is running on")
    var host: String

    @Option(help: "The port to connect to")
    var port: Int

    func run() async throws {
      for testCase in InteroperabilityTestCase.allCases {
        try await RunTest.runTest(
          testCase: testCase,
          host: self.host,
          port: self.port
        )
      }
    }
  }
}
