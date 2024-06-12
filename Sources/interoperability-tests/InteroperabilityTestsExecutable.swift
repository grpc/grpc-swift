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
    subcommands: [StartServer.self, ListTests.self, RunTests.self]
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

  struct RunTests: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: """
          Run gRPC interoperability tests using a gRPC Swift client.
          You can specify a test name as an argument to run a single test.
          If no test name is given, all interoperability tests will be run.
        """
    )

    @Option(help: "The host the server is running on")
    var host: String

    @Option(help: "The port to connect to")
    var port: Int

    @Argument(help: "The name of the test to run. If absent, all tests will be run.")
    var testName: String?

    func run() async throws {
      if let testName = self.testName {
        guard let testCase = InteroperabilityTestCase(rawValue: testName) else {
          throw InteroperabilityTestError.testNotFound(name: testName)
        }

        try await Self.runTest(
          testCase: testCase,
          host: self.host,
          port: self.port
        )
      } else {
        print("Running all tests...")
        var errors = [any Error]()
        for testCase in InteroperabilityTestCase.allCases {
          do {
            try await Self.runTest(
              testCase: testCase,
              host: self.host,
              port: self.port
            )
          } catch {
            errors.append(error)
          }
        }
      }
    }

    internal static func runTest(
      testCase: InteroperabilityTestCase,
      host: String,
      port: Int
    ) async throws {
      var transportConfig = HTTP2ClientTransport.Posix.Config.defaults
      transportConfig.compression.enabledAlgorithms = .all
      let serviceConfig = ServiceConfig(loadBalancingConfig: [.roundRobin])
      let transport = try HTTP2ClientTransport.Posix(
        target: .ipv4(host: "0.0.0.0", port: port),
        config: transportConfig,
        serviceConfig: serviceConfig,
        eventLoopGroup: .singletonMultiThreadedEventLoopGroup
      )
      let client = GRPCClient(transport: transport)

      try await withThrowingDiscardingTaskGroup { group in
        group.addTask {
          try await client.run()
        }

        print("Running '\(testCase.name)' ... ", terminator: "")
        do {
          try await testCase.makeTest().run(client: client)
          print("PASSED")
        } catch {
          print("FAILED\n" + String(describing: InteroperabilityTestError.testFailed(cause: error)))
        }

        client.close()
      }
    }
  }
}

enum InteroperabilityTestError: Error, CustomStringConvertible {
  case testNotFound(name: String)
  case testFailed(cause: any Error)

  var description: String {
    switch self {
    case .testNotFound(let name):
      return "Test \"\(name)\" not found."
    case .testFailed(let cause):
      return "Test failed with error: \(String(describing: cause))"
    }
  }
}
