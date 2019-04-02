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
import SwiftGRPCNIOInteropabilityTests
import Commander

enum InteropabilityTestError: LocalizedError {
  case testNotFound(String)
  case testNotSupported(String)
  case testFailed(Error)

  var errorDescription: String? {
    switch self {
    case .testNotFound(let name):
      return "No test named '\(name)' was found"

    case .testNotSupported(let name):
      return "Test '\(name)' was found but is not currently supported"

    case .testFailed(let error):
      return "Test failed with error: \(error)"
    }
  }
}

func runTest(_ instance: InteropabilityTest, name: String, connection: GRPCClientConnection) throws {
  do {
    print("Running '\(name)' ... ", terminator: "")
    try instance.run(using: connection)
    print("PASSED")
  } catch {
    print("FAILED")
    throw error
  }
}

func makeRunnableTest(name: String) throws -> InteropabilityTest {
  guard let testCase = InteropabilityTestCase(rawValue: name) else {
    throw InteropabilityTestError.testNotFound(name)
  }

  return testCase.makeTest()
}

var server: EventLoopFuture<GRPCServer>!

func exitOnThrow<T>(message: String = "Failed with error:", handler: () throws -> T) -> T {
  do {
    return try handler()
  } catch {
    print(message, error)
    exit(1)
  }
}

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

let serverHostOption = Option(
  "server_host",
  default: "localhost",
  description: "The server host to connect to.")

let serverHostOverrideOption = Option<String?>(
  "server_host_override",
  default: .none,
  description: "The server host to claim to be connecting to, for use in TLS and HTTP/2 " +
    ":authority header. If unspecified, the value of --server_host will be used.")

let serverPortOption = Option(
  "server_port",
  default: 8080,
  description: "The server port to connect to.")

let portOption = Option(
  "port",
  default: 8080,
  description: "The port to listen on.")

let testCaseOption = Argument<String>(
  "test_case",
  description: "The name of the test case to execute. For example, 'empty_unary'.")

let tlsFlag = Flag(
  "use_tls",
  description: "Whether to use a plaintext or encrypted connection.")

let group = Group { group in
  group.command(
    "run_test",
    serverHostOption,
    serverHostOverrideOption,
    serverPortOption,
    tlsFlag,
    testCaseOption,
    description: "Run a single test. See 'list_tests' for available test names."
  ) { host, hostOverride, port, useTLS, testCaseName in
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      try? eventLoopGroup.syncShutdownGracefully()
    }

    exitOnThrow {
      let instance = try makeRunnableTest(name: testCaseName)
      let connection = try makeInteropabilityTestClientConnection(
        host: host,
        port: port,
        eventLoopGroup: eventLoopGroup,
        useTLS: useTLS).wait()
      try runTest(instance, name: testCaseName, connection: connection)
    }
  }

  group.command(
    "start_server",
    portOption,
    tlsFlag,
    description: "Starts the test server."
  ) { port, useTls in
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    server = exitOnThrow {
      return try makeInteropabilityTestServer(
        host: "localhost",
        port: port,
        eventLoopGroup: eventLoopGroup,
        useTLS: useTls)
    }

    server.map { $0.channel.localAddress?.port }.whenSuccess {
      print("Server started on port \($0!)")
    }

    // We never call close; run until we get killed.
    try server!.flatMap { $0.onClose }.wait()
  }

  group.command(
    "list_tests",
    description: "List available test cases."
  ) {
    InteropabilityTestCase.allCases.forEach {
      print($0.name)
    }
  }
}

group.run()
