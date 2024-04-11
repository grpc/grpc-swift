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

import GRPCCore

/// An in-process implementation of a ``ClientTransport``.
///
/// This is useful when you're interested in testing your application without any actual networking layers
/// involved, as the client and server will communicate directly with each other via in-process streams.
///
/// To use this client, you'll have to provide an ``InProcessServerTransport`` upon creation, as well
/// as a ``ClientRPCExecutionConfigurationCollection``, containing a set of
/// ``ClientRPCExecutionConfiguration``s which are specific, per-method configurations for your
/// transport.
///
/// Once you have a client, you must keep a long-running task executing ``connect(lazily:)``, which
/// will return only once all streams have been finished and ``close()`` has been called on this client; or
/// when the containing task is cancelled.
///
/// To execute requests using this client, use ``withStream(descriptor:_:)``. If this function is
/// called before ``connect(lazily:)`` is called, then any streams will remain pending and the call will
/// block until ``connect(lazily:)`` is called or the task is cancelled.
///
/// - SeeAlso: ``ClientTransport``
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct InProcessClientTransport: ClientTransport {
  private enum State: Sendable {
    struct UnconnectedState {
      var serverTransport: InProcessServerTransport
      var pendingStreams: [AsyncStream<Void>.Continuation]

      init(serverTransport: InProcessServerTransport) {
        self.serverTransport = serverTransport
        self.pendingStreams = []
      }
    }

    struct ConnectedState {
      var serverTransport: InProcessServerTransport
      var nextStreamID: Int
      var openStreams:
        [Int: (
          RPCStream<Inbound, Outbound>,
          RPCStream<RPCAsyncSequence<RPCRequestPart>, RPCWriter<RPCResponsePart>.Closable>
        )]
      var signalEndContinuation: AsyncStream<Void>.Continuation

      init(
        fromUnconnected state: UnconnectedState,
        signalEndContinuation: AsyncStream<Void>.Continuation
      ) {
        self.serverTransport = state.serverTransport
        self.nextStreamID = 0
        self.openStreams = [:]
        self.signalEndContinuation = signalEndContinuation
      }
    }

    struct ClosedState {
      var openStreams:
        [Int: (
          RPCStream<Inbound, Outbound>,
          RPCStream<RPCAsyncSequence<RPCRequestPart>, RPCWriter<RPCResponsePart>.Closable>
        )]
      var signalEndContinuation: AsyncStream<Void>.Continuation?

      init() {
        self.openStreams = [:]
        self.signalEndContinuation = nil
      }

      init(fromConnected state: ConnectedState) {
        self.openStreams = state.openStreams
        self.signalEndContinuation = state.signalEndContinuation
      }
    }

    case unconnected(UnconnectedState)
    case connected(ConnectedState)
    case closed(ClosedState)
  }

  public typealias Inbound = RPCAsyncSequence<RPCResponsePart>
  public typealias Outbound = RPCWriter<RPCRequestPart>.Closable

  public let retryThrottle: RetryThrottle?

  private let methodConfiguration: _MethodConfigurations
  private let state: _LockedValueBox<State>

  /// Creates a new in-process client transport.
  ///
  /// - Parameters:
  ///   - server: The in-process server transport to connect to.
  ///   - serviceConfiguration: Service configuration.
  public init(
    server: InProcessServerTransport,
    serviceConfiguration: ServiceConfiguration = ServiceConfiguration()
  ) {
    self.retryThrottle = serviceConfiguration.retryThrottlingPolicy.map {
      RetryThrottle(policy: $0)
    }
    self.methodConfiguration = _MethodConfigurations(serviceConfiguration: serviceConfiguration)
    self.state = _LockedValueBox(.unconnected(.init(serverTransport: server)))
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
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    try self.state.withLockedValue { state in
      switch state {
      case .unconnected(let unconnectedState):
        state = .connected(
          .init(
            fromUnconnected: unconnectedState,
            signalEndContinuation: continuation
          )
        )
        for pendingStream in unconnectedState.pendingStreams {
          pendingStream.finish()
        }
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

    for await _ in stream {
      // This for-await loop will exit (and thus `connect(lazily:)` will return)
      // only when the task is cancelled, or when the stream's continuation is
      // finished - whichever happens first.
      // The continuation will be finished when `close()` is called and there
      // are no more open streams.
    }

    // If at this point there are any open streams, it's because Cancellation
    // occurred and all open streams must now be closed.
    let openStreams = self.state.withLockedValue { state in
      switch state {
      case .unconnected:
        // We have transitioned to connected, and we can't transition back.
        fatalError("Invalid state")
      case .connected(let connectedState):
        state = .closed(.init())
        return connectedState.openStreams.values
      case .closed(let closedState):
        return closedState.openStreams.values
      }
    }

    for (clientStream, serverStream) in openStreams {
      clientStream.outbound.finish(throwing: CancellationError())
      serverStream.outbound.finish(throwing: CancellationError())
    }
  }

  /// Signal to the transport that no new streams may be created.
  ///
  /// Existing streams may run to completion naturally but calling ``withStream(descriptor:_:)``
  /// will result in an ``RPCError`` with code ``RPCError/Code/failedPrecondition`` being thrown.
  ///
  /// If you want to forcefully cancel all active streams then cancel the task running ``connect(lazily:)``.
  public func close() {
    let maybeContinuation: AsyncStream<Void>.Continuation? = self.state.withLockedValue { state in
      switch state {
      case .unconnected:
        state = .closed(.init())
        return nil
      case .connected(let connectedState):
        if connectedState.openStreams.count == 0 {
          state = .closed(.init())
          return connectedState.signalEndContinuation
        } else {
          state = .closed(.init(fromConnected: connectedState))
          return nil
        }
      case .closed:
        return nil
      }
    }
    maybeContinuation?.finish()
  }

  /// Opens a stream using the transport, and uses it as input into a user-provided closure.
  ///
  /// - Important: The opened stream is closed after the closure is finished.
  ///
  /// This transport implementation throws ``RPCError/Code/failedPrecondition`` if the transport
  /// is closing or has been closed.
  ///
  ///   This implementation will queue any streams (and thus block this call) if this function is called before
  ///   ``connect(lazily:)``, until a connection is established - at which point all streams will be
  ///   created.
  ///
  /// - Parameters:
  ///   - descriptor: A description of the method to open a stream for.
  ///   - options: Options specific to the stream.
  ///   - closure: A closure that takes the opened stream as parameter.
  /// - Returns: Whatever value was returned from `closure`.
  public func withStream<T>(
    descriptor: MethodDescriptor,
    options: CallOptions,
    _ closure: (RPCStream<Inbound, Outbound>) async throws -> T
  ) async throws -> T {
    let request = RPCAsyncSequence<RPCRequestPart>._makeBackpressuredStream(watermarks: (16, 32))
    let response = RPCAsyncSequence<RPCResponsePart>._makeBackpressuredStream(watermarks: (16, 32))

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

    let waitForConnectionStream: AsyncStream<Void>? = self.state.withLockedValue { state in
      if case .unconnected(var unconnectedState) = state {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        unconnectedState.pendingStreams.append(continuation)
        state = .unconnected(unconnectedState)
        return stream
      }
      return nil
    }

    if let waitForConnectionStream {
      for await _ in waitForConnectionStream {
        // This loop will exit either when the task is cancelled or when the
        // client connects and this stream can be opened.
      }
      try Task.checkCancellation()
    }

    let streamID = try self.state.withLockedValue { state in
      switch state {
      case .unconnected:
        // The state cannot be unconnected because if it was, then the above
        // for-await loop on `pendingStream` would have not returned.
        // The only other option is for the task to have been cancelled,
        // and that's why we check for cancellation right after the loop.
        fatalError("Invalid state.")

      case .connected(var connectedState):
        let streamID = connectedState.nextStreamID
        do {
          try connectedState.serverTransport.acceptStream(serverStream)
          connectedState.openStreams[streamID] = (clientStream, serverStream)
          connectedState.nextStreamID += 1
          state = .connected(connectedState)
        } catch let acceptStreamError as RPCError {
          serverStream.outbound.finish(throwing: acceptStreamError)
          clientStream.outbound.finish(throwing: acceptStreamError)
          throw acceptStreamError
        } catch {
          serverStream.outbound.finish(throwing: error)
          clientStream.outbound.finish(throwing: error)
          throw RPCError(code: .unknown, message: "Unknown error: \(error).")
        }
        return streamID

      case .closed:
        let error = RPCError(
          code: .failedPrecondition,
          message: "The client transport is closed."
        )
        serverStream.outbound.finish(throwing: error)
        clientStream.outbound.finish(throwing: error)
        throw error
      }
    }

    defer {
      clientStream.outbound.finish()

      let maybeEndContinuation = self.state.withLockedValue { state in
        switch state {
        case .unconnected:
          // The state cannot be unconnected at this point, because if we made
          // it this far, it's because the transport was connected.
          // Once connected, it's impossible to transition back to unconnected,
          // so this is an invalid state.
          fatalError("Invalid state")
        case .connected(var connectedState):
          connectedState.openStreams.removeValue(forKey: streamID)
          state = .connected(connectedState)
        case .closed(var closedState):
          closedState.openStreams.removeValue(forKey: streamID)
          state = .closed(closedState)
          if closedState.openStreams.isEmpty {
            // This was the last open stream: signal the closure of the client.
            return closedState.signalEndContinuation
          }
        }
        return nil
      }
      maybeEndContinuation?.finish()
    }

    return try await closure(clientStream)
  }

  /// Returns the execution configuration for a given method.
  ///
  /// - Parameter descriptor: The method to lookup configuration for.
  /// - Returns: Execution configuration for the method, if it exists.
  public func configuration(
    forMethod descriptor: MethodDescriptor
  ) -> MethodConfiguration? {
    self.methodConfiguration[descriptor]
  }
}
