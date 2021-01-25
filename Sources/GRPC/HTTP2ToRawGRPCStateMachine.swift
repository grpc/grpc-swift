/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import Logging
import NIO
import NIOHPACK
import NIOHTTP2

struct HTTP2ToRawGRPCStateMachine {
  /// The current state.
  private var state: State

  /// Temporarily sets `self.state` to `._modifying` before calling the provided block and setting
  /// `self.state` to the `State` modified by the block.
  ///
  /// Since we hold state as associated data on our `State` enum, any modification to that state
  /// will trigger a copy on write for its heap allocated data. Temporarily setting the `self.state`
  /// to `._modifying` allows us to avoid an extra reference to any heap allocated data and
  /// therefore avoid a copy on write.
  @inlinable
  internal mutating func withStateAvoidingCoWs<Action>(_ body: (inout State) -> Action) -> Action {
    var state: State = ._modifying
    swap(&self.state, &state)
    defer {
      swap(&self.state, &state)
    }
    return body(&state)
  }

  internal init(
    services: [Substring: CallHandlerProvider],
    encoding: ServerMessageEncoding,
    normalizeHeaders: Bool = true
  ) {
    let state = RequestIdleResponseIdleState(
      services: services,
      encoding: encoding,
      normalizeHeaders: normalizeHeaders
    )

    self.state = .requestIdleResponseIdle(state)
  }
}

extension HTTP2ToRawGRPCStateMachine {
  enum State {
    // Both peers are idle. Nothing has happened to the stream.
    case requestIdleResponseIdle(RequestIdleResponseIdleState)

    // Received valid headers. Nothing has been sent in response.
    case requestOpenResponseIdle(RequestOpenResponseIdleState)

    // Received valid headers and request(s). Response headers have been sent.
    case requestOpenResponseOpen(RequestOpenResponseOpenState)

    // The request stream is closed. Nothing has been sent in response.
    case requestClosedResponseIdle(RequestClosedResponseIdleState)

    // The request stream is closed. Response headers have been sent.
    case requestClosedResponseOpen(RequestClosedResponseOpenState)

    // Both streams are closed. This state is terminal.
    case requestClosedResponseClosed

    // Not a real state. See 'withStateAvoidingCoWs'.
    case _modifying
  }

  struct RequestIdleResponseIdleState {
    /// The service providers, keyed by service name.
    var services: [Substring: CallHandlerProvider]

    /// The encoding configuration for this server.
    var encoding: ServerMessageEncoding

    /// Whether to normalize user-provided metadata.
    var normalizeHeaders: Bool
  }

  struct RequestOpenResponseIdleState {
    /// A length prefixed message reader for request messages.
    var reader: LengthPrefixedMessageReader

    /// A length prefixed message writer for response messages.
    var writer: LengthPrefixedMessageWriter

    /// The content type of the RPC.
    var contentType: ContentType

    /// An accept encoding header to send in the response headers indicating the message encoding
    /// that the server supports.
    var acceptEncoding: String?

    /// A message encoding header to send in the response headers indicating the encoding which will
    /// be used for responses.
    var responseEncoding: String?

    /// Whether to normalize user-provided metadata.
    var normalizeHeaders: Bool

    /// The pipeline configuration state.
    var configurationState: ConfigurationState
  }

  struct RequestClosedResponseIdleState {
    /// A length prefixed message reader for request messages.
    var reader: LengthPrefixedMessageReader

    /// A length prefixed message writer for response messages.
    var writer: LengthPrefixedMessageWriter

    /// The content type of the RPC.
    var contentType: ContentType

    /// An accept encoding header to send in the response headers indicating the message encoding
    /// that the server supports.
    var acceptEncoding: String?

    /// A message encoding header to send in the response headers indicating the encoding which will
    /// be used for responses.
    var responseEncoding: String?

    /// Whether to normalize user-provided metadata.
    var normalizeHeaders: Bool

    /// The pipeline configuration state.
    var configurationState: ConfigurationState

    init(from state: RequestOpenResponseIdleState) {
      self.reader = state.reader
      self.writer = state.writer
      self.contentType = state.contentType
      self.acceptEncoding = state.acceptEncoding
      self.responseEncoding = state.responseEncoding
      self.normalizeHeaders = state.normalizeHeaders
      self.configurationState = state.configurationState
    }
  }

  struct RequestOpenResponseOpenState {
    /// A length prefixed message reader for request messages.
    var reader: LengthPrefixedMessageReader

    /// A length prefixed message writer for response messages.
    var writer: LengthPrefixedMessageWriter

    /// Whether to normalize user-provided metadata.
    var normalizeHeaders: Bool

    init(from state: RequestOpenResponseIdleState) {
      self.reader = state.reader
      self.writer = state.writer
      self.normalizeHeaders = state.normalizeHeaders
    }
  }

  struct RequestClosedResponseOpenState {
    /// A length prefixed message reader for request messages.
    var reader: LengthPrefixedMessageReader

    /// A length prefixed message writer for response messages.
    var writer: LengthPrefixedMessageWriter

    /// Whether to normalize user-provided metadata.
    var normalizeHeaders: Bool

    init(from state: RequestOpenResponseOpenState) {
      self.reader = state.reader
      self.writer = state.writer
      self.normalizeHeaders = state.normalizeHeaders
    }

    init(from state: RequestClosedResponseIdleState) {
      self.reader = state.reader
      self.writer = state.writer
      self.normalizeHeaders = state.normalizeHeaders
    }
  }

  /// The pipeline configuration state.
  enum ConfigurationState {
    /// The pipeline is being configured. Any message data will be buffered into an appropriate
    /// message reader.
    case configuring(HPACKHeaders)

    /// The pipeline is configured.
    case configured

    /// Returns true if the configuration is in the `.configured` state.
    var isConfigured: Bool {
      switch self {
      case .configuring:
        return false
      case .configured:
        return true
      }
    }

    /// Configuration has completed.
    mutating func configured() -> HPACKHeaders {
      switch self {
      case .configured:
        preconditionFailure("Invalid state: already configured")

      case let .configuring(headers):
        self = .configured
        return headers
      }
    }
  }
}

extension HTTP2ToRawGRPCStateMachine {
  enum PipelineConfiguredAction {
    /// Forward the given headers.
    case forwardHeaders(HPACKHeaders)
    /// Forward the given headers and try reading the next message.
    case forwardHeadersAndRead(HPACKHeaders)
  }

  enum ReceiveHeadersAction {
    /// Configure the RPC to use the given server handler.
    case configure(GRPCServerHandlerProtocol)
    /// Reject the RPC by writing out the given headers and setting end-stream.
    case rejectRPC(HPACKHeaders)
  }

  enum ReadNextMessageAction {
    /// Do nothing.
    case none
    /// Forward the buffer.
    case forwardMessage(ByteBuffer)
    /// Forward the buffer and an 'end' of stream request part.
    case forwardMessageAndEnd(ByteBuffer)
    /// Forward the buffer and try reading the next message.
    case forwardMessageThenReadNextMessage(ByteBuffer)
    /// Forward the 'end' of stream request part.
    case forwardEnd
    /// Throw an error down the pipeline.
    case errorCaught(Error)
  }

  struct StateAndReceiveHeadersAction {
    /// The next state.
    var state: State
    /// The action to take.
    var action: ReceiveHeadersAction
  }

  struct StateAndReceiveDataAction {
    /// The next state.
    var state: State
    /// Whether the caller should try reading the next message.
    var tryReading: Bool
  }
}

// MARK: Receive Headers

// This is the only state in which we can receive headers.
extension HTTP2ToRawGRPCStateMachine.RequestIdleResponseIdleState {
  func receive(
    headers: HPACKHeaders,
    eventLoop: EventLoop,
    errorDelegate: ServerErrorDelegate?,
    remoteAddress: SocketAddress?,
    logger: Logger,
    allocator: ByteBufferAllocator,
    responseWriter: GRPCServerResponseWriter
  ) -> HTTP2ToRawGRPCStateMachine.StateAndReceiveHeadersAction {
    // Extract and validate the content type. If it's nil we need to close.
    guard let contentType = self.extractContentType(from: headers) else {
      return self.unsupportedContentType()
    }

    // Now extract the request message encoding and setup an appropriate message reader.
    // We may send back a list of acceptable request message encodings as well.
    let reader: LengthPrefixedMessageReader
    let acceptableRequestEncoding: String?

    switch self.extractRequestEncoding(from: headers) {
    case let .valid(messageReader, acceptEncodingHeader):
      reader = messageReader
      acceptableRequestEncoding = acceptEncodingHeader

    case let .invalid(status, acceptableRequestEncoding):
      return self.invalidRequestEncoding(
        status: status,
        acceptableRequestEncoding: acceptableRequestEncoding,
        contentType: contentType
      )
    }

    // Figure out which encoding we should use for responses.
    let (writer, responseEncoding) = self.extractResponseEncoding(from: headers)

    // Parse the path, and create a call handler.
    guard let path = headers.first(name: ":path") else {
      return self.methodNotImplemented("", contentType: contentType)
    }

    guard let callPath = CallPath(requestURI: path),
      let service = self.services[Substring(callPath.service)] else {
      return self.methodNotImplemented(path, contentType: contentType)
    }

    // Create a call handler context, i.e. a bunch of 'stuff' we need to create the handler with,
    // some of which is exposed to service providers.
    let context = CallHandlerContext(
      errorDelegate: errorDelegate,
      logger: logger,
      encoding: self.encoding,
      eventLoop: eventLoop,
      path: path,
      remoteAddress: remoteAddress,
      responseWriter: responseWriter,
      allocator: allocator
    )

    // We have a matching service, hopefully we have a provider for the method too.
    let method = Substring(callPath.method)

    if let handler = service.handle(method: method, context: context) {
      let nextState = HTTP2ToRawGRPCStateMachine.RequestOpenResponseIdleState(
        reader: reader,
        writer: writer,
        contentType: contentType,
        acceptEncoding: acceptableRequestEncoding,
        responseEncoding: responseEncoding,
        normalizeHeaders: self.normalizeHeaders,
        configurationState: .configuring(headers)
      )

      return .init(
        state: .requestOpenResponseIdle(nextState),
        action: .configure(handler)
      )
    } else {
      return self.methodNotImplemented(path, contentType: contentType)
    }
  }

  /// The 'content-type' is not supported; close with status code 415.
  private func unsupportedContentType() -> HTTP2ToRawGRPCStateMachine.StateAndReceiveHeadersAction {
    // From: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md
    //
    //   If 'content-type' does not begin with "application/grpc", gRPC servers SHOULD respond
    //   with HTTP status of 415 (Unsupported Media Type). This will prevent other HTTP/2
    //   clients from interpreting a gRPC error response, which uses status 200 (OK), as
    //   successful.
    let trailers = HPACKHeaders([(":status", "415")])
    return .init(
      state: .requestClosedResponseClosed,
      action: .rejectRPC(trailers)
    )
  }

  /// The RPC method is not implemented. Close with an appropriate status.
  private func methodNotImplemented(
    _ path: String,
    contentType: ContentType
  ) -> HTTP2ToRawGRPCStateMachine.StateAndReceiveHeadersAction {
    let trailers = HTTP2ToRawGRPCStateMachine.makeResponseTrailersOnly(
      for: GRPCStatus(code: .unimplemented, message: "'\(path)' is not implemented"),
      contentType: contentType,
      acceptableRequestEncoding: nil,
      userProvidedHeaders: nil,
      normalizeUserProvidedHeaders: self.normalizeHeaders
    )

    return .init(
      state: .requestClosedResponseClosed,
      action: .rejectRPC(trailers)
    )
  }

  /// The request encoding specified by the client is not supported. Close with an appropriate
  /// status.
  private func invalidRequestEncoding(
    status: GRPCStatus,
    acceptableRequestEncoding: String?,
    contentType: ContentType
  ) -> HTTP2ToRawGRPCStateMachine.StateAndReceiveHeadersAction {
    let trailers = HTTP2ToRawGRPCStateMachine.makeResponseTrailersOnly(
      for: status,
      contentType: contentType,
      acceptableRequestEncoding: acceptableRequestEncoding,
      userProvidedHeaders: nil,
      normalizeUserProvidedHeaders: self.normalizeHeaders
    )

    return .init(
      state: .requestClosedResponseClosed,
      action: .rejectRPC(trailers)
    )
  }

  /// Makes a 'GRPCStatus' and response trailers suitable for returning to the client when the
  /// request message encoding is not supported.
  ///
  /// - Parameters:
  ///   - encoding: The unsupported request message encoding sent by the client.
  ///   - acceptable: The list if acceptable request message encoding the client may use.
  /// - Returns: The status and trailers to return to the client.
  private func makeStatusAndTrailersForUnsupportedEncoding(
    _ encoding: String,
    advertisedEncoding: [String]
  ) -> (GRPCStatus, acceptEncoding: String?) {
    let status: GRPCStatus
    let acceptEncoding: String?

    if advertisedEncoding.isEmpty {
      // No compression is supported; there's nothing to tell the client about.
      status = GRPCStatus(code: .unimplemented, message: "compression is not supported")
      acceptEncoding = nil
    } else {
      // Return a list of supported encodings which we advertise. (The list we advertise may be a
      // subset of the encodings we support.)
      acceptEncoding = advertisedEncoding.joined(separator: ",")
      status = GRPCStatus(
        code: .unimplemented,
        message: "\(encoding) compression is not supported, supported algorithms are " +
          "listed in '\(GRPCHeaderName.acceptEncoding)'"
      )
    }

    return (status, acceptEncoding)
  }

  /// Extract and validate the 'content-type' sent by the client.
  /// - Parameter headers: The headers to extract the 'content-type' from
  private func extractContentType(from headers: HPACKHeaders) -> ContentType? {
    return headers.first(name: GRPCHeaderName.contentType).flatMap(ContentType.init)
  }

  /// The result of validating the request encoding header.
  private enum RequestEncodingValidation {
    /// The encoding was valid.
    case valid(messageReader: LengthPrefixedMessageReader, acceptEncoding: String?)
    /// The encoding was invalid, the RPC should be terminated with this status.
    case invalid(status: GRPCStatus, acceptEncoding: String?)
  }

  /// Extract and validate the request message encoding header.
  /// - Parameters:
  ///   - headers: The headers to extract the message encoding header from.
  /// - Returns: `RequestEncodingValidation`, either a message reader suitable for decoding requests
  ///   and an accept encoding response header if the request encoding was valid, or a pair of
  ///     `GRPCStatus` and trailers to close the RPC with.
  private func extractRequestEncoding(from headers: HPACKHeaders) -> RequestEncodingValidation {
    let encodings = headers[canonicalForm: GRPCHeaderName.encoding]

    // Fail if there's more than one encoding header.
    if encodings.count > 1 {
      let status = GRPCStatus(
        code: .invalidArgument,
        message: "'\(GRPCHeaderName.encoding)' must contain no more than one value but was '\(encodings.joined(separator: ", "))'"
      )
      return .invalid(status: status, acceptEncoding: nil)
    }

    let encodingHeader = encodings.first
    let result: RequestEncodingValidation

    let validator = MessageEncodingHeaderValidator(encoding: self.encoding)

    switch validator.validate(requestEncoding: encodingHeader) {
    case let .supported(algorithm, decompressionLimit, acceptEncoding):
      // Request message encoding is valid and supported.
      result = .valid(
        messageReader: LengthPrefixedMessageReader(
          compression: algorithm,
          decompressionLimit: decompressionLimit
        ),
        acceptEncoding: acceptEncoding.isEmpty ? nil : acceptEncoding.joined(separator: ",")
      )

    case .noCompression:
      // No message encoding header was present. This means no compression is being used.
      result = .valid(
        messageReader: LengthPrefixedMessageReader(),
        acceptEncoding: nil
      )

    case let .unsupported(encoding, acceptable):
      // Request encoding is not supported.
      let (status, acceptEncoding) = self.makeStatusAndTrailersForUnsupportedEncoding(
        encoding,
        advertisedEncoding: acceptable
      )
      result = .invalid(status: status, acceptEncoding: acceptEncoding)
    }

    return result
  }

  /// Extract a suitable message encoding for responses.
  /// - Parameters:
  ///   - headers: The headers to extract the acceptable response message encoding from.
  ///   - configuration: The encoding configuration for the server.
  /// - Returns: A message writer and the response encoding header to send back to the client.
  private func extractResponseEncoding(
    from headers: HPACKHeaders
  ) -> (LengthPrefixedMessageWriter, String?) {
    let writer: LengthPrefixedMessageWriter
    let responseEncoding: String?

    switch self.encoding {
    case let .enabled(configuration):
      // Extract the encodings acceptable to the client for response messages.
      let acceptableResponseEncoding = headers[canonicalForm: GRPCHeaderName.acceptEncoding]

      // Select the first algorithm that we support and have enabled. If we don't find one then we
      // won't compress response messages.
      let algorithm = acceptableResponseEncoding.lazy.compactMap { value in
        CompressionAlgorithm(rawValue: value)
      }.first {
        configuration.enabledAlgorithms.contains($0)
      }

      writer = LengthPrefixedMessageWriter(compression: algorithm)
      responseEncoding = algorithm?.name

    case .disabled:
      // The server doesn't have compression enabled.
      writer = LengthPrefixedMessageWriter(compression: .none)
      responseEncoding = nil
    }

    return (writer, responseEncoding)
  }
}

// MARK: - Receive Data

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseIdleState {
  mutating func receive(
    buffer: inout ByteBuffer,
    endStream: Bool
  ) -> HTTP2ToRawGRPCStateMachine.StateAndReceiveDataAction {
    // Append the bytes to the reader.
    self.reader.append(buffer: &buffer)

    let state: HTTP2ToRawGRPCStateMachine.State
    let tryReading: Bool

    switch (self.configurationState.isConfigured, endStream) {
    case (true, true):
      /// Configured and end stream: read from the buffer, end will be sent as a result of draining
      /// the reader in the next state.
      state = .requestClosedResponseIdle(.init(from: self))
      tryReading = true

    case (true, false):
      /// Configured but not end stream, just read from the buffer.
      state = .requestOpenResponseIdle(self)
      tryReading = true

    case (false, true):
      // Not configured yet, but end of stream. Request stream is now closed but there's no point
      // reading yet.
      state = .requestClosedResponseIdle(.init(from: self))
      tryReading = false

    case (false, false):
      // Not configured yet, not end stream. No point reading a message yet since we don't have
      // anywhere to deliver it.
      state = .requestOpenResponseIdle(self)
      tryReading = false
    }

    return .init(state: state, tryReading: tryReading)
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseOpenState {
  mutating func receive(
    buffer: inout ByteBuffer,
    endStream: Bool
  ) -> HTTP2ToRawGRPCStateMachine.StateAndReceiveDataAction {
    self.reader.append(buffer: &buffer)

    let state: HTTP2ToRawGRPCStateMachine.State

    if endStream {
      // End stream, so move to the closed state. Any end of request stream events events will
      // happen as a result of reading from the closed state.
      state = .requestClosedResponseOpen(.init(from: self))
    } else {
      state = .requestOpenResponseOpen(self)
    }

    return .init(state: state, tryReading: true)
  }
}

// MARK: - Send Headers

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseIdleState {
  func send(headers userProvidedHeaders: HPACKHeaders) -> HPACKHeaders {
    return HTTP2ToRawGRPCStateMachine.makeResponseHeaders(
      contentType: self.contentType,
      responseEncoding: self.responseEncoding,
      acceptableRequestEncoding: self.acceptEncoding,
      userProvidedHeaders: userProvidedHeaders,
      normalizeUserProvidedHeaders: self.normalizeHeaders
    )
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestClosedResponseIdleState {
  func send(headers userProvidedHeaders: HPACKHeaders) -> HPACKHeaders {
    return HTTP2ToRawGRPCStateMachine.makeResponseHeaders(
      contentType: self.contentType,
      responseEncoding: self.responseEncoding,
      acceptableRequestEncoding: self.acceptEncoding,
      userProvidedHeaders: userProvidedHeaders,
      normalizeUserProvidedHeaders: self.normalizeHeaders
    )
  }
}

// MARK: - Send Data

extension HTTP2ToRawGRPCStateMachine {
  static func writeGRPCFramedMessage(
    _ buffer: ByteBuffer,
    compress: Bool,
    allocator: ByteBufferAllocator,
    writer: LengthPrefixedMessageWriter
  ) -> Result<ByteBuffer, Error> {
    do {
      let prefixed = try writer.write(buffer: buffer, allocator: allocator, compressed: compress)
      return .success(prefixed)
    } catch {
      return .failure(error)
    }
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseOpenState {
  func send(
    buffer: ByteBuffer,
    allocator: ByteBufferAllocator,
    compress: Bool
  ) -> Result<ByteBuffer, Error> {
    return HTTP2ToRawGRPCStateMachine.writeGRPCFramedMessage(
      buffer,
      compress: compress,
      allocator: allocator,
      writer: self.writer
    )
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestClosedResponseOpenState {
  func send(
    buffer: ByteBuffer,
    allocator: ByteBufferAllocator,
    compress: Bool
  ) -> Result<ByteBuffer, Error> {
    return HTTP2ToRawGRPCStateMachine.writeGRPCFramedMessage(
      buffer,
      compress: compress,
      allocator: allocator,
      writer: self.writer
    )
  }
}

// MARK: - Send End

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseIdleState {
  func send(
    status: GRPCStatus,
    trailers userProvidedTrailers: HPACKHeaders
  ) -> HPACKHeaders {
    return HTTP2ToRawGRPCStateMachine.makeResponseTrailersOnly(
      for: status,
      contentType: self.contentType,
      acceptableRequestEncoding: self.acceptEncoding,
      userProvidedHeaders: userProvidedTrailers,
      normalizeUserProvidedHeaders: self.normalizeHeaders
    )
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestClosedResponseIdleState {
  func send(
    status: GRPCStatus,
    trailers userProvidedTrailers: HPACKHeaders
  ) -> HPACKHeaders {
    return HTTP2ToRawGRPCStateMachine.makeResponseTrailersOnly(
      for: status,
      contentType: self.contentType,
      acceptableRequestEncoding: self.acceptEncoding,
      userProvidedHeaders: userProvidedTrailers,
      normalizeUserProvidedHeaders: self.normalizeHeaders
    )
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestClosedResponseOpenState {
  func send(
    status: GRPCStatus,
    trailers userProvidedTrailers: HPACKHeaders
  ) -> HPACKHeaders {
    return HTTP2ToRawGRPCStateMachine.makeResponseTrailers(
      for: status,
      userProvidedHeaders: userProvidedTrailers,
      normalizeUserProvidedHeaders: true
    )
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseOpenState {
  func send(
    status: GRPCStatus,
    trailers userProvidedTrailers: HPACKHeaders
  ) -> HPACKHeaders {
    return HTTP2ToRawGRPCStateMachine.makeResponseTrailers(
      for: status,
      userProvidedHeaders: userProvidedTrailers,
      normalizeUserProvidedHeaders: true
    )
  }
}

// MARK: - Pipeline Configured

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseIdleState {
  mutating func pipelineConfigured() -> HTTP2ToRawGRPCStateMachine.PipelineConfiguredAction {
    let headers = self.configurationState.configured()
    let action: HTTP2ToRawGRPCStateMachine.PipelineConfiguredAction

    // If there are unprocessed bytes then we need to read messages as well.
    let hasUnprocessedBytes = self.reader.unprocessedBytes != 0

    if hasUnprocessedBytes {
      // If there are unprocessed bytes, we need to try to read after sending the metadata.
      action = .forwardHeadersAndRead(headers)
    } else {
      // No unprocessed bytes; the reader is empty. Just send the metadata.
      action = .forwardHeaders(headers)
    }

    return action
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestClosedResponseIdleState {
  mutating func pipelineConfigured() -> HTTP2ToRawGRPCStateMachine.PipelineConfiguredAction {
    let headers = self.configurationState.configured()
    // Since we're already closed, we need to forward the headers and start reading.
    return .forwardHeadersAndRead(headers)
  }
}

// MARK: - Read Next Request

extension HTTP2ToRawGRPCStateMachine {
  static func read(
    from reader: inout LengthPrefixedMessageReader,
    requestStreamClosed: Bool
  ) -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    do {
      // Try to read a message.
      guard let buffer = try reader.nextMessage() else {
        // We didn't read a message: if we're closed then there's no chance of receiving more bytes,
        // just forward the end of stream. If we're not closed then we could receive more bytes so
        // there's no need to take any action at this point.
        return requestStreamClosed ? .forwardEnd : .none
      }

      guard reader.unprocessedBytes == 0 else {
        // There are still unprocessed bytes, continue reading.
        return .forwardMessageThenReadNextMessage(buffer)
      }

      // If we're closed and there's nothing left to read, then we're done, forward the message and
      // end of stream. If we're closed we could still receive more bytes (or end stream) so just
      // forward the message.
      return requestStreamClosed ? .forwardMessageAndEnd(buffer) : .forwardMessage(buffer)
    } catch {
      return .errorCaught(error)
    }
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseIdleState {
  mutating func readNextRequest() -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    return HTTP2ToRawGRPCStateMachine.read(from: &self.reader, requestStreamClosed: false)
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseOpenState {
  mutating func readNextRequest() -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    return HTTP2ToRawGRPCStateMachine.read(from: &self.reader, requestStreamClosed: false)
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestClosedResponseIdleState {
  mutating func readNextRequest() -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    return HTTP2ToRawGRPCStateMachine.read(from: &self.reader, requestStreamClosed: true)
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestClosedResponseOpenState {
  mutating func readNextRequest() -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    return HTTP2ToRawGRPCStateMachine.read(from: &self.reader, requestStreamClosed: true)
  }
}

// MARK: - Top Level State Changes

extension HTTP2ToRawGRPCStateMachine {
  /// Receive request headers.
  mutating func receive(
    headers: HPACKHeaders,
    eventLoop: EventLoop,
    errorDelegate: ServerErrorDelegate?,
    remoteAddress: SocketAddress?,
    logger: Logger,
    allocator: ByteBufferAllocator,
    responseWriter: GRPCServerResponseWriter
  ) -> ReceiveHeadersAction {
    return self.withStateAvoidingCoWs { state in
      state.receive(
        headers: headers,
        eventLoop: eventLoop,
        errorDelegate: errorDelegate,
        remoteAddress: remoteAddress,
        logger: logger,
        allocator: allocator,
        responseWriter: responseWriter
      )
    }
  }

  /// Receive request buffer.
  /// - Parameters:
  ///   - buffer: The received buffer.
  ///   - endStream: Whether end stream was set.
  /// - Returns: Returns whether the caller should try to read a message from the buffer.
  mutating func receive(buffer: inout ByteBuffer, endStream: Bool) -> Bool {
    return self.withStateAvoidingCoWs { state in
      state.receive(buffer: &buffer, endStream: endStream)
    }
  }

  /// Send response headers.
  mutating func send(headers: HPACKHeaders) -> Result<HPACKHeaders, Error> {
    return self.withStateAvoidingCoWs { state in
      state.send(headers: headers)
    }
  }

  /// Send a response buffer.
  func send(
    buffer: ByteBuffer,
    allocator: ByteBufferAllocator,
    compress: Bool
  ) -> Result<ByteBuffer, Error> {
    return self.state.send(buffer: buffer, allocator: allocator, compress: compress)
  }

  /// Send status and trailers.
  mutating func send(
    status: GRPCStatus,
    trailers: HPACKHeaders
  ) -> Result<HPACKHeaders, Error> {
    return self.withStateAvoidingCoWs { state in
      state.send(status: status, trailers: trailers)
    }
  }

  /// The pipeline has been configured with a service provider.
  mutating func pipelineConfigured() -> PipelineConfiguredAction {
    return self.withStateAvoidingCoWs { state in
      state.pipelineConfigured()
    }
  }

  /// Try to read a request message.
  mutating func readNextRequest() -> ReadNextMessageAction {
    return self.withStateAvoidingCoWs { state in
      state.readNextRequest()
    }
  }
}

extension HTTP2ToRawGRPCStateMachine.State {
  mutating func pipelineConfigured() -> HTTP2ToRawGRPCStateMachine.PipelineConfiguredAction {
    switch self {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: pipeline configured before receiving request headers")

    case var .requestOpenResponseIdle(state):
      let action = state.pipelineConfigured()
      self = .requestOpenResponseIdle(state)
      return action

    case var .requestClosedResponseIdle(state):
      let action = state.pipelineConfigured()
      self = .requestClosedResponseIdle(state)
      return action

    case .requestOpenResponseOpen,
         .requestClosedResponseOpen,
         .requestClosedResponseClosed:
      preconditionFailure("Invalid state: response stream opened before pipeline was configured")

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  mutating func receive(
    headers: HPACKHeaders,
    eventLoop: EventLoop,
    errorDelegate: ServerErrorDelegate?,
    remoteAddress: SocketAddress?,
    logger: Logger,
    allocator: ByteBufferAllocator,
    responseWriter: GRPCServerResponseWriter
  ) -> HTTP2ToRawGRPCStateMachine.ReceiveHeadersAction {
    switch self {
    // This is the only state in which we can receive headers. Everything else is invalid.
    case let .requestIdleResponseIdle(state):
      let stateAndAction = state.receive(
        headers: headers,
        eventLoop: eventLoop,
        errorDelegate: errorDelegate,
        remoteAddress: remoteAddress,
        logger: logger,
        allocator: allocator,
        responseWriter: responseWriter
      )
      self = stateAndAction.state
      return stateAndAction.action

    // We can't receive headers in any of these states.
    case .requestOpenResponseIdle,
         .requestOpenResponseOpen,
         .requestClosedResponseIdle,
         .requestClosedResponseOpen,
         .requestClosedResponseClosed:
      preconditionFailure("Invalid state")

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  /// Receive a buffer from the client.
  mutating func receive(buffer: inout ByteBuffer, endStream: Bool) -> Bool {
    switch self {
    case .requestIdleResponseIdle:
      /// This isn't allowed: we must receive the request headers first.
      preconditionFailure("Invalid state")

    case var .requestOpenResponseIdle(state):
      let stateAndAction = state.receive(buffer: &buffer, endStream: endStream)
      self = stateAndAction.state
      return stateAndAction.tryReading

    case var .requestOpenResponseOpen(state):
      let stateAndAction = state.receive(buffer: &buffer, endStream: endStream)
      self = stateAndAction.state
      return stateAndAction.tryReading

    case .requestClosedResponseIdle,
         .requestClosedResponseOpen:
      preconditionFailure("Invalid state: the request stream is already closed")

    case .requestClosedResponseClosed:
      // This is okay: we could have closed before receiving end.
      return false

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  mutating func readNextRequest() -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    switch self {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state")

    case var .requestOpenResponseIdle(state):
      let action = state.readNextRequest()
      self = .requestOpenResponseIdle(state)
      return action

    case var .requestOpenResponseOpen(state):
      let action = state.readNextRequest()
      self = .requestOpenResponseOpen(state)
      return action

    case var .requestClosedResponseIdle(state):
      let action = state.readNextRequest()
      self = .requestClosedResponseIdle(state)
      return action

    case var .requestClosedResponseOpen(state):
      let action = state.readNextRequest()
      self = .requestClosedResponseOpen(state)
      return action

    case .requestClosedResponseClosed:
      return .none

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  mutating func send(headers: HPACKHeaders) -> Result<HPACKHeaders, Error> {
    switch self {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: the request stream isn't open")

    case let .requestOpenResponseIdle(state):
      let headers = state.send(headers: headers)
      self = .requestOpenResponseOpen(.init(from: state))
      return .success(headers)

    case let .requestClosedResponseIdle(state):
      let headers = state.send(headers: headers)
      self = .requestClosedResponseOpen(.init(from: state))
      return .success(headers)

    case .requestOpenResponseOpen,
         .requestClosedResponseOpen,
         .requestClosedResponseClosed:
      return .failure(GRPCError.AlreadyComplete())

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  func send(
    buffer: ByteBuffer,
    allocator: ByteBufferAllocator,
    compress: Bool
  ) -> Result<ByteBuffer, Error> {
    switch self {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: the request stream is still closed")

    case .requestOpenResponseIdle,
         .requestClosedResponseIdle:
      let error = GRPCError.InvalidState("Response headers must be sent before response message")
      return .failure(error)

    case let .requestOpenResponseOpen(state):
      return state.send(
        buffer: buffer,
        allocator: allocator,
        compress: compress
      )

    case let .requestClosedResponseOpen(state):
      return state.send(
        buffer: buffer,
        allocator: allocator,
        compress: compress
      )

    case .requestClosedResponseClosed:
      return .failure(GRPCError.AlreadyComplete())

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  mutating func send(
    status: GRPCStatus,
    trailers: HPACKHeaders
  ) -> Result<HPACKHeaders, Error> {
    switch self {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: the request stream is still closed")

    case let .requestOpenResponseIdle(state):
      self = .requestClosedResponseClosed
      return .success(state.send(status: status, trailers: trailers))

    case let .requestClosedResponseIdle(state):
      self = .requestClosedResponseClosed
      return .success(state.send(status: status, trailers: trailers))

    case let .requestOpenResponseOpen(state):
      self = .requestClosedResponseClosed
      return .success(state.send(status: status, trailers: trailers))

    case let .requestClosedResponseOpen(state):
      self = .requestClosedResponseClosed
      return .success(state.send(status: status, trailers: trailers))

    case .requestClosedResponseClosed:
      return .failure(GRPCError.AlreadyComplete())

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }
}

// MARK: - Helpers

extension HTTP2ToRawGRPCStateMachine {
  static func makeResponseHeaders(
    contentType: ContentType,
    responseEncoding: String?,
    acceptableRequestEncoding: String?,
    userProvidedHeaders: HPACKHeaders,
    normalizeUserProvidedHeaders: Bool
  ) -> HPACKHeaders {
    // 4 because ':status' and 'content-type' are required. We may send back 'grpc-encoding' and
    // 'grpc-accept-encoding' as well.
    let capacity = 4 + userProvidedHeaders.count

    var headers = HPACKHeaders()
    headers.reserveCapacity(capacity)

    headers.add(name: ":status", value: "200")
    headers.add(name: GRPCHeaderName.contentType, value: contentType.canonicalValue)

    if let responseEncoding = responseEncoding {
      headers.add(name: GRPCHeaderName.encoding, value: responseEncoding)
    }

    if let acceptEncoding = acceptableRequestEncoding {
      headers.add(name: GRPCHeaderName.acceptEncoding, value: acceptEncoding)
    }

    // Add user provided headers, normalizing if required.
    headers.add(contentsOf: userProvidedHeaders, normalize: normalizeUserProvidedHeaders)

    return headers
  }

  static func makeResponseTrailersOnly(
    for status: GRPCStatus,
    contentType: ContentType,
    acceptableRequestEncoding: String?,
    userProvidedHeaders: HPACKHeaders?,
    normalizeUserProvidedHeaders: Bool
  ) -> HPACKHeaders {
    // 5 because ':status', 'content-type', 'grpc-status' are required. We may also send back
    // 'grpc-message' and 'grpc-accept-encoding'.
    let capacity = 5 + (userProvidedHeaders.map { $0.count } ?? 0)

    var headers = HPACKHeaders()
    headers.reserveCapacity(capacity)

    // Add the required trailers.
    headers.add(name: ":status", value: "200")
    headers.add(name: GRPCHeaderName.contentType, value: contentType.canonicalValue)
    headers.add(name: GRPCHeaderName.statusCode, value: String(describing: status.code.rawValue))

    if let message = status.message.flatMap(GRPCStatusMessageMarshaller.marshall) {
      headers.add(name: GRPCHeaderName.statusMessage, value: message)
    }

    // We may include this if the requested encoding was not valid.
    if let acceptEncoding = acceptableRequestEncoding {
      headers.add(name: GRPCHeaderName.acceptEncoding, value: acceptEncoding)
    }

    if let userProvided = userProvidedHeaders {
      headers.add(contentsOf: userProvided, normalize: normalizeUserProvidedHeaders)
    }

    return headers
  }

  static func makeResponseTrailers(
    for status: GRPCStatus,
    userProvidedHeaders: HPACKHeaders,
    normalizeUserProvidedHeaders: Bool
  ) -> HPACKHeaders {
    // 2 because 'grpc-status' is required, we may also send back 'grpc-message'.
    let capacity = 2 + userProvidedHeaders.count

    var trailers = HPACKHeaders()
    trailers.reserveCapacity(capacity)

    // status code.
    trailers.add(name: GRPCHeaderName.statusCode, value: String(describing: status.code.rawValue))

    // status message, if present.
    if let message = status.message.flatMap(GRPCStatusMessageMarshaller.marshall) {
      trailers.add(name: GRPCHeaderName.statusMessage, value: message)
    }

    // user provided trailers.
    trailers.add(contentsOf: userProvidedHeaders, normalize: normalizeUserProvidedHeaders)

    return trailers
  }
}

private extension HPACKHeaders {
  mutating func add(contentsOf other: HPACKHeaders, normalize: Bool) {
    if normalize {
      self.add(contentsOf: other.lazy.map { name, value, indexable in
        (name: name.lowercased(), value: value, indexable: indexable)
      })
    } else {
      self.add(contentsOf: other)
    }
  }
}
