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

private import Atomics
private import Foundation
internal import GRPCCore
private import NIOConcurrencyHelpers

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct BenchmarkClient {
  private let _isShuttingDown = ManagedAtomic(false)

  /// Whether the benchmark client is shutting down. Used to control when to stop sending messages
  /// or creating new RPCs.
  private var isShuttingDown: Bool {
    self._isShuttingDown.load(ordering: .relaxed)
  }

  /// The underlying client.
  private var client: GRPCClient

  /// The number of concurrent RPCs to run.
  private var concurrentRPCs: Int

  /// The type of RPC to make against the server.
  private var rpcType: RPCType

  /// The max number of messages to send on a stream before replacing the RPC with a new one. A
  /// value of zero means there is no limit.
  private var messagesPerStream: Int
  private var noMessageLimit: Bool { self.messagesPerStream == 0 }

  /// The message to send for all RPC types to the server.
  private let message: Grpc_Testing_SimpleRequest

  /// Per RPC stats.
  private let rpcStats: NIOLockedValueBox<RPCStats>

  init(
    client: GRPCClient,
    concurrentRPCs: Int,
    rpcType: RPCType,
    messagesPerStream: Int,
    protoParams: Grpc_Testing_SimpleProtoParams,
    histogramParams: Grpc_Testing_HistogramParams?
  ) {
    self.client = client
    self.concurrentRPCs = concurrentRPCs
    self.messagesPerStream = messagesPerStream
    self.rpcType = rpcType
    self.message = .with {
      $0.responseSize = protoParams.respSize
      $0.payload = Grpc_Testing_Payload.with {
        $0.body = Data(count: Int(protoParams.reqSize))
      }
    }

    let histogram: RPCStats.LatencyHistogram
    if let histogramParams = histogramParams {
      histogram = RPCStats.LatencyHistogram(
        resolution: histogramParams.resolution,
        maxBucketStart: histogramParams.maxPossible
      )
    } else {
      histogram = RPCStats.LatencyHistogram()
    }

    self.rpcStats = NIOLockedValueBox(RPCStats(latencyHistogram: histogram))
  }

  enum RPCType {
    case unary
    case streaming
  }

  internal var currentStats: RPCStats {
    return self.rpcStats.withLockedValue { stats in
      return stats
    }
  }

  internal func run() async throws {
    let benchmarkClient = Grpc_Testing_BenchmarkServiceClient(wrapping: self.client)
    return try await withThrowingTaskGroup(of: Void.self) { clientGroup in
      // Start the client.
      clientGroup.addTask {
        try await self.client.run()
      }

      try await withThrowingTaskGroup(of: Void.self) { rpcsGroup in
        // Start one task for each concurrent RPC and keep looping in that task until indicated
        // to stop.
        for _ in 0 ..< self.concurrentRPCs {
          rpcsGroup.addTask {
            while !self.isShuttingDown {
              switch self.rpcType {
              case .unary:
                await self.unary(benchmark: benchmarkClient)

              case .streaming:
                await self.streaming(benchmark: benchmarkClient)
              }
            }
          }
        }

        try await rpcsGroup.waitForAll()
      }

      self.client.beginGracefulShutdown()
      try await clientGroup.next()
    }
  }

  private func record(latencyNanos: Double, errorCode: RPCError.Code?) {
    self.rpcStats.withLockedValue { stats in
      stats.latencyHistogram.record(latencyNanos)
      if let errorCode = errorCode {
        stats.requestResultCount[errorCode, default: 0] += 1
      }
    }
  }

  private func record(errorCode: RPCError.Code) {
    self.rpcStats.withLockedValue { stats in
      stats.requestResultCount[errorCode, default: 0] += 1
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

  private func unary(benchmark: Grpc_Testing_BenchmarkServiceClient) async {
    let (errorCode, nanoseconds): (RPCError.Code?, Double) = await self.timeIt {
      do {
        try await benchmark.unaryCall(request: ClientRequest.Single(message: self.message)) {
          _ = try $0.message
        }
        return nil
      } catch let error as RPCError {
        return error.code
      } catch {
        return .unknown
      }
    }

    self.record(latencyNanos: nanoseconds, errorCode: errorCode)
  }

  private func streaming(benchmark: Grpc_Testing_BenchmarkServiceClient) async {
    // Streaming RPCs ping-pong messages back and forth. To achieve this the response message
    // stream is sent to the request closure, and the request closure indicates the outcome back
    // to the response handler to keep the RPC alive for the appropriate amount of time.
    let status = AsyncStream.makeStream(of: RPCError.self)
    let response = AsyncStream.makeStream(
      of: RPCAsyncSequence<Grpc_Testing_SimpleResponse, any Error>.self
    )

    let request = ClientRequest.Stream(of: Grpc_Testing_SimpleRequest.self) { writer in
      defer { status.continuation.finish() }

      // The time at which the last message was sent.
      var lastMessageSendTime = DispatchTime.now()
      try await writer.write(self.message)

      // Wait for the response stream.
      var iterator = response.stream.makeAsyncIterator()
      guard let responses = await iterator.next() else {
        throw RPCError(code: .internalError, message: "")
      }

      // Record the first latency.
      let now = DispatchTime.now()
      let nanos = now.uptimeNanoseconds - lastMessageSendTime.uptimeNanoseconds
      lastMessageSendTime = now
      self.record(latencyNanos: Double(nanos), errorCode: nil)

      // Now start looping. Only stop when the max messages per stream is hit or told to stop.
      var responseIterator = responses.makeAsyncIterator()
      var messagesSent = 1

      while !self.isShuttingDown && (self.noMessageLimit || messagesSent < self.messagesPerStream) {
        messagesSent += 1
        do {
          if try await responseIterator.next() != nil {
            let now = DispatchTime.now()
            let nanos = now.uptimeNanoseconds - lastMessageSendTime.uptimeNanoseconds
            lastMessageSendTime = now
            self.record(latencyNanos: Double(nanos), errorCode: nil)
            try await writer.write(message)
          } else {
            break
          }
        } catch let error as RPCError {
          status.continuation.yield(error)
          break
        } catch {
          status.continuation.yield(RPCError(code: .unknown, message: ""))
          break
        }
      }
    }

    do {
      try await benchmark.streamingCall(request: request) {
        response.continuation.yield($0.messages)
        response.continuation.finish()
        for await errorCode in status.stream {
          throw errorCode
        }
      }
    } catch let error as RPCError {
      self.record(errorCode: error.code)
    } catch {
      self.record(errorCode: .unknown)
    }
  }

  internal func shutdown() {
    self._isShuttingDown.store(true, ordering: .relaxed)
    self.client.beginGracefulShutdown()
  }
}
