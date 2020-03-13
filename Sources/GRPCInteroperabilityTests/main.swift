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
import NIOSSL
import GRPCInteroperabilityTestsImplementation
import Logging

// Reduce stdout noise.
LoggingSystem.bootstrap(StreamLogHandler.standardError)

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
///   - host: host of the test server.
///   - port: port of the test server.
///   - useTLS: whether to use TLS when connecting to the test server.
/// - Throws: `InteroperabilityTestError` if the test fails.
func runTest(_ instance: InteroperabilityTest, name: String, host: String, port: Int, useTLS: Bool) throws {
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

func printUsageAndExit(program: String) -> Never {
  print("""
    Usage: \(program) COMMAND [OPTIONS...]

    Commands:
      start_server [--tls|--notls] PORT         Starts the interoperability test server.

      run_test [--tls|--notls] HOST PORT NAME   Run an interoperability test.

      list_tests                                List all interoperability test names.
    """)
  exit(1)
}

enum Command {
  case startServer(port: Int, useTLS: Bool)
  case runTest(name: String, host: String, port: Int, useTLS: Bool)
  case listTests

  init?(from args: [String]) {
    guard !args.isEmpty else {
      return nil
    }

    var args = args
    let command = args.removeFirst()
    switch command {
    case "start_server":
      guard (args.count == 1 || args.count == 2),
        let port = args.popLast().flatMap(Int.init),
        let useTLS = Command.parseTLSArg(args.popLast())
        else {
          return nil
      }
      self = .startServer(port: port, useTLS: useTLS)

    case "run_test":
      guard (args.count == 3 || args.count == 4),
        let name = args.popLast(),
        let port = args.popLast().flatMap(Int.init),
        let host = args.popLast(),
        let useTLS = Command.parseTLSArg(args.popLast())
        else {
          return nil
      }
      self = .runTest(name: name, host: host, port: port, useTLS: useTLS)

    case "list_tests":
      self = .listTests

    default:
      return nil
    }
  }

  private static func parseTLSArg(_ arg: String?) -> Bool? {
    switch arg {
    case .some("--tls"):
      return true
    case .none, .some("--notls"):
      return false
    default:
      return nil
    }
  }
}

func main(args: [String]) {
  let program = args.first ?? "GRPC Interoperability Tests"
  guard let command = Command(from: .init(args.dropFirst())) else {
    printUsageAndExit(program: program)
  }

  switch command {
  case .listTests:
    InteroperabilityTestCase.allCases.forEach {
      print($0.name)
    }

  case let .startServer(port: port, useTLS: useTLS):
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      try! group.syncShutdownGracefully()
    }

    do {
      let server = try makeInteroperabilityTestServer(port: port, eventLoopGroup: group, useTLS: useTLS).wait()
      print("server started: \(server.channel.localAddress!)")

      // We never call close; run until we get killed.
      try server.onClose.wait()
    } catch {
      print("unable to start interoperability test server")
    }

  case let .runTest(name: name, host: host, port: port, useTLS: useTLS):
    let test: InteroperabilityTest
    do {
      test = try makeRunnableTest(name: name)
    } catch {
      print("\(error)")
      exit(1)
    }

    do {
      // Provide some basic configuration. Some tests may override this.
      try runTest(test, name: name, host: host, port: port, useTLS: useTLS)
    } catch {
      print("Error running test: \(error)")
      exit(1)
    }
  }
}

main(args: CommandLine.arguments)
