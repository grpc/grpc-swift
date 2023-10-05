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
import GRPC
import Logging

let smallRequest = String(repeating: "x", count: 8)
let largeRequest = String(repeating: "x", count: 1 << 16)  // 65k

// Add benchmarks here!
func runBenchmarks(spec: TestSpec) {
  measureAndPrint(
    description: "unary_10k_small_requests",
    benchmark: Unary(
      requests: 10000,
      text: smallRequest,
      useNIOTSIfAvailable: spec.useNIOTransportServices,
      useTLS: spec.useTLS
    ),
    spec: spec
  )

  measureAndPrint(
    description: "unary_10k_long_requests",
    benchmark: Unary(
      requests: 10000,
      text: largeRequest,
      useNIOTSIfAvailable: spec.useNIOTransportServices,
      useTLS: spec.useTLS
    ),
    spec: spec
  )

  measureAndPrint(
    description: "bidi_10k_small_requests_in_batches_of_1",
    benchmark: Bidi(
      requests: 10000,
      text: smallRequest,
      batchSize: 1,
      useNIOTSIfAvailable: spec.useNIOTransportServices,
      useTLS: spec.useTLS
    ),
    spec: spec
  )

  measureAndPrint(
    description: "bidi_10k_small_requests_in_batches_of_5",
    benchmark: Bidi(
      requests: 10000,
      text: smallRequest,
      batchSize: 5,
      useNIOTSIfAvailable: spec.useNIOTransportServices,
      useTLS: spec.useTLS
    ),
    spec: spec
  )

  measureAndPrint(
    description: "bidi_1k_large_requests_in_batches_of_5",
    benchmark: Bidi(
      requests: 1000,
      text: largeRequest,
      batchSize: 1,
      useNIOTSIfAvailable: spec.useNIOTransportServices,
      useTLS: spec.useTLS
    ),
    spec: spec
  )

  measureAndPrint(
    description: "embedded_client_unary_10k_small_requests",
    benchmark: EmbeddedClientThroughput(requests: 10000, text: smallRequest),
    spec: spec
  )

  measureAndPrint(
    description: "embedded_client_unary_1k_large_requests",
    benchmark: EmbeddedClientThroughput(requests: 1000, text: largeRequest),
    spec: spec
  )

  measureAndPrint(
    description: "embedded_client_unary_1k_large_requests_1k_frames",
    benchmark: EmbeddedClientThroughput(
      requests: 1000,
      text: largeRequest,
      maxResponseFrameSize: 1024
    ),
    spec: spec
  )

  measureAndPrint(
    description: "embedded_server_unary_10k_small_requests",
    benchmark: EmbeddedServerChildChannelBenchmark(
      mode: .unary(rpcs: 10000),
      text: smallRequest
    ),
    spec: spec
  )

  measureAndPrint(
    description: "embedded_server_client_streaming_1_rpc_10k_small_requests",
    benchmark: EmbeddedServerChildChannelBenchmark(
      mode: .clientStreaming(rpcs: 1, requestsPerRPC: 10000),
      text: smallRequest
    ),
    spec: spec
  )

  measureAndPrint(
    description: "embedded_server_client_streaming_10k_rpcs_1_small_requests",
    benchmark: EmbeddedServerChildChannelBenchmark(
      mode: .clientStreaming(rpcs: 10000, requestsPerRPC: 1),
      text: smallRequest
    ),
    spec: spec
  )

  measureAndPrint(
    description: "embedded_server_server_streaming_1_rpc_10k_small_responses",
    benchmark: EmbeddedServerChildChannelBenchmark(
      mode: .serverStreaming(rpcs: 1, responsesPerRPC: 10000),
      text: smallRequest
    ),
    spec: spec
  )

  measureAndPrint(
    description: "embedded_server_server_streaming_10k_rpcs_1_small_response",
    benchmark: EmbeddedServerChildChannelBenchmark(
      mode: .serverStreaming(rpcs: 10000, responsesPerRPC: 1),
      text: smallRequest
    ),
    spec: spec
  )

  measureAndPrint(
    description: "embedded_server_bidi_1_rpc_10k_small_requests",
    benchmark: EmbeddedServerChildChannelBenchmark(
      mode: .bidirectional(rpcs: 1, requestsPerRPC: 10000),
      text: smallRequest
    ),
    spec: spec
  )

  measureAndPrint(
    description: "embedded_server_bidi_10k_rpcs_1_small_request",
    benchmark: EmbeddedServerChildChannelBenchmark(
      mode: .bidirectional(rpcs: 10000, requestsPerRPC: 1),
      text: smallRequest
    ),
    spec: spec
  )

  measureAndPrint(
    description: "percent_encode_decode_10k_status_messages",
    benchmark: PercentEncoding(iterations: 10000, requiresEncoding: true),
    spec: spec
  )

  measureAndPrint(
    description: "percent_encode_decode_10k_ascii_status_messages",
    benchmark: PercentEncoding(iterations: 10000, requiresEncoding: false),
    spec: spec
  )
}

struct TestSpec {
  var action: Action
  var repeats: Int
  var useNIOTransportServices: Bool
  var useTLS: Bool

  init(action: Action, repeats: Int, useNIOTransportServices: Bool, useTLS: Bool) {
    self.action = action
    self.repeats = repeats
    self.useNIOTransportServices = useNIOTransportServices
    self.useTLS = useTLS
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
      case let .some(selectedTests):
        return selectedTests.contains(description)
      }
    }
  }
}

struct PerformanceTests: ParsableCommand {
  @Flag(name: .shortAndLong, help: "List all available tests")
  var list: Bool = false

  @Flag(name: .shortAndLong, help: "Run all tests")
  var all: Bool = false

  @Flag(help: "Use NIO Transport Services (if available)")
  var useNIOTransportServices: Bool = false

  @Flag(help: "Use TLS for tests which support it")
  var useTLS: Bool = false

  @Option(help: "The number of times to run each test")
  var repeats: Int = 10

  @Argument(help: "The tests to run")
  var tests: [String] = []

  func run() throws {
    let spec: TestSpec

    if self.list {
      spec = TestSpec(
        action: .list,
        repeats: self.repeats,
        useNIOTransportServices: self.useNIOTransportServices,
        useTLS: self.useTLS
      )
    } else if self.all {
      spec = TestSpec(
        action: .run(.all),
        repeats: self.repeats,
        useNIOTransportServices: self.useNIOTransportServices,
        useTLS: self.useTLS
      )
    } else {
      spec = TestSpec(
        action: .run(.some(self.tests)),
        repeats: self.repeats,
        useNIOTransportServices: self.useNIOTransportServices,
        useTLS: self.useTLS
      )
    }

    runBenchmarks(spec: spec)
  }
}

assert(
  {
    print("⚠️ WARNING: YOU ARE RUNNING IN DEBUG MODE ⚠️")
    return true
  }()
)

PerformanceTests.main()
