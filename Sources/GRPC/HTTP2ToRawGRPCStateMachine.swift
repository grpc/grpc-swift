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
import NIOCore
import NIOHPACK
import NIOHTTP2

struct HTTP2ToRawGRPCStateMachine {
  /// The current state.
  private var state: State = .requestIdleResponseIdle
}

extension HTTP2ToRawGRPCStateMachine {
  enum State {
    // Both peers are idle. Nothing has happened to the stream.
    case requestIdleResponseIdle

    // Received valid headers. Nothing has been sent in response.
    case requestOpenResponseIdle(RequestOpenResponseIdleState)

    // Received valid headers and request(s). Response headers have been sent.
    case requestOpenResponseOpen(RequestOpenResponseOpenState)

    // Received valid headers and request(s) but not end of the request stream. Response stream has
    // been closed.
    case requestOpenResponseClosed

    // The request stream is closed. Nothing has been sent in response.
    case requestClosedResponseIdle(RequestClosedResponseIdleState)

    // The request stream is closed. Response headers have been sent.
    case requestClosedResponseOpen(RequestClosedResponseOpenState)

    // Both streams are closed. This state is terminal.
    case requestClosedResponseClosed
  }

  struct RequestOpenResponseIdleState {
    /// A length prefixed message reader for request messages.
    var reader: LengthPrefixedMessageReader

    /// A length prefixed message writer for response messages.
    var writer: CoalescingLengthPrefixedMessageWriter

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
    var writer: CoalescingLengthPrefixedMessageWriter

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
    var writer: CoalescingLengthPrefixedMessageWriter

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
    var writer: CoalescingLengthPrefixedMessageWriter

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
    /// The action to take
    var action: ReceiveDataAction
  }

  enum ReceiveDataAction: Hashable {
    /// Try to read the next message from the state machine.
    case tryReading
    /// Invoke 'finish' on the RPC handler.
    case finishHandler
    /// Do nothing.
    case nothing
  }

  enum SendEndAction {
    /// Send trailers to the client.
    case sendTrailers(HPACKHeaders)
    /// Send trailers to the client and invoke 'finish' on the RPC handler.
    case sendTrailersAndFinish(HPACKHeaders)
    /// Fail any promise associated with this send.
    case failure(Error)
  }
}

// MARK: Receive Headers

// This is the only state in which we can receive headers.
extension HTTP2ToRawGRPCStateMachine.State {
  private func _receive(
    headers: HPACKHeaders,
    eventLoop: EventLoop,
    errorDelegate: ServerErrorDelegate?,
    remoteAddress: SocketAddress?,
    logger: Logger,
    allocator: ByteBufferAllocator,
    responseWriter: GRPCServerResponseWriter,
    closeFuture: EventLoopFuture<Void>,
    services: [Substring: CallHandlerProvider],
    encoding: ServerMessageEncoding,
    normalizeHeaders: Bool
  ) -> HTTP2ToRawGRPCStateMachine.StateAndReceiveHeadersAction {
    // Extract and validate the content type. If it's nil we need to close.
    guard let contentType = self.extractContentType(from: headers) else {
      return self.unsupportedContentType()
    }

    // Now extract the request message encoding and setup an appropriate message reader.
    // We may send back a list of acceptable request message encodings as well.
    let reader: LengthPrefixedMessageReader
    let acceptableRequestEncoding: String?

    switch self.extractRequestEncoding(from: headers, encoding: encoding) {
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
    let (writer, responseEncoding) = self.extractResponseEncoding(
      from: headers,
      encoding: encoding,
      allocator: allocator
    )

    // Parse the path, and create a call handler.
    guard let path = headers.first(name: ":path") else {
      return self.methodNotImplemented("", contentType: contentType)
    }

    guard let callPath = CallPath(requestURI: path),
      let service = services[Substring(callPath.service)]
    else {
      return self.methodNotImplemented(path, contentType: contentType)
    }

    // Create a call handler context, i.e. a bunch of 'stuff' we need to create the handler with,
    // some of which is exposed to service providers.
    let context = CallHandlerContext(
      errorDelegate: errorDelegate,
      logger: logger,
      encoding: encoding,
      eventLoop: eventLoop,
      path: path,
      remoteAddress: remoteAddress,
      responseWriter: responseWriter,
      allocator: allocator,
      closeFuture: closeFuture
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
        normalizeHeaders: normalizeHeaders,
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
      normalizeUserProvidedHeaders: false
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
      normalizeUserProvidedHeaders: false
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
        message: "\(encoding) compression is not supported, supported algorithms are "
          + "listed in '\(GRPCHeaderName.acceptEncoding)'"
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
  private func extractRequestEncoding(
    from headers: HPACKHeaders,
    encoding: ServerMessageEncoding
  ) -> RequestEncodingValidation {
    let encodingValues = headers.values(forHeader: GRPCHeaderName.encoding, canonicalForm: true)
    var encodingIterator = encodingValues.makeIterator()
    let encodingHeader = encodingIterator.next()

    // Fail if there's more than one encoding header.
    if let first = encodingHeader, let second = encodingIterator.next() {
      var encodings: [Substring] = []
      encodings.reserveCapacity(8)
      encodings.append(first)
      encodings.append(second)
      while let next = encodingIterator.next() {
        encodings.append(next)
      }
      let status = GRPCStatus(
        code: .invalidArgument,
        message:
          "'\(GRPCHeaderName.encoding)' must contain no more than one value but was '\(encodings.joined(separator: ", "))'"
      )
      return .invalid(status: status, acceptEncoding: nil)
    }

    let result: RequestEncodingValidation
    let validator = MessageEncodingHeaderValidator(encoding: encoding)

    switch validator.validate(requestEncoding: encodingHeader.map { String($0) }) {
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
    from headers: HPACKHeaders,
    encoding: ServerMessageEncoding,
    allocator: ByteBufferAllocator
  ) -> (CoalescingLengthPrefixedMessageWriter, String?) {
    let writer: CoalescingLengthPrefixedMessageWriter
    let responseEncoding: String?

    switch encoding {
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

      writer = .init(compression: algorithm, allocator: allocator)
      responseEncoding = algorithm?.name

    case .disabled:
      // The server doesn't have compression enabled.
      writer = .init(compression: .none, allocator: allocator)
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
    let action: HTTP2ToRawGRPCStateMachine.ReceiveDataAction

    switch (self.configurationState.isConfigured, endStream) {
    case (true, true):
      /// Configured and end stream: read from the buffer, end will be sent as a result of draining
      /// the reader in the next state.
      state = .requestClosedResponseIdle(.init(from: self))
      action = .tryReading

    case (true, false):
      /// Configured but not end stream, just read from the buffer.
      state = .requestOpenResponseIdle(self)
      action = .tryReading

    case (false, true):
      // Not configured yet, but end of stream. Request stream is now closed but there's no point
      // reading yet.
      state = .requestClosedResponseIdle(.init(from: self))
      action = .nothing

    case (false, false):
      // Not configured yet, not end stream. No point reading a message yet since we don't have
      // anywhere to deliver it.
      state = .requestOpenResponseIdle(self)
      action = .nothing
    }

    return .init(state: state, action: action)
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

    return .init(state: state, action: .tryReading)
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

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseOpenState {
  mutating func send(
    buffer: ByteBuffer,
    compress: Bool,
    promise: EventLoopPromise<Void>?
  ) {
    self.writer.append(buffer: buffer, compress: compress, promise: promise)
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestClosedResponseOpenState {
  mutating func send(
    buffer: ByteBuffer,
    compress: Bool,
    promise: EventLoopPromise<Void>?
  ) {
    self.writer.append(buffer: buffer, compress: compress, promise: promise)
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
    requestStreamClosed: Bool,
    maxLength: Int
  ) -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    do {
      if let buffer = try reader.nextMessage(maxLength: maxLength) {
        if reader.unprocessedBytes > 0 || requestStreamClosed {
          // Either there are unprocessed bytes or the request stream is now closed: deliver the
          // message and then try to read. The subsequent read may be another message or it may
          // be end stream.
          return .forwardMessageThenReadNextMessage(buffer)
        } else {
          // Nothing left to process and the stream isn't closed yet, just forward the message.
          return .forwardMessage(buffer)
        }
      } else if requestStreamClosed {
        return .forwardEnd
      } else {
        return .none
      }
    } catch {
      return .errorCaught(error)
    }
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseIdleState {
  mutating func readNextRequest(
    maxLength: Int
  ) -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    return HTTP2ToRawGRPCStateMachine.read(
      from: &self.reader,
      requestStreamClosed: false,
      maxLength: maxLength
    )
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestOpenResponseOpenState {
  mutating func readNextRequest(
    maxLength: Int
  ) -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    return HTTP2ToRawGRPCStateMachine.read(
      from: &self.reader,
      requestStreamClosed: false,
      maxLength: maxLength
    )
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestClosedResponseIdleState {
  mutating func readNextRequest(
    maxLength: Int
  ) -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    return HTTP2ToRawGRPCStateMachine.read(
      from: &self.reader,
      requestStreamClosed: true,
      maxLength: maxLength
    )
  }
}

extension HTTP2ToRawGRPCStateMachine.RequestClosedResponseOpenState {
  mutating func readNextRequest(
    maxLength: Int
  ) -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    return HTTP2ToRawGRPCStateMachine.read(
      from: &self.reader,
      requestStreamClosed: true,
      maxLength: maxLength
    )
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
    responseWriter: GRPCServerResponseWriter,
    closeFuture: EventLoopFuture<Void>,
    services: [Substring: CallHandlerProvider],
    encoding: ServerMessageEncoding,
    normalizeHeaders: Bool
  ) -> ReceiveHeadersAction {
    return self.state.receive(
      headers: headers,
      eventLoop: eventLoop,
      errorDelegate: errorDelegate,
      remoteAddress: remoteAddress,
      logger: logger,
      allocator: allocator,
      responseWriter: responseWriter,
      closeFuture: closeFuture,
      services: services,
      encoding: encoding,
      normalizeHeaders: normalizeHeaders
    )
  }

  /// Receive request buffer.
  /// - Parameters:
  ///   - buffer: The received buffer.
  ///   - endStream: Whether end stream was set.
  /// - Returns: Returns whether the caller should try to read a message from the buffer.
  mutating func receive(buffer: inout ByteBuffer, endStream: Bool) -> ReceiveDataAction {
    self.state.receive(buffer: &buffer, endStream: endStream)
  }

  /// Send response headers.
  mutating func send(headers: HPACKHeaders) -> Result<HPACKHeaders, Error> {
    self.state.send(headers: headers)
  }

  /// Send a response buffer.
  mutating func send(
    buffer: ByteBuffer,
    compress: Bool,
    promise: EventLoopPromise<Void>?
  ) -> Result<Void, Error> {
    self.state.send(buffer: buffer, compress: compress, promise: promise)
  }

  mutating func nextResponse() -> (Result<ByteBuffer, Error>, EventLoopPromise<Void>?)? {
    self.state.nextResponse()
  }

  /// Send status and trailers.
  mutating func send(
    status: GRPCStatus,
    trailers: HPACKHeaders
  ) -> HTTP2ToRawGRPCStateMachine.SendEndAction {
    self.state.send(status: status, trailers: trailers)
  }

  /// The pipeline has been configured with a service provider.
  mutating func pipelineConfigured() -> PipelineConfiguredAction {
    self.state.pipelineConfigured()
  }

  /// Try to read a request message.
  mutating func readNextRequest(maxLength: Int) -> ReadNextMessageAction {
    self.state.readNextRequest(maxLength: maxLength)
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
      .requestOpenResponseClosed,
      .requestClosedResponseOpen,
      .requestClosedResponseClosed:
      preconditionFailure("Invalid state: response stream opened before pipeline was configured")
    }
  }

  mutating func receive(
    headers: HPACKHeaders,
    eventLoop: EventLoop,
    errorDelegate: ServerErrorDelegate?,
    remoteAddress: SocketAddress?,
    logger: Logger,
    allocator: ByteBufferAllocator,
    responseWriter: GRPCServerResponseWriter,
    closeFuture: EventLoopFuture<Void>,
    services: [Substring: CallHandlerProvider],
    encoding: ServerMessageEncoding,
    normalizeHeaders: Bool
  ) -> HTTP2ToRawGRPCStateMachine.ReceiveHeadersAction {
    switch self {
    // These are the only states in which we can receive headers. Everything else is invalid.
    case .requestIdleResponseIdle,
      .requestClosedResponseClosed:
      let stateAndAction = self._receive(
        headers: headers,
        eventLoop: eventLoop,
        errorDelegate: errorDelegate,
        remoteAddress: remoteAddress,
        logger: logger,
        allocator: allocator,
        responseWriter: responseWriter,
        closeFuture: closeFuture,
        services: services,
        encoding: encoding,
        normalizeHeaders: normalizeHeaders
      )
      self = stateAndAction.state
      return stateAndAction.action

    // We can't receive headers in any of these states.
    case .requestOpenResponseIdle,
      .requestOpenResponseOpen,
      .requestOpenResponseClosed,
      .requestClosedResponseIdle,
      .requestClosedResponseOpen:
      preconditionFailure("Invalid state: \(self)")
    }
  }

  /// Receive a buffer from the client.
  mutating func receive(
    buffer: inout ByteBuffer,
    endStream: Bool
  ) -> HTTP2ToRawGRPCStateMachine.ReceiveDataAction {
    switch self {
    case .requestIdleResponseIdle:
      /// This isn't allowed: we must receive the request headers first.
      preconditionFailure("Invalid state")

    case var .requestOpenResponseIdle(state):
      let stateAndAction = state.receive(buffer: &buffer, endStream: endStream)
      self = stateAndAction.state
      return stateAndAction.action

    case var .requestOpenResponseOpen(state):
      let stateAndAction = state.receive(buffer: &buffer, endStream: endStream)
      self = stateAndAction.state
      return stateAndAction.action

    case .requestClosedResponseIdle,
      .requestClosedResponseOpen:
      preconditionFailure("Invalid state: the request stream is already closed")

    case .requestOpenResponseClosed:
      if endStream {
        // Server has finish responding and this is the end of the request stream; we're done for
        // this RPC now, finish the handler.
        self = .requestClosedResponseClosed
        return .finishHandler
      } else {
        // Server has finished responding but this isn't the end of the request stream; ignore the
        // input, we need to wait for end stream before tearing down the handler.
        return .nothing
      }

    case .requestClosedResponseClosed:
      return .nothing
    }
  }

  mutating func readNextRequest(
    maxLength: Int
  ) -> HTTP2ToRawGRPCStateMachine.ReadNextMessageAction {
    switch self {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state")

    case var .requestOpenResponseIdle(state):
      let action = state.readNextRequest(maxLength: maxLength)
      self = .requestOpenResponseIdle(state)
      return action

    case var .requestOpenResponseOpen(state):
      let action = state.readNextRequest(maxLength: maxLength)
      self = .requestOpenResponseOpen(state)
      return action

    case var .requestClosedResponseIdle(state):
      let action = state.readNextRequest(maxLength: maxLength)
      self = .requestClosedResponseIdle(state)
      return action

    case var .requestClosedResponseOpen(state):
      let action = state.readNextRequest(maxLength: maxLength)
      self = .requestClosedResponseOpen(state)
      return action

    case .requestOpenResponseClosed,
      .requestClosedResponseClosed:
      return .none
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
      .requestOpenResponseClosed,
      .requestClosedResponseOpen,
      .requestClosedResponseClosed:
      return .failure(GRPCError.AlreadyComplete())
    }
  }

  mutating func send(
    buffer: ByteBuffer,
    compress: Bool,
    promise: EventLoopPromise<Void>?
  ) -> Result<Void, Error> {
    switch self {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: the request stream is still closed")

    case .requestOpenResponseIdle,
      .requestClosedResponseIdle:
      let error = GRPCError.InvalidState("Response headers must be sent before response message")
      return .failure(error)

    case var .requestOpenResponseOpen(state):
      self = .requestClosedResponseClosed
      state.send(buffer: buffer, compress: compress, promise: promise)
      self = .requestOpenResponseOpen(state)
      return .success(())

    case var .requestClosedResponseOpen(state):
      self = .requestClosedResponseClosed
      state.send(buffer: buffer, compress: compress, promise: promise)
      self = .requestClosedResponseOpen(state)
      return .success(())

    case .requestOpenResponseClosed,
      .requestClosedResponseClosed:
      return .failure(GRPCError.AlreadyComplete())
    }
  }

  mutating func nextResponse() -> (Result<ByteBuffer, Error>, EventLoopPromise<Void>?)? {
    switch self {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: the request stream is still closed")

    case .requestOpenResponseIdle,
      .requestClosedResponseIdle:
      return nil

    case var .requestOpenResponseOpen(state):
      self = .requestClosedResponseClosed
      let result = state.writer.next()
      self = .requestOpenResponseOpen(state)
      return result

    case var .requestClosedResponseOpen(state):
      self = .requestClosedResponseClosed
      let result = state.writer.next()
      self = .requestClosedResponseOpen(state)
      return result

    case .requestOpenResponseClosed,
      .requestClosedResponseClosed:
      return nil
    }
  }

  mutating func send(
    status: GRPCStatus,
    trailers: HPACKHeaders
  ) -> HTTP2ToRawGRPCStateMachine.SendEndAction {
    switch self {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: the request stream is still closed")

    case let .requestOpenResponseIdle(state):
      self = .requestOpenResponseClosed
      return .sendTrailers(state.send(status: status, trailers: trailers))

    case let .requestClosedResponseIdle(state):
      self = .requestClosedResponseClosed
      return .sendTrailersAndFinish(state.send(status: status, trailers: trailers))

    case let .requestOpenResponseOpen(state):
      self = .requestOpenResponseClosed
      return .sendTrailers(state.send(status: status, trailers: trailers))

    case let .requestClosedResponseOpen(state):
      self = .requestClosedResponseClosed
      return .sendTrailersAndFinish(state.send(status: status, trailers: trailers))

    case .requestOpenResponseClosed,
      .requestClosedResponseClosed:
      return .failure(GRPCError.AlreadyComplete())
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
    // Most RPCs should end with status code 'ok' (hopefully!), and if the user didn't provide any
    // additional trailers, then we can use a pre-canned set of headers to avoid an extra
    // allocation.
    if status == .ok, userProvidedHeaders.isEmpty {
      return Self.gRPCStatusOkTrailers
    }

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

  private static let gRPCStatusOkTrailers: HPACKHeaders = [
    GRPCHeaderName.statusCode: String(describing: GRPCStatus.Code.ok.rawValue)
  ]
}

extension HPACKHeaders {
  fileprivate mutating func add(contentsOf other: HPACKHeaders, normalize: Bool) {
    if normalize {
      self.add(
        contentsOf: other.lazy.map { name, value, indexable in
          (name: name.lowercased(), value: value, indexable: indexable)
        }
      )
    } else {
      self.add(contentsOf: other)
    }
  }
}
