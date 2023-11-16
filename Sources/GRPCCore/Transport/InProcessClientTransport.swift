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
public struct InProcessClientTransport: ClientTransport {
  private enum State: Sendable {
    case unconnected(
      _ serverTransport: InProcessServerTransport,
      _ pendingStreams: [AsyncStream<Void>.Continuation]
    )
    case connected(
      _ serverTransport: InProcessServerTransport,
      _ openStreams: Int,
      _ signalEndConnection: AsyncStream<Void>.Continuation
    )
    case closed(
      _ openStreams: Int,
      _ signalEndContinuation: AsyncStream<Void>.Continuation?
    )
  }

  public typealias Inbound = RPCAsyncSequence<RPCResponsePart>
  public typealias Outbound = RPCWriter<RPCRequestPart>.Closable

  public let retryThrottle: RetryThrottle

  private let executionConfigurations: ClientRPCExecutionConfigurationCollection
  private let state: LockedValueBox<State>

  public init(
    server: InProcessServerTransport,
    executionConfigurations: ClientRPCExecutionConfigurationCollection
  ) {
    self.retryThrottle = RetryThrottle(maximumTokens: 10, tokenRatio: 0.1)
    self.executionConfigurations = executionConfigurations
    self.state = LockedValueBox(.unconnected(server, []))
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
      case .unconnected(let server, let pendingStreams):
        state = .connected(server, 0, continuation)
        for pendingStream in pendingStreams {
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
  }

  /// Signal to the transport that no new streams may be created.
  ///
  /// Existing streams may run to completion naturally but calling ``withStream(descriptor:_:)``
  /// should result in an ``RPCError`` with code ``RPCError/Code/failedPrecondition`` being thrown.
  ///
  /// If you want to forcefully cancel all active streams then cancel the task running ``connect(lazily:)``.
  public func close() {
    self.state.withLockedValue { state in
      switch state {
      case .unconnected:
        state = .closed(0, nil)
      case .connected(_, let openStreams, let signalEndConnection):
        state = .closed(openStreams, signalEndConnection)
        if openStreams == 0 {
          signalEndConnection.finish()
        }
      case .closed:
        ()
      }
    }
  }

  private enum WithStreamResult {
    case success
    case pending(AsyncStream<Void>)
  }

  /// Opens a stream using the transport, and uses it as input into a user-provided closure.
  ///
  /// - Important: The opened stream is closed after the closure is finished.
  ///
  /// Transport implementations should throw an ``RPCError`` with the following error codes:
  /// - ``RPCError/Code/failedPrecondition`` if the transport is closing or has been closed.
  /// - ``RPCError/Code/unavailable`` if it's temporarily not possible to create a stream and it
  ///   may be possible after some backoff period.
  ///
  ///   This implementation will queue any streams (and thus block this call) if this function is called before
  ///   ``connect(lazily:)``, until a connection is established - at which point all streams will be
  ///   created.
  ///
  /// - Parameters:
  ///   - descriptor: A description of the method to open a stream for.
  ///   - closure: A closure that takes the opened stream as parameter.
  /// - Returns: Whatever value was returned from `closure`.
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

    let result: Result<WithStreamResult, RPCError> = self.state.withLockedValue { state in
      switch state {
      case .connected(let serverTransport, let openStreams, let signalEndConnection):
        do {
          try serverTransport.acceptStream(serverStream)
          state = .connected(serverTransport, openStreams + 1, signalEndConnection)
        } catch let acceptStreamError as RPCError {
          return .failure(acceptStreamError)
        } catch {
          return .failure(RPCError(code: .unknown, message: "Unknown error: \(error)."))
        }
        return .success(.success)

      case .unconnected(let serverTransport, var pendingStreams):
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        pendingStreams.append(continuation)
        state = .unconnected(serverTransport, pendingStreams)
        return .success(.pending(stream))

      case .closed:
        return .failure(
          RPCError(
            code: .failedPrecondition,
            message: "The client transport is closed."
          )
        )
      }
    }

    let withStreamResult: WithStreamResult
    do {
      withStreamResult = try result.get()
    } catch {
      serverStream.outbound.finish()
      clientStream.outbound.finish()
      throw error
    }

    switch withStreamResult {
    case .success:
      ()
    case .pending(let pendingStream):
      for await _ in pendingStream {
        // This loop will exit either when the task is cancelled or when the
        // client connects and this stream can be opened.
      }
      try Task.checkCancellation()

      try self.state.withLockedValue { state in
        switch state {
        case .unconnected:
          fatalError("Invalid state.")
        case .connected(let serverTransport, let openStreams, let signalEndConnection):
          do {
            try serverTransport.acceptStream(serverStream)
            state = .connected(serverTransport, openStreams + 1, signalEndConnection)
          } catch let acceptStreamError as RPCError {
            throw acceptStreamError
          } catch {
            throw RPCError(code: .unknown, message: "Unknown error: \(error).")
          }
        case .closed:
          serverStream.outbound.finish()
          clientStream.outbound.finish()
          throw RPCError(
            code: .failedPrecondition,
            message: "The client transport is closed."
          )
        }
      }
    }

    defer {
      self.state.withLockedValue { state in
        switch state {
        case .unconnected:
          fatalError("Invalid state")
        case .connected(let serverTransport, let openStreams, let signalEndContinuation):
          state = .connected(serverTransport, openStreams - 1, signalEndContinuation)
        case .closed(let openStreams, let signalEndConnection):
          if openStreams == 1 {
            // This was the last open stream: signal the closure of the client.
            signalEndConnection?.finish()
          }
        }
      }
    }

    let userResult = try await closure(clientStream)

    serverStream.outbound.finish()
    clientStream.outbound.finish()

    return userResult
  }

  /// Returns the execution configuration for a given method.
  ///
  /// - Parameter descriptor: The method to lookup configuration for.
  /// - Returns: Execution configuration for the method, if it exists.
  public func executionConfiguration(
    forMethod descriptor: MethodDescriptor
  ) -> ClientRPCExecutionConfiguration? {
    self.executionConfigurations[descriptor]
  }
}
