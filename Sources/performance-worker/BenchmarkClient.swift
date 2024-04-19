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
  private var rpcType: RPCType
  private var messagesPerStream: Int32
  private var protoParams: Grpc_Testing_SimpleProtoParams
  private let rpcStats: NIOLockedValueBox<RPCStats>

  init(
    client: GRPCClient,
    rpcNumber: Int32,
    rpcType: RPCType,
    messagesPerStream: Int32,
    protoParams: Grpc_Testing_SimpleProtoParams,
    histogramParams: Grpc_Testing_HistogramParams?
  ) {
    self.client = client
    self.rpcNumber = rpcNumber
    self.messagesPerStream = messagesPerStream
    self.protoParams = protoParams
    self.rpcType = rpcType

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

  enum RPCType {
    case unary
    case streaming
    case streamingFromClient
    case streamingFromServer
    case streamingBothWays
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
              benchmarkClient: benchmarkClient
            )
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

  private func timeIt<R>(
    _ body: () async throws -> R
  ) async rethrows -> (R, nanoseconds: Double) {
    let startTime = DispatchTime.now().uptimeNanoseconds
    let result = try await body()
    let endTime = DispatchTime.now().uptimeNanoseconds
    return (result, nanoseconds: Double(endTime - startTime))
  }

  // The result is the number of nanoseconds for processing the RPC.
  private func makeRPC(
    benchmarkClient: Grpc_Testing_BenchmarkServiceClient
  ) async throws -> (latency: Double, errorCode: RPCError.Code?) {
    let message = Grpc_Testing_SimpleRequest.with {
      $0.responseSize = self.protoParams.respSize
      $0.payload = Grpc_Testing_Payload.with {
        $0.body = Data(count: Int(self.protoParams.reqSize))
      }
    }

    switch self.rpcType {
    case .unary:
      let (errorCode, nanoseconds): (RPCError.Code?, Double) = await self.timeIt {
        do {
          try await benchmarkClient.unaryCall(
            request: ClientRequest.Single(message: message)
          ) { response in
            _ = try response.message
          }
          return nil
        } catch let error as RPCError {
          return error.code
        } catch {
          return .unknown
        }
      }
      return (latency: nanoseconds, errorCode)

    // Repeated sequence of one request followed by one response.
    // It is a ping-pong of messages between the client and the server.
    case .streaming:
      let (errorCode, nanoseconds): (RPCError.Code?, Double) = await self.timeIt {
        do {
          let ids = AsyncStream.makeStream(of: Int.self)
          let streamingRequest = ClientRequest.Stream { writer in
            for try await id in ids.stream {
              if id <= self.messagesPerStream {
                try await writer.write(message)
              } else {
                return
              }
            }
          }

          ids.continuation.yield(1)

          try await benchmarkClient.streamingCall(request: streamingRequest) { response in
            var id = 1
            for try await _ in response.messages {
              id += 1
              ids.continuation.yield(id)
            }
          }
          return nil
        } catch let error as RPCError {
          return error.code
        } catch {
          return .unknown
        }
      }
      return (latency: nanoseconds, errorCode)

    case .streamingFromClient:
      let (errorCode, nanoseconds): (RPCError.Code?, Double) = await self.timeIt {
        do {
          let streamingRequest = ClientRequest.Stream { writer in
            for _ in 1 ... self.messagesPerStream {
              try await writer.write(message)
            }
          }

          try await benchmarkClient.streamingFromClient(
            request: streamingRequest
          ) { response in
            _ = try response.message
          }
          return nil
        } catch let error as RPCError {
          return error.code
        } catch {
          return .unknown
        }
      }
      return (latency: nanoseconds, errorCode)

    case .streamingFromServer:
      let (errorCode, nanoseconds): (RPCError.Code?, Double) = await self.timeIt {
        do {
          try await benchmarkClient.streamingFromServer(
            request: ClientRequest.Single(message: message)
          ) { response in
            for try await _ in response.messages {}
          }
          return nil
        } catch let error as RPCError {
          return error.code
        } catch {
          return .unknown
        }
      }
      return (latency: nanoseconds, errorCode)

    case .streamingBothWays:
      let (errorCode, nanoseconds): (RPCError.Code?, Double) = await self.timeIt {
        do {
          let streamingRequest = ClientRequest.Stream { writer in
            for _ in 1 ... self.messagesPerStream {
              try await writer.write(message)
            }
          }

          try await benchmarkClient.streamingBothWays(request: streamingRequest) { response in
            for try await _ in response.messages {}
          }
          return nil
        } catch let error as RPCError {
          return error.code
        } catch {
          return .unknown
        }
      }
      return (latency: nanoseconds, errorCode)
    }
  }

  internal func shutdown() {
    self.client.close()
  }
}
