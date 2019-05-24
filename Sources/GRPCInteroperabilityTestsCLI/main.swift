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
import SwiftGRPCNIO
import NIO
import NIOSSL
import SwiftGRPCNIOInteroperabilityTests
import Commander

enum InteroperabilityTestError: LocalizedError {
  case testNotFound(String)
  case testFailed(Error)

  var errorDescription: String? {
    switch self {
    case .testNotFound(let name):
      return "No test named '\(name)' was found"

    case .testFailed(let error):
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
///   - connection: client connection to use for running the test.
/// - Throws: `InteroperabilityTestError` if the test fails.
func runTest(_ instance: InteroperabilityTest, name: String, connection: GRPCClientConnection) throws {
  do {
    print("Running '\(name)' ... ", terminator: "")
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

/// Runs the given block and exits with code 1 if the block throws an error.
///
/// The "Commander" CLI elides thrown errors in favour of its own. This function is intended purely
/// to work around this limitation by printing any errors before exiting.
func exitOnThrow<T>(block: () throws -> T) -> T {
  do {
    return try block()
  } catch {
    print(error)
    exit(1)
  }
}

// MARK: - Optional extensions for Commander

// "Commander" doesn't allow us to have no value for an `Option` and using a sentinel value to
// indicate a lack of value isn't very Swift-y when we have `Optional`.

extension Optional: CustomStringConvertible where Wrapped: ArgumentConvertible {
  public var description: String {
    guard let value = self else {
      return "None"
    }
    return "Some(\(value))"
  }
}

extension Optional: ArgumentConvertible where Wrapped: ArgumentConvertible {
  public init(parser: ArgumentParser) throws {
    if let wrapped = parser.shift() as? Wrapped {
      self = wrapped
    } else {
      self = .none
    }
  }
}

// MARK: - Command line options and "main".

let serverHostOption = Option(
  "server_host",
  default: "localhost",
  description: "The server host to connect to.")

let serverPortOption = Option(
  "server_port",
  default: 8080,
  description: "The server port to connect to.")

let testCaseOption = Option(
  "test_case",
  default: InteroperabilityTestCase.emptyUnary.name,
  description: "The name of the test case to execute.")

/// The spec requires a string (as opposed to having a flag) to indicate whether TLS is enabled or
/// disabled.
let useTLSOption = Option(
  "use_tls",
  default: "false",
  description: "Whether to use an encrypted or plaintext connection (true|false).") { value in
  let lowercased = value.lowercased()
  switch lowercased {
  case "true", "false":
    return lowercased
  default:
    throw ArgumentError.invalidType(value: value, type: "boolean", argument: "use_tls")
  }
}

let portOption = Option(
  "port",
  default: 8080,
  description: "The port to listen on.")

let group = Group { group in
  group.command(
    "run_test",
    serverHostOption,
    serverPortOption,
    useTLSOption,
    testCaseOption,
    description: "Run a single test. See 'list_tests' for available test names."
  ) { host, port, useTLS, testCaseName in
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      try? eventLoopGroup.syncShutdownGracefully()
    }

    exitOnThrow {
      let instance = try makeRunnableTest(name: testCaseName)
      let connection = try makeInteroperabilityTestClientConnection(
        host: host,
        port: port,
        eventLoopGroup: eventLoopGroup,
        useTLS: useTLS == "true").wait()
      try runTest(instance, name: testCaseName, connection: connection)
    }
  }

  group.command(
    "start_server",
    portOption,
    useTLSOption,
    description: "Starts the test server."
  ) { port, useTls in
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      try? eventLoopGroup.syncShutdownGracefully()
    }

    let server = exitOnThrow {
      return try makeInteroperabilityTestServer(
        host: "localhost",
        port: port,
        eventLoopGroup: eventLoopGroup,
        useTLS: useTls == "true")
    }

    server.map { $0.channel.localAddress?.port }.whenSuccess {
      print("Server started on port \($0!)")
    }

    // We never call close; run until we get killed.
    try server.flatMap { $0.onClose }.wait()
  }

  group.command(
    "list_tests",
    description: "List available test case names."
  ) {
    InteroperabilityTestCase.allCases.forEach {
      print($0.name)
    }
  }
}

group.run()
