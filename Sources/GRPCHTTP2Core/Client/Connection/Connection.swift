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

package import GRPCCore
package import NIOCore
package import NIOHTTP2
private import Synchronization

/// A `Connection` provides communication to a single remote peer.
///
/// Each `Connection` object is 'one-shot': it may only be used for a single connection over
/// its lifetime. If a connect attempt fails then the `Connection` must be discarded and a new one
/// must be created. However, an active connection may be used multiple times to provide streams
/// to the backend.
///
/// To use the `Connection` you must run it in a task. You can consume event updates by listening
/// to `events`:
///
/// ```swift
/// await withTaskGroup(of: Void.self) { group in
///   group.addTask { await connection.run() }
///
///   for await event in connection.events {
///     switch event {
///     case .connectSucceeded:
///       // ...
///     default:
///       // ...
///     }
///   }
/// }
/// ```
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
package final class Connection: Sendable {
  /// Events which can happen over the lifetime of the connection.
  package enum Event: Sendable {
    /// The connect attempt succeeded and the connection is ready to use.
    case connectSucceeded
    /// The connect attempt failed.
    case connectFailed(any Error)
    /// The connection received a GOAWAY and will close soon. No new streams
    /// should be opened on this connection.
    case goingAway(HTTP2ErrorCode, String)
    /// The connection is closed.
    case closed(Connection.CloseReason)
  }

  /// The reason the connection closed.
  package enum CloseReason: Sendable {
    /// Closed because an idle timeout fired.
    case idleTimeout
    /// Closed because a keepalive timer fired.
    case keepaliveTimeout
    /// Closed because the caller initiated shutdown and all RPCs on the connection finished.
    case initiatedLocally
    /// Closed because the remote peer initiate shutdown (i.e. sent a GOAWAY frame).
    case remote
    /// Closed because the connection encountered an unexpected error.
    case error(any Error, wasIdle: Bool)
  }

  /// Inputs to the 'run' method.
  private enum Input: Sendable {
    case close
  }

  /// Events which have happened to the connection.
  private let event: (stream: AsyncStream<Event>, continuation: AsyncStream<Event>.Continuation)

  /// Events which the connection must react to.
  private let input: (stream: AsyncStream<Input>, continuation: AsyncStream<Input>.Continuation)

  /// The address to connect to.
  private let address: SocketAddress

  /// The default compression algorithm used for requests.
  private let defaultCompression: CompressionAlgorithm

  /// The set of enabled compression algorithms.
  private let enabledCompression: CompressionAlgorithmSet

  /// A connector used to establish a connection.
  private let http2Connector: any HTTP2Connector

  /// The state of the connection.
  private let state: Mutex<State>

  /// The default max request message size in bytes, 4 MiB.
  private static var defaultMaxRequestMessageSizeBytes: Int {
    4 * 1024 * 1024
  }

  /// A stream of events which can happen to the connection.
  package var events: AsyncStream<Event> {
    self.event.stream
  }

  package init(
    address: SocketAddress,
    http2Connector: any HTTP2Connector,
    defaultCompression: CompressionAlgorithm,
    enabledCompression: CompressionAlgorithmSet
  ) {
    self.address = address
    self.defaultCompression = defaultCompression
    self.enabledCompression = enabledCompression
    self.http2Connector = http2Connector
    self.event = AsyncStream.makeStream(of: Event.self)
    self.input = AsyncStream.makeStream(of: Input.self)
    self.state = Mutex(.notConnected)
  }

  /// Connect and run the connection.
  ///
  /// This function returns when the connection has closed. You can observe connection events
  /// by consuming the ``events`` sequence.
  package func run() async {
    let connectResult = await Result {
      try await self.http2Connector.establishConnection(to: self.address)
    }

    switch connectResult {
    case .success(let connected):
      // Connected successfully, update state and report the event.
      self.state.withLock { state in
        state.connected(connected)
      }

      await withDiscardingTaskGroup { group in
        // Add a task to run the connection and consume events.
        group.addTask {
          try? await connected.channel.executeThenClose { inbound, outbound in
            await self.consumeConnectionEvents(inbound)
          }
        }

        // Meanwhile, consume input events. This sequence will end when the connection has closed.
        for await input in self.input.stream {
          switch input {
          case .close:
            let asyncChannel = self.state.withLock { $0.beginClosing() }
            if let channel = asyncChannel?.channel {
              let event = ClientConnectionHandler.OutboundEvent.closeGracefully
              channel.triggerUserOutboundEvent(event, promise: nil)
            }
          }
        }
      }

    case .failure(let error):
      // Connect failed, this connection is no longer useful.
      self.state.withLock { $0.closed() }
      self.finishStreams(withEvent: .connectFailed(error))
    }
  }

  /// Gracefully close the connection.
  package func close() {
    self.input.continuation.yield(.close)
  }

  /// Make a stream using the connection if it's connected.
  ///
  /// - Parameter descriptor: A descriptor of the method to create a stream for.
  /// - Returns: The open stream.
  package func makeStream(
    descriptor: MethodDescriptor,
    options: CallOptions
  ) async throws -> Stream {
    let (multiplexer, scheme) = try self.state.withLock { state in
      switch state {
      case .connected(let connected):
        return (connected.multiplexer, connected.scheme)
      case .notConnected, .closing, .closed:
        throw RPCError(code: .unavailable, message: "subchannel isn't ready")
      }
    }

    let compression: CompressionAlgorithm
    if let override = options.compression {
      compression = self.enabledCompression.contains(override) ? override : .none
    } else {
      compression = self.defaultCompression
    }

    let maxRequestSize = options.maxRequestMessageBytes ?? Self.defaultMaxRequestMessageSizeBytes

    do {
      let stream = try await multiplexer.openStream { channel in
        channel.eventLoop.makeCompletedFuture {
          let streamHandler = GRPCClientStreamHandler(
            methodDescriptor: descriptor,
            scheme: scheme,
            outboundEncoding: compression,
            acceptedEncodings: self.enabledCompression,
            maximumPayloadSize: maxRequestSize
          )
          try channel.pipeline.syncOperations.addHandler(streamHandler)

          return try NIOAsyncChannel(
            wrappingChannelSynchronously: channel,
            configuration: NIOAsyncChannel.Configuration(
              isOutboundHalfClosureEnabled: true,
              inboundType: RPCResponsePart.self,
              outboundType: RPCRequestPart.self
            )
          )
        }
      }

      return Stream(wrapping: stream, descriptor: descriptor)
    } catch {
      throw RPCError(code: .unavailable, message: "subchannel is unavailable", cause: error)
    }
  }

  private func consumeConnectionEvents(
    _ connectionEvents: NIOAsyncChannelInboundStream<ClientConnectionEvent>
  ) async {
    // The connection becomes 'ready' when the initial HTTP/2 SETTINGS frame is received.
    // Establishing a TCP connection is insufficient as the TLS handshake may not complete or the
    // server might not be configured for gRPC or HTTP/2.
    //
    // This state is tracked here so that if the connection events sequence finishes and the
    // connection never became ready then the connection can report that the connect failed.
    var isReady = false

    func makeNeverReadyError(cause: (any Error)?) -> RPCError {
      return RPCError(
        code: .unavailable,
        message: """
          The server accepted the TCP connection but closed the connection before completing \
          the HTTP/2 connection preface.
          """,
        cause: cause
      )
    }

    do {
      var channelCloseReason: ClientConnectionEvent.CloseReason?

      for try await connectionEvent in connectionEvents {
        switch connectionEvent {
        case .ready:
          isReady = true
          self.event.continuation.yield(.connectSucceeded)

        case .closing(let reason):
          self.state.withLock { $0.closing() }

          switch reason {
          case .goAway(let errorCode, let reason):
            // The connection will close at some point soon, yield a notification for this
            // because the close might not be imminent and this could result in address resolution.
            self.event.continuation.yield(.goingAway(errorCode, reason))
          case .idle, .keepaliveExpired, .initiatedLocally, .unexpected:
            // The connection will be closed imminently in these cases there's no need to do
            // anything.
            ()
          }

          // Take the reason with the highest precedence. A GOAWAY may be superseded by user
          // closing, for example.
          if channelCloseReason.map({ reason.precedence > $0.precedence }) ?? true {
            channelCloseReason = reason
          }
        }
      }

      let finalEvent: Event
      if isReady {
        let connectionCloseReason: CloseReason
        switch channelCloseReason {
        case .keepaliveExpired:
          connectionCloseReason = .keepaliveTimeout

        case .idle:
          // Connection became idle, that's fine.
          connectionCloseReason = .idleTimeout

        case .goAway:
          // Remote peer told us to GOAWAY.
          connectionCloseReason = .remote

        case .initiatedLocally:
          // Shutdown was initiated locally.
          connectionCloseReason = .initiatedLocally

        case .unexpected(let error, let isIdle):
          let error = RPCError(
            code: .unavailable,
            message: "The TCP connection was dropped unexpectedly.",
            cause: error
          )
          connectionCloseReason = .error(error, wasIdle: isIdle)

        case .none:
          let error = RPCError(
            code: .unavailable,
            message: "The TCP connection was dropped unexpectedly.",
            cause: nil
          )
          connectionCloseReason = .error(error, wasIdle: true)
        }

        finalEvent = .closed(connectionCloseReason)
      } else {
        // The connection never became ready, this therefore counts as a failed connect attempt.
        finalEvent = .connectFailed(makeNeverReadyError(cause: nil))
      }

      // The connection events sequence has finished: the connection is now closed.
      self.state.withLock { $0.closed() }
      self.finishStreams(withEvent: finalEvent)
    } catch {
      let finalEvent: Event

      if isReady {
        // Any error must come from consuming the inbound channel meaning that the connection
        // must be borked, wrap it up and close.
        let rpcError = RPCError(code: .unavailable, message: "connection closed", cause: error)
        finalEvent = .closed(.error(rpcError, wasIdle: true))
      } else {
        // The connection never became ready, this therefore counts as a failed connect attempt.
        finalEvent = .connectFailed(makeNeverReadyError(cause: error))
      }

      self.state.withLock { $0.closed() }
      self.finishStreams(withEvent: finalEvent)
    }
  }

  private func finishStreams(withEvent event: Event) {
    self.event.continuation.yield(event)
    self.event.continuation.finish()
    self.input.continuation.finish()
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Connection {
  package struct Stream {
    package typealias Inbound = NIOAsyncChannelInboundStream<RPCResponsePart>

    package struct Outbound: ClosableRPCWriterProtocol {
      package typealias Element = RPCRequestPart

      private let requestWriter: NIOAsyncChannelOutboundWriter<RPCRequestPart>
      private let http2Stream: NIOAsyncChannel<RPCResponsePart, RPCRequestPart>

      fileprivate init(
        requestWriter: NIOAsyncChannelOutboundWriter<RPCRequestPart>,
        http2Stream: NIOAsyncChannel<RPCResponsePart, RPCRequestPart>
      ) {
        self.requestWriter = requestWriter
        self.http2Stream = http2Stream
      }

      package func write(_ element: RPCRequestPart) async throws {
        try await self.requestWriter.write(element)
      }

      package func write(contentsOf elements: some Sequence<Self.Element>) async throws {
        try await self.requestWriter.write(contentsOf: elements)
      }

      package func finish() {
        self.requestWriter.finish()
      }

      package func finish(throwing error: any Error) {
        // Fire the error inbound; this fails the inbound writer.
        self.http2Stream.channel.pipeline.fireErrorCaught(error)
      }
    }

    let descriptor: MethodDescriptor

    private let http2Stream: NIOAsyncChannel<RPCResponsePart, RPCRequestPart>

    init(
      wrapping stream: NIOAsyncChannel<RPCResponsePart, RPCRequestPart>,
      descriptor: MethodDescriptor
    ) {
      self.http2Stream = stream
      self.descriptor = descriptor
    }

    package func execute<T>(
      _ closure: (_ inbound: Inbound, _ outbound: Outbound) async throws -> T
    ) async throws -> T where T: Sendable {
      try await self.http2Stream.executeThenClose { inbound, outbound in
        return try await closure(
          inbound,
          Outbound(requestWriter: outbound, http2Stream: self.http2Stream)
        )
      }
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Connection {
  private enum State: Sendable {
    /// The connection is idle or connecting.
    case notConnected
    /// A TCP connection has been established with the remote peer. However, the connection may not
    /// be ready to use yet.
    case connected(Connected)
    /// The connection has started to close. This may be initiated locally or by the remote.
    case closing
    /// The connection has closed. This is a terminal state.
    case closed

    struct Connected: Sendable {
      /// The connection channel.
      var channel: NIOAsyncChannel<ClientConnectionEvent, Void>
      /// Multiplexer for creating HTTP/2 streams.
      var multiplexer: NIOHTTP2Handler.AsyncStreamMultiplexer<Void>
      /// Whether the connection is plaintext, `false` implies TLS is being used.
      var scheme: Scheme

      init(_ connection: HTTP2Connection) {
        self.channel = connection.channel
        self.multiplexer = connection.multiplexer
        self.scheme = connection.isPlaintext ? .http : .https
      }
    }

    mutating func connected(_ channel: HTTP2Connection) {
      switch self {
      case .notConnected:
        self = .connected(State.Connected(channel))
      case .connected, .closing, .closed:
        fatalError("Invalid state: 'run()' must only be called once")
      }
    }

    mutating func beginClosing() -> NIOAsyncChannel<ClientConnectionEvent, Void>? {
      switch self {
      case .notConnected:
        fatalError("Invalid state: 'run()' must be called first")
      case .connected(let connected):
        self = .closing
        return connected.channel
      case .closing, .closed:
        return nil
      }
    }

    mutating func closing() {
      switch self {
      case .notConnected:
        // Not reachable: happens as a result of a connection event, that can only happen if
        // the connection has started (i.e. must be in the 'connected' state or later).
        fatalError("Invalid state")
      case .connected:
        self = .closing
      case .closing, .closed:
        ()
      }
    }

    mutating func closed() {
      self = .closed
    }
  }
}

extension ClientConnectionEvent.CloseReason {
  fileprivate var precedence: Int {
    switch self {
    case .unexpected:
      return -1
    case .goAway:
      return 0
    case .idle:
      return 1
    case .keepaliveExpired:
      return 2
    case .initiatedLocally:
      return 3
    }
  }
}
