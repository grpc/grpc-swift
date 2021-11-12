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
import ArgumentParser
import Foundation
import GRPC
import GRPCInteroperabilityTestsImplementation
import Logging
import NIOCore
import NIOPosix

// Reduce stdout noise.
LoggingSystem.bootstrap(StreamLogHandler.standardError)

enum InteroperabilityTestError: LocalizedError {
  case testNotFound(String)
  case testFailed(Error)

  var errorDescription: String? {
    switch self {
    case let .testNotFound(name):
      return "No test named '\(name)' was found"

    case let .testFailed(error):
      return "Test failed with error: \(error)"
    }
  }
}

/// Runs the test instance using the given connection.
///
/// Success or failure is indicated by the lack or presence of thrown errors, respectively.
///
/// - Parameters:
///   - instance: `InteroperabilityTest` instance to run.
///   - name: the name of the test, use for logging only.
///   - host: host of the test server.
///   - port: port of the test server.
///   - useTLS: whether to use TLS when connecting to the test server.
/// - Throws: `InteroperabilityTestError` if the test fails.
func runTest(
  _ instance: InteroperabilityTest,
  name: String,
  host: String,
  port: Int,
  useTLS: Bool
) throws {
  let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  defer {
    try! group.syncShutdownGracefully()
  }

  do {
    print("Running '\(name)' ... ", terminator: "")
    let builder = makeInteroperabilityTestClientBuilder(group: group, useTLS: useTLS)
    instance.configure(builder: builder)
    let connection = builder.connect(host: host, port: port)
    defer {
      _ = connection.close()
    }
    try instance.run(using: connection)
    print("PASSED")
  } catch {
    print("FAILED")
    throw InteroperabilityTestError.testFailed(error)
  }
}

/// Creates a new `InteroperabilityTest` instance with the given name, or throws an
/// `InteroperabilityTestError` if no test matches the given name. Implemented test names can be
/// found by running the `list_tests` target.
func makeRunnableTest(name: String) throws -> InteroperabilityTest {
  guard let testCase = InteroperabilityTestCase(rawValue: name) else {
    throw InteroperabilityTestError.testNotFound(name)
  }

  return testCase.makeTest()
}

// MARK: - Command line options and "main".

struct InteroperabilityTests: ParsableCommand {
  static var configuration = CommandConfiguration(
    abstract: "gRPC Swift Interoperability Runner",
    subcommands: [StartServer.self, RunTest.self, ListTests.self]
  )

  struct StartServer: ParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "Start the gRPC Swift interoperability test server."
    )

    @Option(help: "The port to listen on for new connections")
    var port: Int

    @Flag(help: "Whether TLS should be used or not")
    var tls = false

    func run() throws {
      let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      defer {
        try! group.syncShutdownGracefully()
      }

      let server = try makeInteroperabilityTestServer(
        port: self.port,
        eventLoopGroup: group,
        useTLS: self.tls
      ).wait()
      print("server started: \(server.channel.localAddress!)")

      // We never call close; run until we get killed.
      try server.onClose.wait()
    }
  }

  struct RunTest: ParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "Runs a gRPC interoperability test using a gRPC Swift client."
    )

    @Flag(help: "Whether TLS should be used or not")
    var tls = false

    @Option(help: "The host the server is running on")
    var host: String

    @Option(help: "The port to connect to")
    var port: Int

    @Argument(help: "The name of the test to run")
    var testName: String

    func run() throws {
      let test = try makeRunnableTest(name: self.testName)
      try runTest(
        test,
        name: self.testName,
        host: self.host,
        port: self.port,
        useTLS: self.tls
      )
    }
  }

  struct ListTests: ParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "List all interoperability test names."
    )

    func run() throws {
      InteroperabilityTestCase.allCases.forEach {
        print($0.name)
      }
    }
  }
}

InteroperabilityTests.main()
