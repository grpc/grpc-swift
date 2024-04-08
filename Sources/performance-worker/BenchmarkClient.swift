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

import GRPCCore

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct BenchmarkClient {
  var client: GRPCClient
  var rpcNumber: Int32
  var rpcType: Grpc_Testing_RpcType
  var histogramParams: Grpc_Testing_HistogramParams

  init(
    client: GRPCClient,
    rpcNumber: Int32,
    rpcType: Grpc_Testing_RpcType,
    histogramParams: Grpc_Testing_HistogramParams
  ) {
    self.client = client
    self.rpcNumber = rpcNumber
    self.rpcType = rpcType
    self.histogramParams = histogramParams
  }

  func run() async throws -> LatencyHistogram {
    let benchmarkClient = Grpc_Testing_BenchmarkServiceClient(client: client)
    return try await withThrowingTaskGroup(of: Void.self, returning: LatencyHistogram.self) {
      clientGroup in
      // Start the client.
      clientGroup.addTask { try await client.run() }

      // Make the requests to the server and register the latency for each one.
      let latencies = try await withThrowingTaskGroup(of: Double.self, returning: [Double].self) {
        rpcsGroup in
        for _ in 0 ..< self.rpcNumber {
          rpcsGroup.addTask {
            return self.makeRPC(client: benchmarkClient, rpcType: self.rpcType)
          }
        }

        var latencies = [Double]()

        while let latency = try await rpcsGroup.next() {
          latencies.append(latency)
        }

        return latencies
      }

      try await clientGroup.next()

      // Creating the LatencyHistogram for the current client.
      var latencyLatencyHistogram = LatencyHistogram(
        resolution: self.histogramParams.resolution,
        maxBucketStart: self.histogramParams.maxPossible
      )
      for latency in latencies {
        latencyLatencyHistogram.add(value: latency)
      }

      return latencyLatencyHistogram
    }
  }

  // The result is the number of nanoseconds for processing the RPC.
  private func makeRPC(
    client: Grpc_Testing_BenchmarkServiceClient,
    rpcType: Grpc_Testing_RpcType
  ) -> Double {
    switch rpcType {
    case .unary, .streaming, .streamingFromClient, .streamingFromServer, .streamingBothWays,
      .UNRECOGNIZED:
      var startTime = LatencyHistogram.grpcTimeNow()
      var endTime = LatencyHistogram.grpcTimeNow()
      return Double((endTime - startTime).value)
    }
  }
}
