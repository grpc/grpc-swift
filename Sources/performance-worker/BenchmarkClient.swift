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

import Foundation
import GRPCCore
import NIOConcurrencyHelpers

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct BenchmarkClient {
  private var client: GRPCClient
  private var rpcNumber: Int32
  private var rpcType: Grpc_Testing_RpcType
  private var messagesPerStream: Int32
  private let rpcStats: NIOLockedValueBox<RPCStats>

  init(
    client: GRPCClient,
    rpcNumber: Int32,
    rpcType: Grpc_Testing_RpcType,
    messagesPerStream: Int32,
    histogramParams: Grpc_Testing_HistogramParams?
  ) {
    self.client = client
    self.rpcNumber = rpcNumber
    self.rpcType = rpcType
    self.messagesPerStream = messagesPerStream

    let histogram: RPCStats.LatencyHistogram
    if let histogramParams = histogramParams {
      histogram = .init(
        resolution: histogramParams.resolution,
        maxBucketStart: histogramParams.maxPossible
      )
    } else {
      histogram = .init()
    }

    self.rpcStats = NIOLockedValueBox(RPCStats(latencyHistogram: histogram))
  }

  internal var currentStats: RPCStats {
    return self.rpcStats.withLockedValue { stats in
      return stats
    }
  }

  internal func run() async throws {
    let benchmarkClient = Grpc_Testing_BenchmarkServiceClient(client: client)
    return try await withThrowingTaskGroup(of: Void.self) { clientGroup in
      // Start the client.
      clientGroup.addTask { try await client.run() }

      // Make the requests to the server and register the latency for each one.
      try await withThrowingTaskGroup(of: Void.self) { rpcsGroup in
        for _ in 0 ..< self.rpcNumber {
          rpcsGroup.addTask {
            let (latency, errorCode) = try await self.makeRPC(
              benchmarkClient: benchmarkClient,
              rpcType: self.rpcType
            )
            guard errorCode != RPCError.Code.unknown else {
              throw RPCError(code: .unknown, message: "The RPC type is UNRECOGNIZED.")
            }
            self.rpcStats.withLockedValue {
              $0.latencyHistogram.record(latency)
              if let errorCode = errorCode {
                $0.requestResultCount[errorCode, default: 1] += 1
              }
            }
          }
        }
        try await rpcsGroup.waitForAll()
      }

      try await clientGroup.next()
    }
  }

  private func computeTimeAndErrorCode<Contents>(
    _ body: (Grpc_Testing_SimpleRequest) async throws -> Result<Contents, RPCError>
  ) async throws -> (latency: Double, errorCode: RPCError.Code?) {
    let request = Grpc_Testing_SimpleRequest.with {
      $0.responseSize = 10
    }
    let startTime = DispatchTime.now().uptimeNanoseconds
    let result = try await body(request)
    let endTime = DispatchTime.now().uptimeNanoseconds

    var errorCode: RPCError.Code?
    switch result {
    case .success:
      errorCode = nil
    case let .failure(error):
      errorCode = error.code
    }
    return (
      latency: Double(endTime - startTime), errorCode: errorCode
    )
  }

  // The result is the number of nanoseconds for processing the RPC.
  private func makeRPC(
    benchmarkClient: Grpc_Testing_BenchmarkServiceClient,
    rpcType: Grpc_Testing_RpcType
  ) async throws -> (latency: Double, errorCode: RPCError.Code?) {
    switch rpcType {
    case .unary:
      return try await self.computeTimeAndErrorCode { request in
        let responseStatus = try await benchmarkClient.unaryCall(
          request: ClientRequest.Single(message: request)
        ) {
          response in
          return response.accepted
        }

        return responseStatus
      }

    // Repeated sequence of one request followed by one response.
    // It is a ping-pong of messages between the client and the server.
    case .streaming:
      return try await self.computeTimeAndErrorCode { request in
        let ids = AsyncStream.makeStream(of: Int.self)
        let streamingRequest = ClientRequest.Stream { writer in
          for try await id in ids.stream {
            if id <= self.messagesPerStream {
              try await writer.write(request)
            } else {
              return
            }
          }
        }

        ids.continuation.yield(1)

        let responseStatus = try await benchmarkClient.streamingCall(request: streamingRequest) {
          response in
          var id = 1
          for try await _ in response.messages {
            id += 1
            ids.continuation.yield(id)
          }
          return response.accepted
        }

        return responseStatus
      }

    case .streamingFromClient:
      return try await self.computeTimeAndErrorCode { request in
        let streamingRequest = ClientRequest.Stream { writer in
          for _ in 1 ... self.messagesPerStream {
            try await writer.write(request)
          }
        }

        let responseStatus = try await benchmarkClient.streamingFromClient(
          request: streamingRequest
        ) { response in
          return response.accepted
        }

        return responseStatus
      }

    case .streamingFromServer:
      return try await self.computeTimeAndErrorCode { request in
        let responseStatus = try await benchmarkClient.streamingFromServer(
          request: ClientRequest.Single(message: request)
        ) { response in
          return response.accepted
        }

        return responseStatus
      }

    case .streamingBothWays:
      return try await self.computeTimeAndErrorCode { request in
        let streamingRequest = ClientRequest.Stream { writer in
          for _ in 1 ... self.messagesPerStream {
            try await writer.write(request)
          }
        }

        let responseStatus = try await benchmarkClient.streamingBothWays(request: streamingRequest)
        { response in
          return response.accepted
        }

        return responseStatus
      }

    case .UNRECOGNIZED:
      return (
        latency: -1, errorCode: RPCError.Code(.unknown)
      )
    }
  }

  internal func shutdown() {
    self.client.close()
  }
}
