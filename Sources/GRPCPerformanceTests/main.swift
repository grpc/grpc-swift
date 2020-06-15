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
import EchoImplementation
import EchoModel
import Logging

// Add benchmarks here!
func runBenchmarks(spec: TestSpec) {
  let smallRequest = String(repeating: "x", count: 8)
  let largeRequest = String(repeating: "x", count: 1 << 16)  // 65k

  measureAndPrint(
    description: "unary_10k_small_requests",
    benchmark: Unary(requests: 10_000, text: smallRequest),
    spec: spec
  )

  measureAndPrint(
    description: "unary_10k_long_requests",
    benchmark: Unary(requests: 10_000, text: largeRequest),
    spec: spec
  )

  measureAndPrint(
    description: "bidi_10k_small_requests_in_batches_of_1",
    benchmark: Bidi(requests: 10_000, text: smallRequest, batchSize: 1),
    spec: spec
  )

  measureAndPrint(
    description: "bidi_10k_small_requests_in_batches_of_5",
    benchmark: Bidi(requests: 10_000, text: smallRequest, batchSize: 5),
    spec: spec
  )

  measureAndPrint(
    description: "bidi_1k_large_requests_in_batches_of_5",
    benchmark: Bidi(requests: 1_000, text: largeRequest, batchSize: 1),
    spec: spec
  )

  measureAndPrint(
    description: "embedded_client_unary_10k_small_requests",
    benchmark: EmbeddedClientThroughput(requests: 10_000, text: smallRequest),
    spec: spec
  )

  measureAndPrint(
    description: "percent_encode_decode_10k_status_messages",
    benchmark: PercentEncoding(iterations: 10_000, requiresEncoding: true),
    spec: spec
  )

  measureAndPrint(
    description: "percent_encode_decode_10k_ascii_status_messages",
    benchmark: PercentEncoding(iterations: 10_000, requiresEncoding: false),
    spec: spec
  )
}

struct TestSpec {
  var action: Action
  var repeats: Int

  init(action: Action, repeats: Int = 10) {
    self.action = action
    self.repeats = repeats
  }

  enum Action {
    /// Run the benchmark with the given filter.
    case run(Filter)
    /// List all benchmarks.
    case list
  }

  enum Filter {
    /// Run all tests.
    case all
    /// Run the tests which match the given descriptions.
    case some([String])

    func shouldRun(_ description: String) -> Bool {
      switch self {
      case .all:
        return true
      case .some(let selectedTests):
        return selectedTests.contains(description)
      }
    }
  }
}

func usage(program: String) -> String {
  return """
  USAGE: \(program) [-alh] [BENCHMARK ...]

  OPTIONS:

    The following options are available:

    -a  Run all benchmarks. (Also: '--all')

    -l  List all benchmarks. (Also: '--list')

    -h  Prints this message. (Also: '--help')
  """
}

func main(args: [String]) {
  // Quieten the logs.
  LoggingSystem.bootstrap {
    var handler = StreamLogHandler.standardOutput(label: $0)
    handler.logLevel = .critical
    return handler
  }

  let program = args.first!
  let arg0 = args.dropFirst().first

  switch arg0 {
  case "-h", "--help":
    print(usage(program: program))

  case "-l", "--list":
    runBenchmarks(spec: TestSpec(action: .list))

  case "-a", "-all":
    runBenchmarks(spec: TestSpec(action: .run(.all)))

  default:
    // This must be a list of benchmarks to run.
    let tests = Array(args.dropFirst())
    if tests.isEmpty {
      print(usage(program: program))
    } else {
      runBenchmarks(spec: TestSpec(action: .run(.some(tests))))
    }
  }
}

assert({
  print("⚠️ WARNING: YOU ARE RUNNING IN DEBUG MODE ⚠️")
  return true
}())

main(args: CommandLine.arguments)
