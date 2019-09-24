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

enum ReceiveEndOfResponseStreamError: Error {
  /// An invalid state was encountered. This is a serious implementation error.
  case invalidState
}

enum SendRequestHeadersError: Error {
  /// An invalid state was encountered. This is a serious implementation error.
  case invalidState
}

enum SendEndOfRequestStreamError: Error {
  /// The request stream has already been closed. This may happen if the RPC was cancelled, timed
  /// out, the server terminated the RPC, or the user explicitly closed the stream multiple times.
  case alreadyClosed

  /// An invalid state was encountered. This is a serious implementation error.
  case invalidState
}

/// A state machine for a single gRPC call from the perspective of a client.
///
/// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md
struct GRPCClientStateMachine<Request: Message, Response: Message> {
  /// The combined state of the request (client) and response (server) streams for an RPC call.
  ///
  /// The following states are not possible:
  /// - `.clientIdleServerActive`: The client must initiate the call before the server moves
  ///   from the idle state.
  /// - `.clientIdleServerClosed`: The client must initiate the call before the server moves from
  ///   the idle state.
  /// - `.clientActiveServerClosed`: The client may not stream if the server is closed.
  ///
  /// Note: when a peer (client or server) state is "active" it means that messages _may_ be sent or
  /// received. That is, the headers for the stream have been processed by the state machine and
  /// end-of-stream has not yet been processed. A stream may expect any number of messages (i.e. up
  /// to one for a unary call and many for a streaming call).
  enum State {
    /// Initial state. Neither request stream nor response stream have been initiated. Holds the
    /// pending write state for the request stream and arity for the response stream, respectively.
    ///
    /// Valid transitions:
    /// - `clientActiveServerIdle`: if the client initiates the RPC,
    /// - `clientClosedServerClosed`: if the client terminates the RPC.
    case clientIdleServerIdle(pendingWriteState: PendingWriteState, readArity: MessageArity)

    /// The client has initiated an RPC and has not received initial metadata from the server. Holds
    /// the writing state for request stream and arity for the response stream.
    ///
    /// Valid transitions:
    /// - `clientActiveServerActive`: if the server acknowledges the RPC initiation,
    /// - `clientClosedServerIdle`: if the client closes the request stream,
    /// - `clientClosedServerClosed`: if the client terminates the RPC or the server terminates the
    ///      RPC with a "trailers-only" response.
    case clientActiveServerIdle(writeState: WriteState, readArity: MessageArity)

    /// The client has indicated to the server that it has finished sending requests. The server
    /// has not yet sent response headers for the RPC. Holds the response stream arity.
    ///
    /// Valid transitions:
    /// - `clientClosedServerActive`: if the server acknowledges the RPC initiation,
    /// - `clientClosedServerClosed`: if the client terminates the RPC or the server terminates the
    ///      RPC with a "trailers-only" response.
    case clientClosedServerIdle(readArity: MessageArity)

    /// The client has initiated the RPC and the server has acknowledged it. Messages may have been
    /// sent and/or received. Holds the request stream write state and response stream read state.
    ///
    /// Valid transitions:
    /// - `clientClosedServerActive`: if the client closes the request stream,
    /// - `clientClosedServerClosed`: if the client or server terminates the RPC.
    case clientActiveServerActive(writeState: WriteState, readState: ReadState)

    /// The client has indicated to the server that it has finished sending requests. The server
    /// has acknowledged the RPC. Holds the response stream read state.
    ///
    /// Valid transitions:
    /// - `clientClosedServerClosed`: if the client or server terminate the RPC.
    case clientClosedServerActive(readState: ReadState)

    /// The RPC has terminated. There are no valid transitions from this state.
    case clientClosedServerClosed
  }

  /// The current state of the state machine.
  internal private(set) var state: State {
    didSet {
      switch (oldValue, self.state) {
      // All valid transitions:
      case (.clientIdleServerIdle, .clientActiveServerIdle),
           (.clientIdleServerIdle, .clientClosedServerClosed),
           (.clientActiveServerIdle, .clientActiveServerActive),
           (.clientActiveServerIdle, .clientClosedServerIdle),
           (.clientActiveServerIdle, .clientClosedServerClosed),
           (.clientClosedServerIdle, .clientClosedServerActive),
           (.clientClosedServerIdle, .clientClosedServerClosed),
           (.clientActiveServerActive, .clientClosedServerActive),
           (.clientActiveServerActive, .clientClosedServerClosed),
           (.clientClosedServerActive, .clientClosedServerClosed):
        break

      // Self transitions, also valid:
      case (.clientIdleServerIdle, .clientIdleServerIdle),
           (.clientActiveServerIdle, .clientActiveServerIdle),
           (.clientClosedServerIdle, .clientClosedServerIdle),
           (.clientActiveServerActive, .clientActiveServerActive),
           (.clientClosedServerActive, .clientClosedServerActive),
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
  /// - Parameter requestArity: The expected number of messages on the request stream.
  /// - Parameter responseArity: The expected number of messages on the response stream.
  /// - Parameter logger: Logger.
  init(
    requestArity: MessageArity,
    responseArity: MessageArity,
    logger: Logger
  ) {
    self.state = .clientIdleServerIdle(
      pendingWriteState: .init(arity: requestArity, compression: .none, contentType: .protobuf),
      readArity: responseArity
    )
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
  /// - `.clientIdleServerIdle` → `.clientActiveServerIdle`
  ///
  /// All other states will result in an `.invalidState` error.
  ///
  /// On success the state will transition to `.clientActiveServerIdle`.
  ///
  /// - Parameter host: The host which will handle the RPC.
  /// - Parameter path: The path of the RPC (e.g. '/echo.Echo/Collect').
  /// - Parameter options: Options for this RPC.
  /// - Parameter requestID: The unique ID of this request used for logging.
  mutating func sendRequestHead(
    host: String,
    path: String,
    options: CallOptions,
    requestID: String
  ) -> Result<HTTPRequestHead, SendRequestHeadersError> {
    return self.state.sendRequestHead(
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
  /// - `.clientActiveServerIdle` → `.clientActiveServerIdle`
  /// - `.clientActiveServerActive` → `.clientActiveServerActive`
  ///
  /// The client should not attempt to send requests once the request stream is closed, that is
  /// from one of the following states:
  /// - `.clientClosedServerIdle`
  /// - `.clientClosedServerActive`
  /// - `.clientClosedServerClosed`
  /// Doing so will result in a `.cardinalityViolation`.
  ///
  /// Sending a message when both peers are idle (in the `.clientIdleServerIdle` state) will result
  /// in a `.invalidState` error.
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

  /// Closes the request stream.
  ///
  /// The client must be streaming requests in order to terminate the request stream. Valid
  /// states transitions are:
  /// - `.clientActiveServerIdle` → `.clientClosedServerIdle`
  /// - `.clientActiveServerActive` → `.clientClosedServerActive`
  ///
  /// The client should not attempt to close the request stream if it is already closed, that is
  /// from one of the following states:
  /// - `.clientClosedServerIdle`
  /// - `.clientClosedServerActive`
  /// - `.clientClosedServerClosed`
  /// Doing so will result in an `.alreadyClosed` error.
  ///
  /// Closing the request stream when both peers are idle (in the `.clientIdleServerIdle` state)
  /// will result in a `.invalidState` error.
  mutating func sendEndOfRequestStream() -> Result<Void, SendEndOfRequestStreamError> {
    return self.state.sendEndOfRequestStream()
  }

  /// Receive an acknowledgement of the RPC from the server. This **must not** be a "Trailers-Only"
  /// response.
  ///
  /// The server must be idle in order to receive response headers. The valid state transitions are:
  /// - `.clientActiveServerIdle` → `.clientActiveServerActive`
  /// - `.clientClosedServerIdle` → `.clientClosedServerActive`
  ///
  /// The response head will be parsed and validated against the gRPC specification. The following
  /// errors may be returned:
  /// - `.invalidHTTPStatus` if the status was not "200",
  /// - `.invalidContentType` if the "content-type" header does not start with "application/grpc",
  /// - `.unsupportedMessageEncoding` if the "grpc-encoding" header is not supported.
  ///
  /// It is not possible to receive response headers from the following states:
  /// - `.clientIdleServerIdle`
  /// - `.clientActiveServerActive`
  /// - `.clientClosedServerActive`
  /// - `.clientClosedServerClosed`
  /// Doing so will result in a `.invalidState` error.
  ///
  /// - Parameter responseHead: The response head received from the server.
  mutating func receiveResponseHead(
    _ responseHead: HTTPResponseHead
  ) -> Result<HTTPHeaders, ReceiveResponseHeadError> {
    return self.state.receiveResponseHead(responseHead, logger: self.logger)
  }

  /// Read a response buffer from the server and return any decoded messages.
  ///
  /// If the response stream has an expected count of `.one` then this function is guaranteed to
  /// produce *at most* one `Response` in the `Result`.
  ///
  /// To receive a response buffer the server must be streaming. Valid states are:
  /// - `.clientClosedServerActive` → `.clientClosedServerActive`
  /// - `.clientActiveServerActive` → `.clientActiveServerActive`
  ///
  /// This function will read all of the bytes in the `buffer` and attempt to produce as many
  /// messages as possible. This may lead to a number of errors:
  /// - `.cardinalityViolation` if more than one message is received when the state reader is
  ///   expects at most one.
  /// - `.leftOverBytes` if bytes remain in the buffer after reading one message when at most one
  ///   message is expected.
  /// - `.deserializationFailed` if the message could not be deserialized.
  ///
  /// It is not possible to receive response headers from the following states:
  /// - `.clientIdleServerIdle`
  /// - `.clientClosedServerActive`
  /// - `.clientActiveServerActive`
  /// - `.clientClosedServerClosed`
  /// Doing so will result in a `.invalidState` error.
  ///
  /// - Parameter buffer: A buffer of bytes received from the server.
  mutating func receiveResponseBuffer(
    _ buffer: inout ByteBuffer
  ) -> Result<[Response], MessageReadError> {
    return self.state.receiveResponseBuffer(&buffer)
  }

  /// Receive the end of the response stream from the server and parse the results into
  /// a `GRPCStatus`.
  ///
  /// To close the response stream the server must be streaming or idle (since the server may choose
  /// to 'fast fail' the RPC). Valid states are:
  /// - `.clientActiveServerIdle` → `.clientClosedServerClosed`
  /// - `.clientActiveServerActive` → `.clientClosedServerClosed`
  /// - `.clientClosedServerIdle` → `.clientClosedServerClosed`
  /// - `.clientClosedServerActive` → `.clientClosedServerClosed`
  ///
  /// It is not possible to receive an end-of-stream if the RPC has not been initiated or has
  /// already been terminated. That is, in one of the following states:
  /// - `.clientIdleServerIdle`
  /// - `.clientClosedServerClosed`
  /// Doing so will result in a `.invalidState` error.
  ///
  /// - Parameter trailers: The trailers to parse.
  mutating func receiveEndOfResponseStream(
    _ trailers: HTTPHeaders
  ) -> Result<GRPCStatus, ReceiveEndOfResponseStreamError> {
    return self.state.receiveEndOfResponseStream(trailers)
  }
}

extension GRPCClientStateMachine.State {
  /// See `GRPCClientStateMachine.sendRequestHead(host:path:options:requestID)`.
  mutating func sendRequestHead(
    host: String,
    path: String,
    options: CallOptions,
    requestID: String
  ) -> Result<HTTPRequestHead, SendRequestHeadersError> {
    let result: Result<HTTPRequestHead, SendRequestHeadersError>

    switch self {
    case let .clientIdleServerIdle(pendingWriteState, readArity):
      let head = self.makeRequestHead(host: host, path: path, options: options, requestID: requestID)
      result = .success(head)
      self = .clientActiveServerIdle(writeState: pendingWriteState.makeWriteState(), readArity: readArity)

    case .clientActiveServerIdle,
         .clientClosedServerIdle,
         .clientClosedServerActive,
         .clientActiveServerActive,
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
    case .clientActiveServerIdle(var writeState, let readArity):
      result = writeState.write(message, allocator: allocator)
      self = .clientActiveServerIdle(writeState: writeState, readArity: readArity)

    case .clientActiveServerActive(var writeState, let readState):
      result = writeState.write(message, allocator: allocator)
      self = .clientActiveServerActive(writeState: writeState, readState: readState)

    case .clientClosedServerIdle,
         .clientClosedServerActive,
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
    case .clientActiveServerIdle(_, let readArity):
      result = .success(())
      self = .clientClosedServerIdle(readArity: readArity)

    case .clientActiveServerActive(_, let readState):
      result = .success(())
      self = .clientClosedServerActive(readState: readState)

    case .clientClosedServerIdle,
         .clientClosedServerActive,
         .clientClosedServerClosed:
      result = .failure(.alreadyClosed)

    case .clientIdleServerIdle:
      result = .failure(.invalidState)
    }

    return result
  }

  /// See `GRPCClientStateMachine.receiveResponseHead(_:)`.
  mutating func receiveResponseHead(
    _ responseHead: HTTPResponseHead,
    logger: Logger
  ) -> Result<HTTPHeaders, ReceiveResponseHeadError> {
    let result: Result<HTTPHeaders, ReceiveResponseHeadError>

    switch self {
    case let .clientActiveServerIdle(writeState, readArity):
      switch self.parseResponseHead(responseHead, responseArity: readArity, logger: logger) {
      case .success(let readState):
        self = .clientActiveServerActive(writeState: writeState, readState: readState)
        result = .success(responseHead.headers)
      case .failure(let error):
        result = .failure(error)
      }

    case let .clientClosedServerIdle(readArity):
      switch self.parseResponseHead(responseHead, responseArity: readArity, logger: logger) {
      case .success(let readState):
        self = .clientClosedServerActive(readState: readState)
        result = .success(responseHead.headers)
      case .failure(let error):
        result = .failure(error)
      }

    case .clientIdleServerIdle,
         .clientClosedServerActive,
         .clientActiveServerActive,
         .clientClosedServerClosed:
      result = .failure(.invalidState)
    }

    return result
  }

  /// See `GRPCClientStateMachine.receiveResponseBuffer(_:)`.
  mutating func receiveResponseBuffer(
    _ buffer: inout ByteBuffer
  ) -> Result<[Response], MessageReadError> {
    let result: Result<[Response], MessageReadError>

    switch self {
    case .clientClosedServerActive(var readState):
      result = readState.readMessages(&buffer)
      self = .clientClosedServerActive(readState: readState)

    case .clientActiveServerActive(let writeState, var readState):
      result = readState.readMessages(&buffer)
      self = .clientActiveServerActive(writeState: writeState, readState: readState)

    case .clientIdleServerIdle,
         .clientActiveServerIdle,
         .clientClosedServerIdle,
         .clientClosedServerClosed:
      result = .failure(.invalidState)
    }

    return result
  }

  /// See `GRPCClientStateMachine.receiveEndOfResponseStream(_:)`.
  mutating func receiveEndOfResponseStream(
    _ trailers: HTTPHeaders
  ) -> Result<GRPCStatus, ReceiveEndOfResponseStreamError> {
     let result: Result<GRPCStatus, ReceiveEndOfResponseStreamError>

     switch self {
     case .clientActiveServerActive,
          .clientActiveServerIdle,
          .clientClosedServerIdle,
          .clientClosedServerActive:
       result = .success(self.parseTrailers(trailers))
       self = .clientClosedServerClosed

     case .clientIdleServerIdle,
          .clientClosedServerClosed:
      result = .failure(.invalidState)
     }

     return result
   }

  /// Makes the request head (`Request-Headers` in the specification) used to initiate an RPC
  /// call.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#requests
  ///
  /// - Parameter host: The host serving the RPC.
  /// - Parameter options: Any options related to the call.
  /// - Parameter requestID: A request ID associated with the call. An additional header will be
  ///     added using this value if `options.requestIDHeader` is specified.
  private func makeRequestHead(
    host: String,
    path: String,
    options: CallOptions,
    requestID: String
  ) -> HTTPRequestHead {
    // Note: we don't currently set the 'grpc-encoding' header, if we do we will need to feed that
    // encoded into the message writer.
    var headers: HTTPHeaders = [
      "content-type": "application/grpc",
      "te": "trailers",  // Used to detect incompatible proxies, part of the gRPC specification.
      "user-agent": "grpc-swift-nio",  // TODO: Add a more specific user-agent.
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

  /// Parses the response head ("Response-Headers" in the specification) from server into
  /// a `ReadState`.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#responses
  ///
  /// - Parameter headers: The headers to parse.
  private func parseResponseHead(
    _ head: HTTPResponseHead,
    responseArity: MessageArity,
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

    return .success(.reading(responseArity, reader))
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
