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
import NIOHPACK
import Logging
import SwiftProtobuf

enum ReceiveResponseHeadError: Error, Equatable {
  /// The 'content-type' header was missing or the value is not supported by this implementation.
  case invalidContentType

  /// The HTTP response status from the server was not 200 OK.
  case invalidHTTPStatus(HTTPResponseStatus?)

  /// The encoding used by the server is not supported.
  case unsupportedMessageEncoding(String)

  /// An invalid state was encountered. This is a serious implementation error.
  case invalidState
}

enum ReceiveEndOfResponseStreamError: Error {
  /// The 'content-type' header was missing or the value is not supported by this implementation.
  case invalidContentType

  /// The HTTP response status from the server was not 200 OK.
  case invalidHTTPStatus(HTTPResponseStatus?)

  /// The HTTP response status from the server was not 200 OK but the "grpc-status" header contained
  /// a valid value.
  case invalidHTTPStatusWithGRPCStatus(GRPCStatus)

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
  /// - Parameter requestHead: The client request head for the RPC.
  mutating func sendRequestHeaders(
    requestHead: GRPCRequestHead
  ) -> Result<HPACKHeaders, SendRequestHeadersError> {
    return self.state.sendRequestHeaders(requestHead: requestHead)
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
  /// - Parameter headers: The headers received from the server.
  mutating func receiveResponseHeaders(
    _ headers: HPACKHeaders
  ) -> Result<Void, ReceiveResponseHeadError> {
    return self.state.receiveResponseHeaders(headers, logger: self.logger)
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
    _ trailers: HPACKHeaders
  ) -> Result<GRPCStatus, ReceiveEndOfResponseStreamError> {
    return self.state.receiveEndOfResponseStream(trailers)
  }
}

extension GRPCClientStateMachine.State {
  /// See `GRPCClientStateMachine.sendRequestHeaders(requestHead:)`.
  mutating func sendRequestHeaders(
    requestHead: GRPCRequestHead
  ) -> Result<HPACKHeaders, SendRequestHeadersError> {
    let result: Result<HPACKHeaders, SendRequestHeadersError>

    switch self {
    case let .clientIdleServerIdle(pendingWriteState, responseArity):
      let headers = self.makeRequestHeaders(
        method: requestHead.method,
        scheme: requestHead.scheme,
        host: requestHead.host,
        path: requestHead.path,
        timeout: requestHead.timeout,
        customMetadata: requestHead.customMetadata
      )
      result = .success(headers)
      self = .clientActiveServerIdle(
        writeState: pendingWriteState.makeWriteState(),
        readArity: responseArity
      )

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

  /// See `GRPCClientStateMachine.receiveResponseHeaders(_:)`.
  mutating func receiveResponseHeaders(
    _ headers: HPACKHeaders,
    logger: Logger
  ) -> Result<Void, ReceiveResponseHeadError> {
    let result: Result<Void, ReceiveResponseHeadError>

    switch self {
    case let .clientActiveServerIdle(writeState, readArity):
      result = self.parseResponseHeaders(headers, arity: readArity, logger: logger).map { readState in
        self = .clientActiveServerActive(writeState: writeState, readState: readState)
      }

    case let .clientClosedServerIdle(readArity):
      result = self.parseResponseHeaders(headers, arity: readArity, logger: logger).map { readState in
        self = .clientClosedServerActive(readState: readState)
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
    _ trailers: HPACKHeaders
  ) -> Result<GRPCStatus, ReceiveEndOfResponseStreamError> {
    let result: Result<GRPCStatus, ReceiveEndOfResponseStreamError>

    switch self {
    case .clientActiveServerIdle,
         .clientClosedServerIdle:
      result = self.parseTrailersOnly(trailers).map { status in
        self = .clientClosedServerClosed
        return status
      }

    case .clientActiveServerActive,
         .clientClosedServerActive:
      result = .success(self.parseTrailers(trailers))
      self = .clientClosedServerClosed

    case .clientIdleServerIdle,
         .clientClosedServerClosed:
      result = .failure(.invalidState)
    }

    return result
  }

  /// Makes the request headers (`Request-Headers` in the specification) used to initiate an RPC
  /// call.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#requests
  ///
  /// - Parameter host: The host serving the RPC.
  /// - Parameter options: Any options related to the call.
  /// - Parameter requestID: A request ID associated with the call. An additional header will be
  ///     added using this value if `options.requestIDHeader` is specified.
  private func makeRequestHeaders(
    method: String,
    scheme: String,
    host: String,
    path: String,
    timeout: GRPCTimeout,
    customMetadata: HPACKHeaders
  ) -> HPACKHeaders {
    // Note: we don't currently set the 'grpc-encoding' header, if we do we will need to feed that
    // encoded into the message writer.
    var headers: HPACKHeaders = [
      ":method": method,
      ":path": path,
      ":authority": host,
      ":scheme": scheme,
      "content-type": "application/grpc+proto",
      "te": "trailers",  // Used to detect incompatible proxies, part of the gRPC specification.
      "user-agent": "grpc-swift-nio",  //  TODO: Add a more specific user-agent.
    ]

    // Add the timeout header, if a timeout was specified.
    if timeout != .infinite {
      headers.add(name: GRPCHeaderName.timeout, value: String(describing: timeout))
    }

    // Add user-defined custom metadata: this should come after the call definition headers.
    headers.add(contentsOf: customMetadata)

    return headers
  }

  /// Parses the response headers ("Response-Headers" in the specification) from the server into
  /// a `ReadState`.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#responses
  ///
  /// - Parameter headers: The headers to parse.
  private func parseResponseHeaders(
    _ headers: HPACKHeaders,
    arity: MessageArity,
    logger: Logger
  ) -> Result<ReadState, ReceiveResponseHeadError> {
    // From: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#responses
    //
    // "Implementations should expect broken deployments to send non-200 HTTP status codes in
    // responses as well as a variety of non-GRPC content-types and to omit Status & Status-Message.
    // Implementations must synthesize a Status & Status-Message to propagate to the application
    // layer when this occurs."
    let statusHeader = headers[":status"].first
    let responseStatus = statusHeader.flatMap(Int.init).map { code in
      HTTPResponseStatus(statusCode: code)
    } ?? .preconditionFailed

    guard responseStatus == .ok else {
      return .failure(.invalidHTTPStatus(responseStatus))
    }

    guard headers["content-type"].first.flatMap(ContentType.init) != nil else {
      return .failure(.invalidContentType)
    }

    // What compression mechanism is the server using, if any?
    let compression = CompressionMechanism(value: headers[GRPCHeaderName.encoding].first)

    // From: https://github.com/grpc/grpc/blob/master/doc/compression.md
    //
    // "If a server sent data which is compressed by an algorithm that is not supported by the
    // client, an INTERNAL error status will occur on the client side."
    guard compression.supported else {
      return .failure(.unsupportedMessageEncoding(compression.rawValue))
    }

    let reader = LengthPrefixedMessageReader(
      mode: .client,
      compressionMechanism: compression,
      logger: logger
    )

    return .success(.reading(arity, reader))
  }

  /// Parses the response trailers ("Trailers" in the specification) from the server into
  /// a `GRPCStatus`.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#responses
  ///
  /// - Parameter trailers: Trailers to parse.
  private func parseTrailers(_ trailers: HPACKHeaders) -> GRPCStatus {
    // Extract the "Status" and "Status-Message"
    let code = self.readStatusCode(from: trailers) ?? .unknown
    let message = self.readStatusMessage(from: trailers)
    return .init(code: code, message: message)
  }

  private func readStatusCode(from trailers: HPACKHeaders) -> GRPCStatus.Code? {
    return trailers[GRPCHeaderName.statusCode].first
      .flatMap(Int.init)
      .flatMap(GRPCStatus.Code.init)
  }

  private func readStatusMessage(from trailers: HPACKHeaders) -> String? {
    return trailers[GRPCHeaderName.statusMessage].first
      .map(GRPCStatusMessageMarshaller.unmarshall)
  }

  /// Parses a "Trailers-Only" response from the server into a `GRPCStatus`.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#responses
  ///
  /// - Parameter trailers: Trailers to parse.
  private func parseTrailersOnly(
    _ trailers: HPACKHeaders
  ) -> Result<GRPCStatus, ReceiveEndOfResponseStreamError> {
    // We need to check whether we have a valid HTTP status in the headers, if we don't then we also
    // need to check whether we have a gRPC status as it should take preference over a synthesising
    // one from the ":status".
    //
    // See: https://github.com/grpc/grpc/blob/master/doc/http-grpc-status-mapping.md
    let statusHeader = trailers[":status"].first
    guard let status = statusHeader.flatMap(Int.init).map({ HTTPResponseStatus(statusCode: $0) })
      else {
        return .failure(.invalidHTTPStatus(nil))
    }

    guard status == .ok else {
      if let code = self.readStatusCode(from: trailers) {
        let message = self.readStatusMessage(from: trailers)
        return .failure(.invalidHTTPStatusWithGRPCStatus(.init(code: code, message: message)))
      } else {
        return .failure(.invalidHTTPStatus(status))
      }
    }

    guard trailers["content-type"].first.flatMap(ContentType.init) != nil else {
      return .failure(.invalidContentType)
    }

    // We've verified the status and content type are okay: parse the trailers.
    return .success(self.parseTrailers(trailers))
  }
}
