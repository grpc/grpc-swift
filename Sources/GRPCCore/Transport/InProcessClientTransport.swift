/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// An in-process implementation of a ``ClientTransport``.
public struct InProcessClientTransport: ClientTransport {
  private enum State: Sendable {
    case unconnected(InProcessServerTransport)
    case connected(InProcessServerTransport)
    case closed
  }

  public typealias Inbound = RPCAsyncSequence<RPCResponsePart>
  public typealias Outbound = RPCWriter<RPCRequestPart>.Closable
  
  public var retryThrottle: RetryThrottle
  
  private let executionConfigurations: ClientRPCExecutionConfigurationCollection
  private let state: LockedValueBox<State>
  
  public init(
    server: InProcessServerTransport,
    executionConfigurations: ClientRPCExecutionConfigurationCollection
  ) {
    self.retryThrottle = .init(maximumTokens: 10, tokenRatio: 0.1)
    self.executionConfigurations = executionConfigurations
    self.state = .init(.unconnected(server))
  }
  
  /// Establish and maintain a connection to the remote destination.
  ///
  /// Maintains a long-lived connection, or set of connections, to a remote destination.
  /// Connections may be added or removed over time as required by the implementation and the
  /// demand for streams by the client.
  ///
  /// Implementations of this function will typically create a long-lived task group which
  /// maintains connections. The function exits when all open streams have been closed and new connections
  /// are no longer required by the caller who signals this by calling ``close()``, or by cancelling the
  /// task this function runs in.
  ///
  /// - Parameter lazily: This parameter is ignored in this implementation.
  public func connect(lazily: Bool) async throws {
    try self.state.withLockedValue { state in
      switch state {
      case .unconnected(let server):
        state = .connected(server)
        _ = server.listen()
      case .connected:
        throw RPCError(
          code: .failedPrecondition,
          message: "Already connected to server."
        )
      case .closed:
        throw RPCError(
          code: .failedPrecondition,
          message: "Can't connect to server, transport is closed."
        )
      }
    }
  }
  
  public func close() {
    self.state.withLockedValue { state in
      switch state {
      case .unconnected(let server):
        state = .closed
        server.stopListening()
      case .connected(let server):
        state = .closed
        server.stopListening()
      case .closed:
        ()
      }
    }
  }
  
  public func withStream<T>(
    descriptor: MethodDescriptor,
    _ closure: (RPCStream<Inbound, Outbound>) async throws -> T
  ) async throws -> T {
    let request = RPCAsyncSequence<RPCRequestPart>.makeBackpressuredStream(watermarks: (16, 32))
    let response = RPCAsyncSequence<RPCResponsePart>.makeBackpressuredStream(watermarks: (16, 32))

    let clientStream = RPCStream(
      descriptor: descriptor,
      inbound: response.stream,
      outbound: request.writer
    )

    let serverStream = RPCStream(
      descriptor: descriptor,
      inbound: request.stream,
      outbound: response.writer
    )
    
    let error: RPCError? = try self.state.withLockedValue { state in
      switch state {
      case .connected(let transport):
        do {
          try transport.acceptStream(serverStream)
          state = .connected(transport)
        } catch let acceptStreamError as RPCError {
          return acceptStreamError
        }
        return nil

      case .unconnected:
        return RPCError(
          code: .failedPrecondition,
          message: "The client transport must be connected before streams can be created."
        )

      case .closed:
        return RPCError(
          code: .failedPrecondition,
          message: "The client transport is closed."
        )
      }
    }

    if let error = error {
      serverStream.outbound.finish()
      clientStream.outbound.finish()
      throw error
    }
    
    let result = try await closure(clientStream)
    
    serverStream.outbound.finish()
    clientStream.outbound.finish()
    
    return result
  }
  
  public func executionConfiguration(forMethod descriptor: MethodDescriptor) -> ClientRPCExecutionConfiguration? {
    self.executionConfigurations[descriptor]
  }
}
