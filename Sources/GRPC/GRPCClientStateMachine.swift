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
import NIO
import NIOHTTP1
import Logging
import SwiftProtobuf

enum ReceiveResponseHeadError: Error, Equatable {
  /// The 'content-type' header was missing or the value is not supported by this implementation.
  case invalidContentType

  /// The HTTP response status from the server was not 200 OK.
  case invalidHTTPStatus(HTTPResponseStatus)

  /// The encoding used by the server is not supported.
  case unsupportedMessageEncoding

  /// An invalid state was encountered. This is a serious implementation error.
  case invalidState
}

enum SendEndOfRequestStreamError: Error {
  /// The request stream has already been closed.
  case alreadyClosed

  /// An invalid state was encountered. This is a serious implementation error.
  case invalidState
}

  /// An invalid state was encountered. This is a serious implementation error.
struct InvalidStateError: Error {
  static let invalidState = InvalidStateError()
}

/// A state machine for a single gRPC call from the perspective of a client.
///
/// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md
struct GRPCClientStateMachine<Request: Message, Response: Message> {
  /// The combined state of the request (client) and response (server) streams for an RPC call.
  ///
  /// The following states are not possible:
  /// - `.clientIdleServerStreaming`: The client must initiate the call before the server moves
  ///   from the idle state.
  /// - `.clientIdleServerClosed`: The client must initiate the call before the server moves from
  ///   the idle state.
  /// - `.clientStreamingServerClosed`: The client may not stream if the server is closed.
  enum State {
    /// Initial state. Neither request stream nor response stream have been initiated. Holds the
    /// pending write state for the request stream and expected message count for the response
    /// stream, respectively.
    ///
    /// Valid transitions:
    /// - `clientStreamingServerIdle`: if the client initiates the RPC,
    /// - `clientClosedServerClosed`: if the client terminates the RPC.
    case clientIdleServerIdle(client: PendingWriteState, server: MessageCount)

    /// The client has initiated an RPC and has not initial metadata from the server. Holds the
    /// writing state for requests and expected message count for responses.
    ///
    /// Valid transitions:
    /// - `clientStreamingServerStreaming`: if the server acknowledges the RPC initiation,
    /// - `clientClosedServerIdle`: if the client closes the request stream,
    /// - `clientClosedServerClosed`: if the client terminates the RPC or the server terminates the
    ///      RPC with a "trailers-only" response.
    case clientStreamingServerIdle(client: WriteState, server: MessageCount)

    /// The client has indicated to the server that it has finished sending requests. The server
    /// has not yet sent response headers for the RPC. Holds the expected response message count.
    ///
    /// Valid transitions:
    /// - `clientClosedServerStreaming`: if the server acknowledges the RPC initiation,
    /// - `clientClosedServerClosed`: if the client terminates the RPC or the server terminates the
    ///      RPC with a "trailers-only" response.
    case clientClosedServerIdle(server: MessageCount)

    /// The client has initiated the RPC and the server has acknowledged it. Messages may have been
    /// sent and/or received. Holds the request stream write state and response stream read state.
    ///
    /// Valid transitions:
    /// - `clientClosedServerStreaming`: if the client closes the request stream,
    /// - `clientClosedServerClosed`: if the client or server terminates the RPC.
    case clientStreamingServerStreaming(client: WriteState, server: ReadState)

    /// The client has indicated to the server that it has finished sending requests. The server
    /// has acknowledged the RPC. Holds the response stream read state.
    ///
    /// Valid transitions:
    /// - `clientClosedServerClosed`: if the client or server terminate the RPC.
    case clientClosedServerStreaming(server: ReadState)

    /// The RPC has terminated. There are no valid transitions from this state.
    case clientClosedServerClosed
  }

  /// The current state of the state machine.
  internal private(set) var state: State {
    didSet {
      switch (oldValue, self.state) {
      // All valid transitions:
      case (.clientIdleServerIdle, .clientStreamingServerIdle),
           (.clientIdleServerIdle, .clientClosedServerClosed),
           (.clientStreamingServerIdle, .clientStreamingServerStreaming),
           (.clientStreamingServerIdle, .clientClosedServerIdle),
           (.clientStreamingServerIdle, .clientClosedServerClosed),
           (.clientClosedServerIdle, .clientClosedServerStreaming),
           (.clientClosedServerIdle, .clientClosedServerClosed),
           (.clientStreamingServerStreaming, .clientClosedServerStreaming),
           (.clientStreamingServerStreaming, .clientClosedServerClosed),
           (.clientClosedServerStreaming, .clientClosedServerClosed):
        break

      // Self transitions, also valid:
      case (.clientIdleServerIdle, .clientIdleServerIdle),
           (.clientStreamingServerIdle, .clientStreamingServerIdle),
           (.clientClosedServerIdle, .clientClosedServerIdle),
           (.clientStreamingServerStreaming, .clientStreamingServerStreaming),
           (.clientClosedServerStreaming, .clientClosedServerStreaming),
           (.clientClosedServerClosed, .clientClosedServerClosed):
        break

      default:
        preconditionFailure("invalid state transition from '\(oldValue)' to '\(self.state)'")
      }
    }
  }

  private let logger: Logger

  /// Creates a state machine representing a gRPC client's request and response stream state.
  ///
  /// - Parameter requestCount: The arity of the request stream.
  /// - Parameter responseCount: The arity of the response stream.
  /// - Parameter logger: Logger.
  init(
    requestCount: MessageCount,
    responseCount: MessageCount,
    logger: Logger
  ) {
    let pendingWriteState = PendingWriteState(
      expectedCount: requestCount,
      encoding: .none,
      contentType: .protobuf
    )
    self.state = .clientIdleServerIdle(client: pendingWriteState, server: responseCount)
    self.logger = logger
  }

  /// Creates a state machine representing a gRPC client's request and response stream state.
  ///
  /// - Parameter state: The initial state of the state machine.
  /// - Parameter logger: Logger.
  init(
    state: State,
    logger: Logger
  ) {
    self.state = state
    self.logger = logger
  }

  /// Initiates an RPC.
  ///
  /// The only valid state transition is:
  /// - `.clientIdleServerIdle` → `.clientStreamingServerIdle`
  ///
  /// All other states will result in a `.fatal` error.
  ///
  /// On success the state will transition to `.clientStreamingServerIdle`.
  ///
  /// - Parameter host: The host which will handle the RPC.
  /// - Parameter path: The path of the RPC (e.g. '/echo.Echo/Collect').
  /// - Parameter options: Options for this RPC.
  /// - Parameter requestID: The uniuqe ID of this request used for logging.
  mutating func sendRequestHeaders(
    host: String,
    path: String,
    options: CallOptions,
    requestID: String
  ) -> Result<HTTPRequestHead, InvalidStateError> {
    return self.state.sendRequestHeaders(
      host: host,
      path: path,
      options: options,
      requestID: requestID
    )
  }

  /// Formats a request to send to the server.
  ///
  /// The client must be streaming in order for this to return successfully. Therefore the valid
  /// state transitions are:
  /// - `.clientStreamingServerIdle` → `.clientStreamingServerIdle`
  /// - `.clientStreamingServerStreaming` → `.clientStreamingServerStreaming`
  ///
  /// It is invalid (but not fatal) for the client to attempt to send requests once the request
  /// stream is closed. The states are:
  /// - `.clientClosedServerIdle`
  /// - `.clientClosedServerStreaming`
  /// - `.clientClosedServerClosed`
  ///
  /// Sending messages is invald, and fatal, for the following states:
  /// - `.clientIdleServerIdle`
  ///
  /// - Parameter message: The `Request` to send to the server.
  /// - Parameter allocator: A `ByteBufferAllocator` to allocate the buffer into which the encoded
  ///     request will be written.
  mutating func sendRequest(
    _ message: Request,
    allocator: ByteBufferAllocator
  ) -> Result<ByteBuffer, MessageWriteError> {
    return self.state.sendRequest(message, allocator: allocator)
  }

  /// Terminates the request stream.
  ///
  /// The client must be streaming requests in order to terminate the request stream. Valid
  /// states transitions are:
  /// - `.clientStreamingServerIdle` → `.clientClosedServerIdle`
  /// - `.clientStreamingServerStreaming` → `.clientClosedServerStreaming`
  ///
  /// It is invalid (but not fatal) for the client to attempt to close the request stream multiple
  /// times The states in which this is possible are:
  /// - `.clientClosedServerIdle`
  /// - `.clientClosedServerStreaming`
  /// - `.clientClosedServerClosed`
  ///
  /// Closing the request stream is invald, and fatal, for the following states:
  /// - `.clientIdleServerIdle`
  mutating func sendEndOfRequestStream() -> Result<Void, SendEndOfRequestStreamError> {
    return self.state.sendEndOfRequestStream()
  }

  /// Receive an acknowledgement of the RPC from the server. This **must not** be a "trailers-only"
  /// response.
  ///
  /// The server must be idle in order to recive response headers. The valid state transitions are:
  /// - `.clientStreamingServerIdle` → `.clientStreamingServerStreaming`
  /// - `.clientClosedServerIdle` → `.clientClosedServerStreaming`
  ///
  /// It is invalid and fatal for the RPC to receive response headers from the following states:
  /// - `.clientIdleServerIdle`
  /// - `.clientStreamingServerStreaming`
  /// - `.clientClosedServerStreaming`
  /// - `.clientClosedServerClosed`
  ///
  /// - Parameter headers: The headers received from the server.
  mutating func receiveResponseHeaders(
    _ responseHead: HTTPResponseHead
  ) -> Result<HTTPHeaders, ReceiveResponseHeadError> {
    return self.state.receiveResponseHeaders(responseHead, logger: self.logger)
  }

  /// Read a response buffer from the server and return any decoded messages.
  ///
  /// If the response stream has an expected count of `.one` then this function is guaranteed to
  /// produce *at most* one `Response` in the `Result`.
  ///
  /// To receive a response buffer the server must be streaming. Valid states are:
  /// - `.clientClosedServerStreaming` → `.clientClosedServerStreaming`
  /// - `.clientStreamingServerStreaming` → `.clientStreamingServerStreaming`
  ///
  /// It is invalid and fatal to receive a response in the following states:
  /// - `.clientIdleServerIdle`
  /// - `.clientClosedServerStreaming`
  /// - `.clientStreamingServerStreaming`
  /// - `.clientClosedServerClosed`
  ///
  /// - Parameter buffer: A buffer of bytes received from the server.
  mutating func receiveResponse(
    _ buffer: inout ByteBuffer
  ) -> Result<[Response], MessageReadError> {
    return self.state.receiveResponse(&buffer)
  }

  /// Receive the end of the response stream from the server and parse the results into
  /// a `GRPCStatus`.
  ///
  /// To close the response stream the server must be streaming or idle (since the server may choose
  /// to 'fast fail' the RPC). Valid states are:
  /// - `.clientStreamingServerIdle` → `.clientClosedServerClosed`
  /// - `.clientStreamingServerStreaming` → `.clientClosedServerClosed`
  /// - `.clientClosedServerIdle` → `.clientClosedServerClosed`
  /// - `.clientClosedServerStreaming` → `.clientClosedServerClosed`
  ///
  /// It is invalid to receive an end-of-stream if the RPC has not been initiated or has already
  /// been terminated. That is, in one of the following states:
  /// - `.clientIdleServerIdle`
  /// - `.clientClosedServerClosed`
  ///
  /// - Parameter trailers: The trailers to parse.
  mutating func receiveEndOfResponseStream(
    _ trailers: HTTPHeaders
  ) -> Result<GRPCStatus, InvalidStateError> {
    return self.state.receiveEndOfResponseStream(trailers)
  }
}

extension GRPCClientStateMachine.State {
  /// See `GRPCClientStateMachine.sendRequestHeaders(host:path:options:requestID)`.
  mutating func sendRequestHeaders(
    host: String,
    path: String,
    options: CallOptions,
    requestID: String
  ) -> Result<HTTPRequestHead, InvalidStateError> {
    let result: Result<HTTPRequestHead, InvalidStateError>

    switch self {
    case let .clientIdleServerIdle(pendingWriteState, responseArity):
      let head = self.makeRequestHeaders(host: host, path: path, options: options, requestID: requestID)
      result = .success(head)
      self = .clientStreamingServerIdle(client: pendingWriteState.makeWriteState(), server: responseArity)

    case .clientStreamingServerIdle,
         .clientClosedServerIdle,
         .clientClosedServerStreaming,
         .clientStreamingServerStreaming,
         .clientClosedServerClosed:
      result = .failure(.invalidState)
    }

    return result
  }

  /// See `GRPCClientStateMachine.sendRequest(_:allocator:)`.
  mutating func sendRequest(
    _ message: Request,
    allocator: ByteBufferAllocator
  ) -> Result<ByteBuffer, MessageWriteError> {
    let result: Result<ByteBuffer, MessageWriteError>

    switch self {
    case .clientStreamingServerIdle(var writeState, let arity):
      result = writeState.write(message, allocator: allocator)
      self = .clientStreamingServerIdle(client: writeState, server: arity)

    case .clientStreamingServerStreaming(var writeState, let readState):
      result = writeState.write(message, allocator: allocator)
      self = .clientStreamingServerStreaming(client: writeState, server: readState)

    case .clientClosedServerIdle,
         .clientClosedServerStreaming,
         .clientClosedServerClosed:
      result = .failure(.cardinalityViolation)

    case .clientIdleServerIdle:
      result = .failure(.invalidState)
    }

    return result
  }

  /// See `GRPCClientStateMachine.sendEndOfRequestStream()`.
  mutating func sendEndOfRequestStream() -> Result<Void, SendEndOfRequestStreamError> {
    let result: Result<Void, SendEndOfRequestStreamError>

    switch self {
    case .clientStreamingServerIdle(_, let responseArity):
      result = .success(())
      self = .clientClosedServerIdle(server: responseArity)

    case .clientStreamingServerStreaming(_, let readState):
      result = .success(())
      self = .clientClosedServerStreaming(server: readState)

    case .clientClosedServerIdle,
         .clientClosedServerStreaming,
         .clientClosedServerClosed:
      result = .failure(.alreadyClosed)

    case .clientIdleServerIdle:
      result = .failure(.invalidState)
    }

    return result
  }

  /// See `GRPCClientStateMachine.receiveResponseHeaders(_:)`.
  mutating func receiveResponseHeaders(
    _ responseHead: HTTPResponseHead,
    logger: Logger
  ) -> Result<HTTPHeaders, ReceiveResponseHeadError> {
    let result: Result<HTTPHeaders, ReceiveResponseHeadError>

    switch self {
    case let .clientStreamingServerIdle(writeState, responseArity):
      switch self.parseResponseHeaders(responseHead, responseArity: responseArity, logger: logger) {
      case .success(let readState):
        self = .clientStreamingServerStreaming(client: writeState, server: readState)
        result = .success(responseHead.headers)
      case .failure(let error):
        result = .failure(error)
      }

    case let .clientClosedServerIdle(responseArity):
      switch self.parseResponseHeaders(responseHead, responseArity: responseArity, logger: logger) {
      case .success(let readState):
        self = .clientClosedServerStreaming(server: readState)
        result = .success(responseHead.headers)
      case .failure(let error):
        result = .failure(error)
      }

    case .clientIdleServerIdle,
         .clientClosedServerStreaming,
         .clientStreamingServerStreaming,
         .clientClosedServerClosed:
      result = .failure(.invalidState)
    }

    return result
  }

  /// See `GRPCClientStateMachine.receiveResponse(_:)`.
  mutating func receiveResponse(
    _ buffer: inout ByteBuffer
  ) -> Result<[Response], MessageReadError> {
    let result: Result<[Response], MessageReadError>

    switch self {
    case .clientClosedServerStreaming(var readState):
      result = readState.readMessage(&buffer, as: Response.self)
      self = .clientClosedServerStreaming(server: readState)

    case .clientStreamingServerStreaming(let writeState, var readState):
      result = readState.readMessage(&buffer, as: Response.self)
      self = .clientStreamingServerStreaming(client: writeState, server: readState)

    case .clientIdleServerIdle,
         .clientStreamingServerIdle,
         .clientClosedServerIdle,
         .clientClosedServerClosed:
      result = .failure(.invalidState)
    }

    return result
  }

  /// See `GRPCClientStateMachine.receiveEndOfResponseStream(_:)`.
  mutating func receiveEndOfResponseStream(
    _ trailers: HTTPHeaders
  ) -> Result<GRPCStatus, InvalidStateError> {
     let result: Result<GRPCStatus, InvalidStateError>

     switch self {
     case .clientStreamingServerStreaming,
          .clientStreamingServerIdle,
          .clientClosedServerIdle,
          .clientClosedServerStreaming:
       result = .success(self.parseTrailers(trailers))
       self = .clientClosedServerClosed

     case .clientIdleServerIdle,
          .clientClosedServerClosed:
      result = .failure(.invalidState)
     }

     return result
   }

  /// Makes the request headers ("Request-Headers" in the specification) used to initiate an RPC
  /// call.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#requests
  ///
  /// - Important: pseudo-headers (":method", ":scheme", ":path") are not included here and should
  ///     be added elsewhere.
  /// - Parameter host: The host serving the RPC.
  /// - Parameter options: Any options related to the call.
  /// - Parameter requestID: A request ID associated with the call. An additional header will be
  ///     added using this value if `options.requestIDHeader` is specified.
  private func makeRequestHeaders(
    host: String,
    path: String,
    options: CallOptions,
    requestID: String
  ) -> HTTPRequestHead {
    // Note: we don't currently set the 'grpc-encoding' header, if we do we will need to feed that
    // encoded into the message writer.
    var headers: HTTPHeaders = [
      "content-type": "application/grpc",
      "te": "trailers",  // Used to detect incompatible proxies.
      "user-agent": "grpc-swift-nio",  //  TODO: Add a more specific user-agent.
      "host": host,  // NIO's HTTP2ToHTTP1Codec replaces "host" with ":authority"
    ]

    // Add the timeout header, if a timeout was specified.
    if options.timeout != .infinite {
      headers.add(name: GRPCHeaderName.timeout, value: String(describing: options.timeout))
    }

    // Add user-defined custom metadata: this should come after the call definition headers.
    headers.add(contentsOf: options.customMetadata)

    // Add a tracing header if the user specified it.
    if let headerName = options.requestIDHeader {
      headers.add(name: headerName, value: requestID)
    }

    return HTTPRequestHead(
      version: HTTPVersion(major: 2, minor: 0),
      method: options.cacheable ? .GET : .POST,
      uri: path,
      headers: headers
    )
  }

  /// Parses the response headers ("Response-Headers" in the specification) from server into
  /// a `ReadState`.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#responses
  ///
  /// - Parameter headers: The headers to parse.
  private func parseResponseHeaders(
    _ head: HTTPResponseHead,
    responseArity: MessageCount,
    logger: Logger
  ) -> Result<ReadState, ReceiveResponseHeadError> {
    // From: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#responses
    //
    // "Implementations should expect broken deployments to send non-200 HTTP status codes in
    // responses as well as a variety of non-GRPC content-types and to omit Status & Status-Message.
    // Implementations must synthesize a Status & Status-Message to propagate to the application
    // layer when this occurs."
    guard head.status == .ok else {
      return .failure(.invalidHTTPStatus(head.status))
    }

    guard head.headers["content-type"].first?.starts(with: "application/grpc") ?? false else {
      return .failure(.invalidContentType)
    }

    // What compression mechanism is the server using, if any?
    let compression = CompressionMechanism(value: head.headers[GRPCHeaderName.encoding].first)

    // From: https://github.com/grpc/grpc/blob/master/doc/compression.md
    //
    // "If a server sent data which is compressed by an algorithm that is not supported by the
    // client, an INTERNAL error status will occur on the client side."
    guard compression.supported else {
      return .failure(.unsupportedMessageEncoding)
    }

    let reader = LengthPrefixedMessageReader(
      mode: .client,
      compressionMechanism: compression,
      logger: logger
    )

    return .success(.init(expectedCount: responseArity, reader: reader))
  }

  /// Parses the response trailers ("Trailers" in the specification) from the server into
  /// a `GRPCStatus`.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#responses
  ///
  /// - Parameter trailers: Trailers to parse.
  private func parseTrailers(_ trailers: HTTPHeaders) -> GRPCStatus {
    // Extract the "Status"
    let code = trailers[GRPCHeaderName.statusCode].first
      .flatMap(Int.init)
      .flatMap(GRPCStatus.Code.init) ?? .unknown

    // Extract and unmarshall the "Status-Message"
    let message = trailers[GRPCHeaderName.statusMessage].first
      .map(GRPCStatusMessageMarshaller.unmarshall)

    return .init(code: code, message: message)
  }
}
