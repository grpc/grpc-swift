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
import Logging
import NIOCore
import NIOHPACK
import NIOHTTP1
import SwiftProtobuf

enum ReceiveResponseHeadError: Error, Equatable {
  /// The 'content-type' header was missing or the value is not supported by this implementation.
  case invalidContentType(String?)

  /// The HTTP response status from the server was not 200 OK.
  case invalidHTTPStatus(String?)

  /// The encoding used by the server is not supported.
  case unsupportedMessageEncoding(String)

  /// An invalid state was encountered. This is a serious implementation error.
  case invalidState
}

enum ReceiveEndOfResponseStreamError: Error, Equatable {
  /// The 'content-type' header was missing or the value is not supported by this implementation.
  case invalidContentType(String?)

  /// The HTTP response status from the server was not 200 OK.
  case invalidHTTPStatus(String?)

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
struct GRPCClientStateMachine {
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
    case clientActiveServerIdle(writeState: WriteState, pendingReadState: PendingReadState)

    /// The client has indicated to the server that it has finished sending requests. The server
    /// has not yet sent response headers for the RPC. Holds the response stream arity.
    ///
    /// Valid transitions:
    /// - `clientClosedServerActive`: if the server acknowledges the RPC initiation,
    /// - `clientClosedServerClosed`: if the client terminates the RPC or the server terminates the
    ///      RPC with a "trailers-only" response.
    case clientClosedServerIdle(pendingReadState: PendingReadState)

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

    /// This isn't a real state. See `withStateAvoidingCoWs`.
    case modifying
  }

  /// The current state of the state machine.
  internal private(set) var state: State

  /// The default user-agent string.
  private static let userAgent = "grpc-swift-nio/\(Version.versionString)"

  /// Creates a state machine representing a gRPC client's request and response stream state.
  ///
  /// - Parameter requestArity: The expected number of messages on the request stream.
  /// - Parameter responseArity: The expected number of messages on the response stream.
  init(requestArity: MessageArity, responseArity: MessageArity) {
    self.state = .clientIdleServerIdle(
      pendingWriteState: .init(arity: requestArity, contentType: .protobuf),
      readArity: responseArity
    )
  }

  /// Creates a state machine representing a gRPC client's request and response stream state.
  ///
  /// - Parameter state: The initial state of the state machine.
  init(state: State) {
    self.state = state
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
    requestHead: _GRPCRequestHead
  ) -> Result<HPACKHeaders, SendRequestHeadersError> {
    return self.withStateAvoidingCoWs { state in
      state.sendRequestHeaders(requestHead: requestHead)
    }
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
  /// - Parameter message: The serialized request to send to the server.
  /// - Parameter compressed: Whether the request should be compressed.
  /// - Parameter allocator: A `ByteBufferAllocator` to allocate the buffer into which the encoded
  ///     request will be written.
  mutating func sendRequest(
    _ message: ByteBuffer,
    compressed: Bool,
    allocator: ByteBufferAllocator
  ) -> Result<ByteBuffer, MessageWriteError> {
    return self.withStateAvoidingCoWs { state in
      state.sendRequest(message, compressed: compressed, allocator: allocator)
    }
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
    return self.withStateAvoidingCoWs { state in
      state.sendEndOfRequestStream()
    }
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
    return self.withStateAvoidingCoWs { state in
      state.receiveResponseHeaders(headers)
    }
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
    _ buffer: inout ByteBuffer,
    maxMessageLength: Int
  ) -> Result<[ByteBuffer], MessageReadError> {
    return self.withStateAvoidingCoWs { state in
      state.receiveResponseBuffer(&buffer, maxMessageLength: maxMessageLength)
    }
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
    return self.withStateAvoidingCoWs { state in
      state.receiveEndOfResponseStream(trailers)
    }
  }

  /// Receive a DATA frame with the end stream flag set. Determines whether it is safe for the
  /// caller to ignore the end stream flag or whether a synthesised status should be forwarded.
  ///
  /// Receiving a DATA frame with the end stream flag set is unexpected: the specification dictates
  /// that an RPC should be ended by the server sending the client a HEADERS frame with end stream
  /// set. However, we will tolerate end stream on a DATA frame if we believe the RPC has already
  /// completed (i.e. we are in the 'clientClosedServerClosed' state). In cases where we don't
  /// expect end of stream on a DATA frame we will emit a status with a message explaining
  /// the protocol violation.
  mutating func receiveEndOfResponseStream() -> GRPCStatus? {
    return self.withStateAvoidingCoWs { state in
      state.receiveEndOfResponseStream()
    }
  }

  /// Temporarily sets `self.state` to `.modifying` before calling the provided block and setting
  /// `self.state` to the `State` modified by the block.
  ///
  /// Since we hold state as associated data on our `State` enum, any modification to that state
  /// will trigger a copy on write for its heap allocated data. Temporarily setting the `self.state`
  /// to `.modifying` allows us to avoid an extra reference to any heap allocated data and therefore
  /// avoid a copy on write.
  @inline(__always)
  private mutating func withStateAvoidingCoWs<ResultType>(
    _ body: (inout State) -> ResultType
  ) -> ResultType {
    var state = State.modifying
    swap(&self.state, &state)
    defer {
      swap(&self.state, &state)
    }
    return body(&state)
  }
}

extension GRPCClientStateMachine.State {
  /// See `GRPCClientStateMachine.sendRequestHeaders(requestHead:)`.
  mutating func sendRequestHeaders(
    requestHead: _GRPCRequestHead
  ) -> Result<HPACKHeaders, SendRequestHeadersError> {
    let result: Result<HPACKHeaders, SendRequestHeadersError>

    switch self {
    case let .clientIdleServerIdle(pendingWriteState, responseArity):
      let headers = self.makeRequestHeaders(
        method: requestHead.method,
        scheme: requestHead.scheme,
        host: requestHead.host,
        path: requestHead.path,
        timeout: GRPCTimeout(deadline: requestHead.deadline),
        customMetadata: requestHead.customMetadata,
        compression: requestHead.encoding
      )
      result = .success(headers)

      self = .clientActiveServerIdle(
        writeState: pendingWriteState.makeWriteState(messageEncoding: requestHead.encoding),
        pendingReadState: .init(arity: responseArity, messageEncoding: requestHead.encoding)
      )

    case .clientActiveServerIdle,
         .clientClosedServerIdle,
         .clientClosedServerActive,
         .clientActiveServerActive,
         .clientClosedServerClosed:
      result = .failure(.invalidState)

    case .modifying:
      preconditionFailure("State left as 'modifying'")
    }

    return result
  }

  /// See `GRPCClientStateMachine.sendRequest(_:allocator:)`.
  mutating func sendRequest(
    _ message: ByteBuffer,
    compressed: Bool,
    allocator: ByteBufferAllocator
  ) -> Result<ByteBuffer, MessageWriteError> {
    let result: Result<ByteBuffer, MessageWriteError>

    switch self {
    case .clientActiveServerIdle(var writeState, let pendingReadState):
      result = writeState.write(message, compressed: compressed, allocator: allocator)
      self = .clientActiveServerIdle(writeState: writeState, pendingReadState: pendingReadState)

    case .clientActiveServerActive(var writeState, let readState):
      result = writeState.write(message, compressed: compressed, allocator: allocator)
      self = .clientActiveServerActive(writeState: writeState, readState: readState)

    case .clientClosedServerIdle,
         .clientClosedServerActive,
         .clientClosedServerClosed:
      result = .failure(.cardinalityViolation)

    case .clientIdleServerIdle:
      result = .failure(.invalidState)

    case .modifying:
      preconditionFailure("State left as 'modifying'")
    }

    return result
  }

  /// See `GRPCClientStateMachine.sendEndOfRequestStream()`.
  mutating func sendEndOfRequestStream() -> Result<Void, SendEndOfRequestStreamError> {
    let result: Result<Void, SendEndOfRequestStreamError>

    switch self {
    case let .clientActiveServerIdle(_, pendingReadState):
      result = .success(())
      self = .clientClosedServerIdle(pendingReadState: pendingReadState)

    case let .clientActiveServerActive(_, readState):
      result = .success(())
      self = .clientClosedServerActive(readState: readState)

    case .clientClosedServerIdle,
         .clientClosedServerActive,
         .clientClosedServerClosed:
      result = .failure(.alreadyClosed)

    case .clientIdleServerIdle:
      result = .failure(.invalidState)

    case .modifying:
      preconditionFailure("State left as 'modifying'")
    }

    return result
  }

  /// See `GRPCClientStateMachine.receiveResponseHeaders(_:)`.
  mutating func receiveResponseHeaders(
    _ headers: HPACKHeaders
  ) -> Result<Void, ReceiveResponseHeadError> {
    let result: Result<Void, ReceiveResponseHeadError>

    switch self {
    case let .clientActiveServerIdle(writeState, pendingReadState):
      result = self.parseResponseHeaders(headers, pendingReadState: pendingReadState)
        .map { readState in
          self = .clientActiveServerActive(writeState: writeState, readState: readState)
        }

    case let .clientClosedServerIdle(pendingReadState):
      result = self.parseResponseHeaders(headers, pendingReadState: pendingReadState)
        .map { readState in
          self = .clientClosedServerActive(readState: readState)
        }

    case .clientIdleServerIdle,
         .clientClosedServerActive,
         .clientActiveServerActive,
         .clientClosedServerClosed:
      result = .failure(.invalidState)

    case .modifying:
      preconditionFailure("State left as 'modifying'")
    }

    return result
  }

  /// See `GRPCClientStateMachine.receiveResponseBuffer(_:)`.
  mutating func receiveResponseBuffer(
    _ buffer: inout ByteBuffer,
    maxMessageLength: Int
  ) -> Result<[ByteBuffer], MessageReadError> {
    let result: Result<[ByteBuffer], MessageReadError>

    switch self {
    case var .clientClosedServerActive(readState):
      result = readState.readMessages(&buffer, maxLength: maxMessageLength)
      self = .clientClosedServerActive(readState: readState)

    case .clientActiveServerActive(let writeState, var readState):
      result = readState.readMessages(&buffer, maxLength: maxMessageLength)
      self = .clientActiveServerActive(writeState: writeState, readState: readState)

    case .clientIdleServerIdle,
         .clientActiveServerIdle,
         .clientClosedServerIdle,
         .clientClosedServerClosed:
      result = .failure(.invalidState)

    case .modifying:
      preconditionFailure("State left as 'modifying'")
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

    case .modifying:
      preconditionFailure("State left as 'modifying'")
    }

    return result
  }

  /// See `GRPCClientStateMachine.receiveEndOfResponseStream()`.
  mutating func receiveEndOfResponseStream() -> GRPCStatus? {
    let status: GRPCStatus?

    switch self {
    case .clientIdleServerIdle:
      // Can't see end stream before writing on it.
      preconditionFailure()

    case .clientActiveServerIdle,
         .clientActiveServerActive,
         .clientClosedServerIdle,
         .clientClosedServerActive:
      self = .clientClosedServerClosed
      status = .init(
        code: .internalError,
        message: "Protocol violation: received DATA frame with end stream set"
      )

    case .clientClosedServerClosed:
      // We've already closed. Ignore this.
      status = nil

    case .modifying:
      preconditionFailure("State left as 'modifying'")
    }

    return status
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
    customMetadata: HPACKHeaders,
    compression: ClientMessageEncoding
  ) -> HPACKHeaders {
    var headers = HPACKHeaders()
    // The 10 is:
    // - 6 which are required and added just below, and
    // - 4 which are possibly added, depending on conditions.
    headers.reserveCapacity(10 + customMetadata.count)

    // Add the required headers.
    headers.add(name: ":method", value: method)
    headers.add(name: ":path", value: path)
    headers.add(name: ":authority", value: host)
    headers.add(name: ":scheme", value: scheme)
    headers.add(name: "content-type", value: "application/grpc")
    // Used to detect incompatible proxies, part of the gRPC specification.
    headers.add(name: "te", value: "trailers")

    switch compression {
    case let .enabled(configuration):
      // Request encoding.
      if let outbound = configuration.outbound {
        headers.add(name: GRPCHeaderName.encoding, value: outbound.name)
      }

      // Response encoding.
      if !configuration.inbound.isEmpty {
        headers.add(name: GRPCHeaderName.acceptEncoding, value: configuration.acceptEncodingHeader)
      }

    case .disabled:
      ()
    }

    // Add the timeout header, if a timeout was specified.
    if timeout != .infinite {
      headers.add(name: GRPCHeaderName.timeout, value: String(describing: timeout))
    }

    // Add user-defined custom metadata: this should come after the call definition headers.
    // TODO: make header normalization user-configurable.
    headers.add(contentsOf: customMetadata.lazy.map { name, value, indexing in
      (name.lowercased(), value, indexing)
    })

    // Add default user-agent value, if `customMetadata` didn't contain user-agent
    if !customMetadata.contains(name: "user-agent") {
      headers.add(name: "user-agent", value: GRPCClientStateMachine.userAgent)
    }

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
    pendingReadState: PendingReadState
  ) -> Result<ReadState, ReceiveResponseHeadError> {
    // From: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#responses
    //
    // "Implementations should expect broken deployments to send non-200 HTTP status codes in
    // responses as well as a variety of non-GRPC content-types and to omit Status & Status-Message.
    // Implementations must synthesize a Status & Status-Message to propagate to the application
    // layer when this occurs."
    let statusHeader = headers.first(name: ":status")
    let responseStatus = statusHeader
      .flatMap(Int.init)
      .map { code in
        HTTPResponseStatus(statusCode: code)
      } ?? .preconditionFailed

    guard responseStatus == .ok else {
      return .failure(.invalidHTTPStatus(statusHeader))
    }

    let contentTypeHeader = headers.first(name: "content-type")
    guard contentTypeHeader.flatMap(ContentType.init) != nil else {
      return .failure(.invalidContentType(contentTypeHeader))
    }

    let result: Result<ReadState, ReceiveResponseHeadError>

    // What compression mechanism is the server using, if any?
    if let encodingHeader = headers.first(name: GRPCHeaderName.encoding) {
      // Note: the server is allowed to encode messages using an algorithm which wasn't included in
      // the 'grpc-accept-encoding' header. If the client still supports that algorithm (despite not
      // permitting the server to use it) then it must still decode that message. Ideally we should
      // log a message here if that was the case but we don't hold that information.
      if let compression = CompressionAlgorithm(rawValue: encodingHeader) {
        result = .success(pendingReadState.makeReadState(compression: compression))
      } else {
        // The algorithm isn't one we support.
        result = .failure(.unsupportedMessageEncoding(encodingHeader))
      }
    } else {
      // No compression was specified, this is fine.
      result = .success(pendingReadState.makeReadState(compression: nil))
    }

    return result
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
    return trailers.first(name: GRPCHeaderName.statusCode)
      .flatMap(Int.init)
      .flatMap(GRPCStatus.Code.init)
  }

  private func readStatusMessage(from trailers: HPACKHeaders) -> String? {
    return trailers.first(name: GRPCHeaderName.statusMessage)
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
    let statusHeader = trailers.first(name: ":status")
    guard let status = statusHeader.flatMap(Int.init).map({ HTTPResponseStatus(statusCode: $0) })
    else {
      return .failure(.invalidHTTPStatus(statusHeader))
    }

    guard status == .ok else {
      if let code = self.readStatusCode(from: trailers) {
        let message = self.readStatusMessage(from: trailers)
        return .failure(.invalidHTTPStatusWithGRPCStatus(.init(code: code, message: message)))
      } else {
        return .failure(.invalidHTTPStatus(statusHeader))
      }
    }

    // Only validate the content-type header if it's present. This is a small deviation from the
    // spec as the content-type is meant to be sent in "Trailers-Only" responses. However, if it's
    // missing then we should avoid the error and propagate the status code and message sent by
    // the server instead.
    if let contentTypeHeader = trailers.first(name: "content-type"),
      ContentType(value: contentTypeHeader) == nil {
      return .failure(.invalidContentType(contentTypeHeader))
    }

    // We've verified the status and content type are okay: parse the trailers.
    return .success(self.parseTrailers(trailers))
  }
}
