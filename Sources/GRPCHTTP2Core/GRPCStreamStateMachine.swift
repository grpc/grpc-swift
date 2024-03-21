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

import GRPCCore
import NIOCore
import NIOHPACK
import NIOHTTP1

enum Scheme: String {
  case http
  case https
}

enum GRPCStreamStateMachineConfiguration {
  case client(ClientConfiguration)
  case server(ServerConfiguration)

  struct ClientConfiguration {
    var methodDescriptor: MethodDescriptor
    var scheme: Scheme
    var outboundEncoding: CompressionAlgorithm
    var acceptedEncodings: [CompressionAlgorithm]
  }

  struct ServerConfiguration {
    var scheme: Scheme
    var acceptedEncodings: [CompressionAlgorithm]
  }
}

private enum GRPCStreamStateMachineState {
  case clientIdleServerIdle(ClientIdleServerIdleState)
  case clientOpenServerIdle(ClientOpenServerIdleState)
  case clientOpenServerOpen(ClientOpenServerOpenState)
  case clientOpenServerClosed(ClientOpenServerClosedState)
  case clientClosedServerIdle(ClientClosedServerIdleState)
  case clientClosedServerOpen(ClientClosedServerOpenState)
  case clientClosedServerClosed(ClientClosedServerClosedState)

  struct ClientIdleServerIdleState {
    let maximumPayloadSize: Int
  }

  struct ClientOpenServerIdleState {
    let maximumPayloadSize: Int
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    var outboundCompression: CompressionAlgorithm?

    // The deframer must be optional because the client will not have one configured
    // until the server opens and sends a grpc-encoding header.
    // It will be present for the server though, because even though it's idle,
    // it can still receive compressed messages from the client.
    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>?
    var decompressor: Zlib.Decompressor?

    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    init(
      previousState: ClientIdleServerIdleState,
      compressor: Zlib.Compressor?,
      framer: GRPCMessageFramer,
      decompressor: Zlib.Decompressor?,
      deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>?
    ) {
      self.maximumPayloadSize = previousState.maximumPayloadSize
      self.compressor = compressor
      self.framer = framer
      self.decompressor = decompressor
      self.deframer = deframer
      self.inboundMessageBuffer = .init()
    }
  }

  struct ClientOpenServerOpenState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?

    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>
    var decompressor: Zlib.Decompressor?

    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    init(
      previousState: ClientOpenServerIdleState,
      deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>,
      decompressor: Zlib.Decompressor?
    ) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor

      self.deframer = deframer
      self.decompressor = decompressor

      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }
  }

  struct ClientOpenServerClosedState {
    var framer: GRPCMessageFramer?
    var compressor: Zlib.Compressor?

    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>?
    var decompressor: Zlib.Decompressor?

    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    // This transition should only happen on the server-side when, upon receiving
    // initial client metadata, some of the headers are invalid and we must reject
    // the RPC.
    // We will mark the client as open (because it sent initial metadata albeit
    // invalid) but we'll close the server, meaning all future messages sent from
    // the client will be ignored. Because of this, we won't need to frame or
    // deframe any messages, as we won't be reading or writing any messages.
    init(previousState: ClientIdleServerIdleState) {
      self.framer = nil
      self.compressor = nil
      self.deframer = nil
      self.decompressor = nil
      self.inboundMessageBuffer = .init()
    }

    init(previousState: ClientOpenServerOpenState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    init(previousState: ClientOpenServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
      // The server went directly from idle to closed - this means it sent a
      // trailers-only response:
      // - if we're the client, the previous state was a nil deframer, but that
      // is okay because we don't need a deframer as the server won't be sending
      // any messages;
      // - if we're the server, we'll keep whatever deframer we had.
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
    }
  }

  struct ClientClosedServerIdleState {
    let maximumPayloadSize: Int
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    var outboundCompression: CompressionAlgorithm?

    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>?
    var decompressor: Zlib.Decompressor?

    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    /// We are closing the client as soon as it opens (i.e., endStream was set when receiving the client's
    /// initial metadata). We don't need to know a decompression algorithm, since we won't receive
    /// any more messages from the client anyways, as it's closed.
    init(
      previousState: ClientIdleServerIdleState,
      compressionAlgorithm: CompressionAlgorithm
    ) {
      self.maximumPayloadSize = previousState.maximumPayloadSize

      if let zlibMethod = Zlib.Method(encoding: compressionAlgorithm) {
        self.compressor = Zlib.Compressor(method: zlibMethod)
      }
      self.framer = GRPCMessageFramer()
      self.outboundCompression = compressionAlgorithm
      // We don't need a deframer since we won't receive any messages from the
      // client: it's closed.
      self.deframer = nil
      self.inboundMessageBuffer = .init()
    }

    init(previousState: ClientOpenServerIdleState) {
      self.maximumPayloadSize = previousState.maximumPayloadSize
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }
  }

  struct ClientClosedServerOpenState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?

    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>?
    var decompressor: Zlib.Decompressor?

    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    init(previousState: ClientOpenServerOpenState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    /// This should be called from the server path, as the deframer will already be configured in this scenario.
    init(previousState: ClientClosedServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor

      // In the case of the server, we don't need to deframe/decompress any more
      // messages, since the client's closed.
      self.deframer = nil
      self.decompressor = nil

      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    /// This should only be called from the client path, as the deframer has not yet been set up.
    init(
      previousState: ClientClosedServerIdleState,
      decompressionAlgorithm: CompressionAlgorithm
    ) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor

      // In the case of the client, it will only be able to set up the deframer
      // after it receives the chosen encoding from the server.
      if let zlibMethod = Zlib.Method(encoding: decompressionAlgorithm) {
        self.decompressor = Zlib.Decompressor(method: zlibMethod)
      }
      let decoder = GRPCMessageDeframer(
        maximumPayloadSize: previousState.maximumPayloadSize,
        decompressor: self.decompressor
      )
      self.deframer = NIOSingleStepByteToMessageProcessor(decoder)

      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }
  }

  struct ClientClosedServerClosedState {
    // We still need the framer and compressor in case the server has closed
    // but its buffer is not yet empty and still needs to send messages out to
    // the client.
    var framer: GRPCMessageFramer?
    var compressor: Zlib.Compressor?

    // These are already deframed, so we don't need the deframer anymore.
    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    // This transition should only happen on the server-side when, upon receiving
    // initial client metadata, some of the headers are invalid and we must reject
    // the RPC.
    // We will mark the client as closed (because it set the EOS flag, even if
    // the initial metadata was invalid) and we'll close the server too.
    // Because of this, we won't need to frame any messages, as we
    // won't be writing any messages.
    init(previousState: ClientIdleServerIdleState) {
      self.framer = nil
      self.compressor = nil
      self.inboundMessageBuffer = .init()
    }

    init(previousState: ClientClosedServerOpenState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    init(previousState: ClientClosedServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    init(previousState: ClientOpenServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    init(previousState: ClientOpenServerClosedState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct GRPCStreamStateMachine {
  private var state: GRPCStreamStateMachineState
  private var configuration: GRPCStreamStateMachineConfiguration
  private var skipAssertions: Bool

  init(
    configuration: GRPCStreamStateMachineConfiguration,
    maximumPayloadSize: Int,
    skipAssertions: Bool = false
  ) {
    self.state = .clientIdleServerIdle(.init(maximumPayloadSize: maximumPayloadSize))
    self.configuration = configuration
    self.skipAssertions = skipAssertions
  }

  mutating func send(metadata: Metadata) throws -> HPACKHeaders {
    switch self.configuration {
    case .client(let clientConfiguration):
      return try self.clientSend(metadata: metadata, configuration: clientConfiguration)
    case .server(let serverConfiguration):
      return try self.serverSend(metadata: metadata, configuration: serverConfiguration)
    }
  }

  mutating func send(message: [UInt8]) throws {
    switch self.configuration {
    case .client:
      try self.clientSend(message: message)
    case .server:
      try self.serverSend(message: message)
    }
  }

  mutating func closeOutbound() throws {
    switch self.configuration {
    case .client:
      try self.clientCloseOutbound()
    case .server:
      try self.invalidState("Server cannot call close: it must send status and trailers.")
    }
  }

  mutating func send(
    status: Status,
    metadata: Metadata
  ) throws -> HPACKHeaders {
    switch self.configuration {
    case .client:
      try self.invalidState(
        "Client cannot send status and trailer."
      )
    case .server:
      return try self.serverSend(
        status: status,
        customMetadata: metadata
      )
    }
  }

  enum OnMetadataReceived: Equatable {
    case receivedMetadata(Metadata)

    // Client-specific actions
    case receivedStatusAndMetadata(status: Status, metadata: Metadata)
    case doNothing

    // Server-specific actions
    case rejectRPC(trailers: HPACKHeaders)
  }

  mutating func receive(headers: HPACKHeaders, endStream: Bool) throws -> OnMetadataReceived {
    switch self.configuration {
    case .client:
      return try self.clientReceive(headers: headers, endStream: endStream)
    case .server(let serverConfiguration):
      return try self.serverReceive(
        headers: headers,
        endStream: endStream,
        configuration: serverConfiguration
      )
    }
  }

  mutating func receive(buffer: ByteBuffer, endStream: Bool) throws {
    switch self.configuration {
    case .client:
      try self.clientReceive(buffer: buffer, endStream: endStream)
    case .server:
      try self.serverReceive(buffer: buffer, endStream: endStream)
    }
  }

  /// The result of requesting the next outbound message.
  enum OnNextOutboundMessage: Equatable {
    /// Either the receiving party is closed, so we shouldn't send any more messages; or the sender is done
    /// writing messages (i.e. we are now closed).
    case noMoreMessages
    /// There isn't a message ready to be sent, but we could still receive more, so keep trying.
    case awaitMoreMessages
    /// A message is ready to be sent.
    case sendMessage(ByteBuffer)
  }

  mutating func nextOutboundMessage() throws -> OnNextOutboundMessage {
    switch self.configuration {
    case .client:
      return try self.clientNextOutboundMessage()
    case .server:
      return try self.serverNextOutboundMessage()
    }
  }

  /// The result of requesting the next inbound message.
  enum OnNextInboundMessage: Equatable {
    /// The sender is done writing messages and there are no more messages to be received.
    case noMoreMessages
    /// There isn't a message ready to be sent, but we could still receive more, so keep trying.
    case awaitMoreMessages
    /// A message has been received.
    case receiveMessage([UInt8])
  }

  mutating func nextInboundMessage() -> OnNextInboundMessage {
    switch self.configuration {
    case .client:
      return self.clientNextInboundMessage()
    case .server:
      return self.serverNextInboundMessage()
    }
  }

  mutating func tearDown() {
    switch self.state {
    case .clientIdleServerIdle:
      ()
    case .clientOpenServerIdle(let state):
      state.compressor?.end()
      state.decompressor?.end()
    case .clientOpenServerOpen(let state):
      state.compressor?.end()
      state.decompressor?.end()
    case .clientOpenServerClosed(let state):
      state.compressor?.end()
      state.decompressor?.end()
    case .clientClosedServerIdle(let state):
      state.compressor?.end()
      state.decompressor?.end()
    case .clientClosedServerOpen(let state):
      state.compressor?.end()
      state.decompressor?.end()
    case .clientClosedServerClosed(let state):
      state.compressor?.end()
    }
  }
}

// - MARK: Client

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine {
  private func makeClientHeaders(
    methodDescriptor: MethodDescriptor,
    scheme: Scheme,
    outboundEncoding: CompressionAlgorithm?,
    acceptedEncodings: [CompressionAlgorithm],
    customMetadata: Metadata
  ) -> HPACKHeaders {
    var headers = HPACKHeaders()
    headers.reserveCapacity(7 + customMetadata.count)

    // Add required headers.
    // See https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#requests

    // The order is important here: reserved HTTP2 headers (those starting with `:`)
    // must come before all other headers.
    headers.add("POST", forKey: .method)
    headers.add(scheme.rawValue, forKey: .scheme)
    headers.add(methodDescriptor.fullyQualifiedMethod, forKey: .path)

    // Add required gRPC headers.
    headers.add(ContentType.grpc.canonicalValue, forKey: .contentType)
    headers.add("trailers", forKey: .te)  // Used to detect incompatible proxies

    if let encoding = outboundEncoding, encoding != .identity {
      headers.add(encoding.name, forKey: .encoding)
    }

    for acceptedEncoding in acceptedEncodings {
      headers.add(acceptedEncoding.name, forKey: .acceptEncoding)
    }

    for metadataPair in customMetadata {
      headers.add(name: metadataPair.key, value: metadataPair.value.encoded())
    }

    return headers
  }

  private mutating func clientSend(
    metadata: Metadata,
    configuration: GRPCStreamStateMachineConfiguration.ClientConfiguration
  ) throws -> HPACKHeaders {
    // Client sends metadata only when opening the stream.
    switch self.state {
    case .clientIdleServerIdle(let state):
      let outboundEncoding = configuration.outboundEncoding
      let compressor = Zlib.Method(encoding: outboundEncoding)
        .flatMap { Zlib.Compressor(method: $0) }
      self.state = .clientOpenServerIdle(
        .init(
          previousState: state,
          compressor: compressor,
          framer: GRPCMessageFramer(),
          decompressor: nil,
          deframer: nil
        )
      )
      return self.makeClientHeaders(
        methodDescriptor: configuration.methodDescriptor,
        scheme: configuration.scheme,
        outboundEncoding: configuration.outboundEncoding,
        acceptedEncodings: configuration.acceptedEncodings,
        customMetadata: metadata
      )
    case .clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed:
      try self.invalidState(
        "Client is already open: shouldn't be sending metadata."
      )
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      try self.invalidState(
        "Client is closed: can't send metadata."
      )
    }
  }

  private mutating func clientSend(message: [UInt8]) throws {
    switch self.state {
    case .clientIdleServerIdle:
      try self.invalidState("Client not yet open.")
    case .clientOpenServerIdle(var state):
      state.framer.append(message)
      self.state = .clientOpenServerIdle(state)
    case .clientOpenServerOpen(var state):
      state.framer.append(message)
      self.state = .clientOpenServerOpen(state)
    case .clientOpenServerClosed:
      // The server has closed, so it makes no sense to send the rest of the request.
      ()
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      try self.invalidState(
        "Client is closed, cannot send a message."
      )
    }
  }

  private mutating func clientCloseOutbound() throws {
    switch self.state {
    case .clientIdleServerIdle:
      try self.invalidState("Client not yet open.")
    case .clientOpenServerIdle(let state):
      self.state = .clientClosedServerIdle(.init(previousState: state))
    case .clientOpenServerOpen(let state):
      self.state = .clientClosedServerOpen(.init(previousState: state))
    case .clientOpenServerClosed(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      try self.invalidState(
        "Client is closed, cannot send a message."
      )
    }
  }

  /// Returns the client's next request to the server.
  /// - Returns: The request to be made to the server.
  private mutating func clientNextOutboundMessage() throws -> OnNextOutboundMessage {
    switch self.state {
    case .clientIdleServerIdle:
      try self.invalidState("Client is not open yet.")
    case .clientOpenServerIdle(var state):
      let request = try state.framer.next(compressor: state.compressor)
      self.state = .clientOpenServerIdle(state)
      return request.map { .sendMessage($0) } ?? .awaitMoreMessages
    case .clientOpenServerOpen(var state):
      let request = try state.framer.next(compressor: state.compressor)
      self.state = .clientOpenServerOpen(state)
      return request.map { .sendMessage($0) } ?? .awaitMoreMessages
    case .clientClosedServerIdle(var state):
      let request = try state.framer.next(compressor: state.compressor)
      self.state = .clientClosedServerIdle(state)
      if let request {
        return .sendMessage(request)
      } else {
        return .noMoreMessages
      }
    case .clientClosedServerOpen(var state):
      let request = try state.framer.next(compressor: state.compressor)
      self.state = .clientClosedServerOpen(state)
      if let request {
        return .sendMessage(request)
      } else {
        return .noMoreMessages
      }
    case .clientOpenServerClosed, .clientClosedServerClosed:
      // No point in sending any more requests if the server is closed.
      return .noMoreMessages
    }
  }

  private enum ServerHeadersValidationResult {
    case valid
    case invalid(OnMetadataReceived)
  }

  private mutating func clientValidateHeadersReceivedFromServer(
    _ metadata: HPACKHeaders
  ) -> ServerHeadersValidationResult {
    var httpStatus: String? {
      metadata.firstString(forKey: .status)
    }
    var grpcStatus: Status.Code? {
      metadata.firstString(forKey: .grpcStatus)
        .flatMap { Int($0) }
        .flatMap { Status.Code(rawValue: $0) }
    }
    guard httpStatus == "200" || grpcStatus != nil else {
      let httpStatusCode =
        httpStatus
        .flatMap { Int($0) }
        .map { HTTPResponseStatus(statusCode: $0) }

      guard let httpStatusCode else {
        return .invalid(
          .receivedStatusAndMetadata(
            status: .init(code: .unknown, message: "HTTP Status Code is missing."),
            metadata: Metadata(headers: metadata)
          )
        )
      }

      if (100 ... 199).contains(httpStatusCode.code) {
        // For 1xx status codes, the entire header should be skipped and a
        // subsequent header should be read.
        // See https://github.com/grpc/grpc/blob/master/doc/http-grpc-status-mapping.md
        return .invalid(.doNothing)
      }

      // Forward the mapped status code.
      return .invalid(
        .receivedStatusAndMetadata(
          status: .init(
            code: Status.Code(httpStatusCode: httpStatusCode),
            message: "Unexpected non-200 HTTP Status Code."
          ),
          metadata: Metadata(headers: metadata)
        )
      )
    }

    let contentTypeHeader = metadata.first(name: GRPCHTTP2Keys.contentType.rawValue)
    guard contentTypeHeader.flatMap(ContentType.init) != nil else {
      return .invalid(
        .receivedStatusAndMetadata(
          status: .init(
            code: .internalError,
            message: "Missing \(GRPCHTTP2Keys.contentType) header"
          ),
          metadata: Metadata(headers: metadata)
        )
      )
    }

    return .valid
  }

  private enum ProcessInboundEncodingResult {
    case error(OnMetadataReceived)
    case success(CompressionAlgorithm)
  }

  private func processInboundEncoding(_ metadata: HPACKHeaders) -> ProcessInboundEncodingResult {
    let inboundEncoding: CompressionAlgorithm
    if let serverEncoding = metadata.first(name: GRPCHTTP2Keys.encoding.rawValue) {
      guard let parsedEncoding = CompressionAlgorithm(rawValue: serverEncoding) else {
        return .error(
          .receivedStatusAndMetadata(
            status: .init(
              code: .internalError,
              message:
                "The server picked a compression algorithm ('\(serverEncoding)') the client does not know about."
            ),
            metadata: Metadata(headers: metadata)
          )
        )
      }
      inboundEncoding = parsedEncoding
    } else {
      inboundEncoding = .identity
    }
    return .success(inboundEncoding)
  }

  private func validateAndReturnStatusAndMetadata(
    _ metadata: HPACKHeaders
  ) throws -> OnMetadataReceived {
    let rawStatusCode = metadata.firstString(forKey: .grpcStatus)
    guard let rawStatusCode,
      let intStatusCode = Int(rawStatusCode),
      let statusCode = Status.Code(rawValue: intStatusCode)
    else {
      let message =
        "Non-initial metadata must be a trailer containing a valid grpc-status"
        + (rawStatusCode.flatMap { "but was \($0)" } ?? "")
      throw RPCError(code: .unknown, message: message)
    }

    let statusMessage =
      metadata.firstString(forKey: .grpcStatusMessage)
      .map { GRPCStatusMessageMarshaller.unmarshall($0) } ?? ""

    var convertedMetadata = Metadata(headers: metadata)
    convertedMetadata.removeAllValues(forKey: GRPCHTTP2Keys.grpcStatus.rawValue)
    convertedMetadata.removeAllValues(forKey: GRPCHTTP2Keys.grpcStatusMessage.rawValue)

    return .receivedStatusAndMetadata(
      status: Status(code: statusCode, message: statusMessage),
      metadata: convertedMetadata
    )
  }

  private mutating func clientReceive(
    headers: HPACKHeaders,
    endStream: Bool
  ) throws -> OnMetadataReceived {
    switch self.state {
    case .clientOpenServerIdle(let state):
      switch (self.clientValidateHeadersReceivedFromServer(headers), endStream) {
      case (.invalid(let action), true):
        // The headers are invalid, but the server signalled that it was
        // closing the stream, so close both client and server.
        self.state = .clientClosedServerClosed(.init(previousState: state))
        return action
      case (.invalid(let action), false):
        self.state = .clientClosedServerIdle(.init(previousState: state))
        return action
      case (.valid, true):
        // This is a trailers-only response: close server.
        self.state = .clientOpenServerClosed(.init(previousState: state))
        return try self.validateAndReturnStatusAndMetadata(headers)
      case (.valid, false):
        switch self.processInboundEncoding(headers) {
        case .error(let failure):
          return failure
        case .success(let inboundEncoding):
          let decompressor = Zlib.Method(encoding: inboundEncoding)
            .flatMap { Zlib.Decompressor(method: $0) }
          let deframer = GRPCMessageDeframer(
            maximumPayloadSize: state.maximumPayloadSize,
            decompressor: decompressor
          )

          self.state = .clientOpenServerOpen(
            .init(
              previousState: state,
              deframer: NIOSingleStepByteToMessageProcessor(deframer),
              decompressor: decompressor
            )
          )
          return .receivedMetadata(Metadata(headers: headers))
        }
      }

    case .clientOpenServerOpen(let state):
      // This state is valid even if endStream is not set: server can send
      // trailing metadata without END_STREAM set, and follow it with an
      // empty message frame where it is set.
      // However, we must make sure that grpc-status is set, otherwise this
      // is an invalid state.
      if endStream {
        self.state = .clientOpenServerClosed(.init(previousState: state))
      }
      return try self.validateAndReturnStatusAndMetadata(headers)

    case .clientClosedServerIdle(let state):
      switch (self.clientValidateHeadersReceivedFromServer(headers), endStream) {
      case (.invalid(let action), true):
        // The headers are invalid, but the server signalled that it was
        // closing the stream, so close the server side too.
        self.state = .clientClosedServerClosed(.init(previousState: state))
        return action
      case (.invalid(let action), false):
        // Client is already closed, so we don't need to update our state.
        return action
      case (.valid, true):
        // This is a trailers-only response: close server.
        self.state = .clientClosedServerClosed(.init(previousState: state))
        return try self.validateAndReturnStatusAndMetadata(headers)
      case (.valid, false):
        switch self.processInboundEncoding(headers) {
        case .error(let failure):
          return failure
        case .success(let inboundEncoding):
          self.state = .clientClosedServerOpen(
            .init(
              previousState: state,
              decompressionAlgorithm: inboundEncoding
            )
          )
          return .receivedMetadata(Metadata(headers: headers))
        }
      }

    case .clientClosedServerOpen(let state):
      // This state is valid even if endStream is not set: server can send
      // trailing metadata without END_STREAM set, and follow it with an
      // empty message frame where it is set.
      // However, we must make sure that grpc-status is set, otherwise this
      // is an invalid state.
      if endStream {
        self.state = .clientClosedServerClosed(.init(previousState: state))
      }
      return try self.validateAndReturnStatusAndMetadata(headers)

    case .clientClosedServerClosed:
      // We could end up here if we received a grpc-status header in a previous
      // frame (which would have already close the server) and then we receive
      // an empty frame with EOS set.
      // We wouldn't want to throw in that scenario, so we just ignore it.
      // Note that we don't want to ignore it if EOS is not set here though, as
      // then it would be an invalid payload.
      if !endStream || headers.count > 0 {
        try self.invalidState(
          "Server is closed, nothing could have been sent."
        )
      }
      return .doNothing
    case .clientIdleServerIdle:
      try self.invalidState(
        "Server cannot have sent metadata if the client is idle."
      )
    case .clientOpenServerClosed:
      try self.invalidState(
        "Server is closed, nothing could have been sent."
      )
    }
  }

  private mutating func clientReceive(buffer: ByteBuffer, endStream: Bool) throws {
    // This is a message received by the client, from the server.
    switch self.state {
    case .clientIdleServerIdle:
      try self.invalidState(
        "Cannot have received anything from server if client is not yet open."
      )
    case .clientOpenServerIdle, .clientClosedServerIdle:
      try self.invalidState(
        "Server cannot have sent a message before sending the initial metadata."
      )
    case .clientOpenServerOpen(var state):
      try state.deframer.process(buffer: buffer) { deframedMessage in
        state.inboundMessageBuffer.append(deframedMessage)
      }
      if endStream {
        self.state = .clientOpenServerClosed(.init(previousState: state))
      } else {
        self.state = .clientOpenServerOpen(state)
      }
    case .clientClosedServerOpen(var state):
      // The client may have sent the end stream and thus it's closed,
      // but the server may still be responding.
      // The client must have a deframer set up, so force-unwrap is okay.
      try state.deframer!.process(buffer: buffer) { deframedMessage in
        state.inboundMessageBuffer.append(deframedMessage)
      }
      if endStream {
        self.state = .clientClosedServerClosed(.init(previousState: state))
      } else {
        self.state = .clientClosedServerOpen(state)
      }
    case .clientOpenServerClosed, .clientClosedServerClosed:
      try self.invalidState(
        "Cannot have received anything from a closed server."
      )
    }
  }

  private mutating func clientNextInboundMessage() -> OnNextInboundMessage {
    switch self.state {
    case .clientOpenServerOpen(var state):
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerOpen(state)
      return message.map { .receiveMessage($0) } ?? .awaitMoreMessages
    case .clientOpenServerClosed(var state):
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerClosed(state)
      return message.map { .receiveMessage($0) } ?? .noMoreMessages
    case .clientClosedServerOpen(var state):
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerOpen(state)
      return message.map { .receiveMessage($0) } ?? .awaitMoreMessages
    case .clientClosedServerClosed(var state):
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerClosed(state)
      return message.map { .receiveMessage($0) } ?? .noMoreMessages
    case .clientIdleServerIdle,
      .clientOpenServerIdle,
      .clientClosedServerIdle:
      return .awaitMoreMessages
    }
  }

  private func invalidState(_ message: String, line: UInt = #line) throws -> Never {
    if !self.skipAssertions {
      assertionFailure(message, line: line)
    }
    throw RPCError(code: .internalError, message: message)
  }
}

// - MARK: Server

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine {
  private func makeResponseHeaders(
    outboundEncoding: CompressionAlgorithm?,
    configuration: GRPCStreamStateMachineConfiguration.ServerConfiguration,
    customMetadata: Metadata
  ) -> HPACKHeaders {
    // Response headers always contain :status (HTTP Status 200) and content-type.
    // They may also contain grpc-encoding, grpc-accept-encoding, and custom metadata.
    var headers = HPACKHeaders()
    headers.reserveCapacity(4 + customMetadata.count)

    headers.add("200", forKey: .status)
    headers.add(ContentType.grpc.canonicalValue, forKey: .contentType)

    if let outboundEncoding, outboundEncoding != .identity {
      headers.add(outboundEncoding.name, forKey: .encoding)
    }

    for acceptedEncoding in configuration.acceptedEncodings {
      headers.add(acceptedEncoding.name, forKey: .acceptEncoding)
    }

    for metadataPair in customMetadata {
      headers.add(name: metadataPair.key, value: metadataPair.value.encoded())
    }

    return headers
  }

  private mutating func serverSend(
    metadata: Metadata,
    configuration: GRPCStreamStateMachineConfiguration.ServerConfiguration
  ) throws -> HPACKHeaders {
    // Server sends initial metadata
    switch self.state {
    case .clientOpenServerIdle(let state):
      self.state = .clientOpenServerOpen(
        .init(
          previousState: state,
          // In the case of the server, it will already have a deframer set up,
          // because it already knows what encoding the client is using:
          // it's okay to force-unwrap.
          deframer: state.deframer!,
          decompressor: state.decompressor
        )
      )
      return self.makeResponseHeaders(
        outboundEncoding: state.outboundCompression,
        configuration: configuration,
        customMetadata: metadata
      )
    case .clientClosedServerIdle(let state):
      self.state = .clientClosedServerOpen(.init(previousState: state))
      return self.makeResponseHeaders(
        outboundEncoding: state.outboundCompression,
        configuration: configuration,
        customMetadata: metadata
      )
    case .clientIdleServerIdle:
      try self.invalidState(
        "Client cannot be idle if server is sending initial metadata: it must have opened."
      )
    case .clientOpenServerClosed, .clientClosedServerClosed:
      try self.invalidState(
        "Server cannot send metadata if closed."
      )
    case .clientOpenServerOpen, .clientClosedServerOpen:
      try self.invalidState(
        "Server has already sent initial metadata."
      )
    }
  }

  private mutating func serverSend(message: [UInt8]) throws {
    switch self.state {
    case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
      try self.invalidState(
        "Server must have sent initial metadata before sending a message."
      )
    case .clientOpenServerOpen(var state):
      state.framer.append(message)
      self.state = .clientOpenServerOpen(state)
    case .clientClosedServerOpen(var state):
      state.framer.append(message)
      self.state = .clientClosedServerOpen(state)
    case .clientOpenServerClosed, .clientClosedServerClosed:
      try self.invalidState(
        "Server can't send a message if it's closed."
      )
    }
  }

  private func makeTrailers(
    status: Status,
    customMetadata: Metadata?,
    trailersOnly: Bool
  ) -> HPACKHeaders {
    // Trailers always contain the grpc-status header, and optionally,
    // grpc-status-message, and custom metadata.
    // If it's a trailers-only response, they will also contain :status and
    // content-type.
    var headers = HPACKHeaders()
    let customMetadataCount = customMetadata?.count ?? 0
    if trailersOnly {
      // Reserve 4 for capacity: 3 for the required headers, and 1 for the
      // optional status message.
      headers.reserveCapacity(4 + customMetadataCount)
      headers.add("200", forKey: .status)
      headers.add(ContentType.grpc.canonicalValue, forKey: .contentType)
    } else {
      // Reserve 2 for capacity: one for the required grpc-status, and
      // one for the optional message.
      headers.reserveCapacity(2 + customMetadataCount)
    }

    headers.add(String(status.code.rawValue), forKey: .grpcStatus)

    if !status.message.isEmpty {
      if let percentEncodedMessage = GRPCStatusMessageMarshaller.marshall(status.message) {
        headers.add(percentEncodedMessage, forKey: .grpcStatusMessage)
      }
    }

    if let customMetadata {
      for metadataPair in customMetadata {
        headers.add(name: metadataPair.key, value: metadataPair.value.encoded())
      }
    }

    return headers
  }

  private mutating func serverSend(
    status: Status,
    customMetadata: Metadata
  ) throws -> HPACKHeaders {
    // Close the server.
    switch self.state {
    case .clientOpenServerOpen(let state):
      self.state = .clientOpenServerClosed(.init(previousState: state))
      return self.makeTrailers(
        status: status,
        customMetadata: customMetadata,
        trailersOnly: false
      )
    case .clientClosedServerOpen(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return self.makeTrailers(
        status: status,
        customMetadata: customMetadata,
        trailersOnly: false
      )
    case .clientOpenServerIdle(let state):
      self.state = .clientOpenServerClosed(.init(previousState: state))
      return self.makeTrailers(
        status: status,
        customMetadata: customMetadata,
        trailersOnly: true
      )
    case .clientClosedServerIdle(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return self.makeTrailers(
        status: status,
        customMetadata: customMetadata,
        trailersOnly: true
      )
    case .clientIdleServerIdle:
      try self.invalidState(
        "Server can't send status if client is idle."
      )
    case .clientOpenServerClosed, .clientClosedServerClosed:
      try self.invalidState(
        "Server can't send anything if closed."
      )
    }
  }

  mutating private func closeServerAndBuildRejectRPCAction(
    currentState: GRPCStreamStateMachineState.ClientIdleServerIdleState,
    endStream: Bool,
    rejectWithStatus status: Status
  ) -> OnMetadataReceived {
    if endStream {
      self.state = .clientClosedServerClosed(.init(previousState: currentState))
    } else {
      self.state = .clientOpenServerClosed(.init(previousState: currentState))
    }

    let trailers = self.makeTrailers(status: status, customMetadata: nil, trailersOnly: true)
    return .rejectRPC(trailers: trailers)
  }

  private mutating func serverReceive(
    headers: HPACKHeaders,
    endStream: Bool,
    configuration: GRPCStreamStateMachineConfiguration.ServerConfiguration
  ) throws -> OnMetadataReceived {
    switch self.state {
    case .clientIdleServerIdle(let state):
      let contentType = headers.firstString(forKey: .contentType)
        .flatMap { ContentType(value: $0) }
      if contentType == nil {
        self.state = .clientOpenServerClosed(.init(previousState: state))

        // Respond with HTTP-level Unsupported Media Type status code.
        var trailers = HPACKHeaders()
        trailers.add("415", forKey: .status)
        return .rejectRPC(trailers: trailers)
      }

      let path = headers.firstString(forKey: .path)
        .flatMap { MethodDescriptor(fullyQualifiedMethod: $0) }
      if path == nil {
        return self.closeServerAndBuildRejectRPCAction(
          currentState: state,
          endStream: endStream,
          rejectWithStatus: Status(
            code: .unimplemented,
            message: "No \(GRPCHTTP2Keys.path.rawValue) header has been set."
          )
        )
      }

      let scheme = headers.firstString(forKey: .scheme)
        .flatMap { Scheme(rawValue: $0) }
      if scheme == nil {
        return self.closeServerAndBuildRejectRPCAction(
          currentState: state,
          endStream: endStream,
          rejectWithStatus: Status(
            code: .invalidArgument,
            message: ":scheme header must be present and one of \"http\" or \"https\"."
          )
        )
      }

      guard let method = headers.firstString(forKey: .method), method == "POST" else {
        return self.closeServerAndBuildRejectRPCAction(
          currentState: state,
          endStream: endStream,
          rejectWithStatus: Status(
            code: .invalidArgument,
            message: ":method header is expected to be present and have a value of \"POST\"."
          )
        )
      }

      guard let te = headers.firstString(forKey: .te), te == "trailers" else {
        return self.closeServerAndBuildRejectRPCAction(
          currentState: state,
          endStream: endStream,
          rejectWithStatus: Status(
            code: .invalidArgument,
            message: "\"te\" header is expected to be present and have a value of \"trailers\"."
          )
        )
      }

      func isIdentityOrCompatibleEncoding(_ clientEncoding: CompressionAlgorithm) -> Bool {
        clientEncoding == .identity || configuration.acceptedEncodings.contains(clientEncoding)
      }

      // Firstly, find out if we support the client's chosen encoding, and reject
      // the RPC if we don't.
      let inboundEncoding: CompressionAlgorithm
      let encodingValues = headers.values(
        forHeader: GRPCHTTP2Keys.encoding.rawValue,
        canonicalForm: true
      )
      var encodingValuesIterator = encodingValues.makeIterator()
      if let rawEncoding = encodingValuesIterator.next() {
        guard encodingValuesIterator.next() == nil else {
          let status = Status(
            code: .internalError,
            message: "\(GRPCHTTP2Keys.encoding) must contain no more than one value."
          )
          let trailers = self.makeTrailers(status: status, customMetadata: nil, trailersOnly: true)
          return .rejectRPC(trailers: trailers)
        }

        guard let clientEncoding = CompressionAlgorithm(rawValue: String(rawEncoding)),
          isIdentityOrCompatibleEncoding(clientEncoding)
        else {
          let statusMessage: String
          let customMetadata: Metadata?
          if configuration.acceptedEncodings.isEmpty {
            statusMessage = "Compression is not supported"
            customMetadata = nil
          } else {
            statusMessage = """
              \(rawEncoding) compression is not supported; \
              supported algorithms are listed in grpc-accept-encoding
              """
            customMetadata = {
              var trailers = Metadata()
              trailers.reserveCapacity(configuration.acceptedEncodings.count)
              for acceptedEncoding in configuration.acceptedEncodings {
                trailers.addString(
                  acceptedEncoding.name,
                  forKey: GRPCHTTP2Keys.acceptEncoding.rawValue
                )
              }
              return trailers
            }()
          }

          let trailers = self.makeTrailers(
            status: Status(code: .unimplemented, message: statusMessage),
            customMetadata: customMetadata,
            trailersOnly: true
          )
          return .rejectRPC(trailers: trailers)
        }

        // Server supports client's encoding.
        inboundEncoding = clientEncoding
      } else {
        inboundEncoding = .identity
      }

      // Secondly, find a compatible encoding the server can use to compress outbound messages,
      // based on the encodings the client has advertised.
      var outboundEncoding: CompressionAlgorithm = .identity
      let clientAdvertisedEncodings = headers.values(
        forHeader: GRPCHTTP2Keys.acceptEncoding.rawValue,
        canonicalForm: true
      )
      // Find the preferred encoding and use it to compress responses.
      // If it's identity, just skip it altogether, since we won't be
      // compressing.
      for clientAdvertisedEncoding in clientAdvertisedEncodings {
        if let algorithm = CompressionAlgorithm(rawValue: String(clientAdvertisedEncoding)),
          isIdentityOrCompatibleEncoding(algorithm)
        {
          outboundEncoding = algorithm
          break
        }
      }

      if endStream {
        self.state = .clientClosedServerIdle(
          .init(
            previousState: state,
            compressionAlgorithm: outboundEncoding
          )
        )
      } else {
        let compressor = Zlib.Method(encoding: outboundEncoding)
          .flatMap { Zlib.Compressor(method: $0) }
        let decompressor = Zlib.Method(encoding: inboundEncoding)
          .flatMap { Zlib.Decompressor(method: $0) }
        let deframer = GRPCMessageDeframer(
          maximumPayloadSize: state.maximumPayloadSize,
          decompressor: decompressor
        )

        self.state = .clientOpenServerIdle(
          .init(
            previousState: state,
            compressor: compressor,
            framer: GRPCMessageFramer(),
            decompressor: decompressor,
            deframer: NIOSingleStepByteToMessageProcessor(deframer)
          )
        )
      }

      return .receivedMetadata(Metadata(headers: headers))
    case .clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed:
      try self.invalidState(
        "Client shouldn't have sent metadata twice."
      )
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      try self.invalidState(
        "Client can't have sent metadata if closed."
      )
    }
  }

  private mutating func serverReceive(buffer: ByteBuffer, endStream: Bool) throws {
    switch self.state {
    case .clientIdleServerIdle:
      try self.invalidState(
        "Can't have received a message if client is idle."
      )
    case .clientOpenServerIdle(var state):
      // Deframer must be present on the server side, as we know the decompression
      // algorithm from the moment the client opens.
      try state.deframer!.process(buffer: buffer) { deframedMessage in
        state.inboundMessageBuffer.append(deframedMessage)
      }

      if endStream {
        self.state = .clientClosedServerIdle(.init(previousState: state))
      } else {
        self.state = .clientOpenServerIdle(state)
      }
    case .clientOpenServerOpen(var state):
      try state.deframer.process(buffer: buffer) { deframedMessage in
        state.inboundMessageBuffer.append(deframedMessage)
      }

      if endStream {
        self.state = .clientClosedServerOpen(.init(previousState: state))
      } else {
        self.state = .clientOpenServerOpen(state)
      }
    case .clientOpenServerClosed(let state):
      // Client is not done sending request, but server has already closed.
      // Ignore the rest of the request: do nothing, unless endStream is set,
      // in which case close the client.
      if endStream {
        self.state = .clientClosedServerClosed(.init(previousState: state))
      }
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      try self.invalidState(
        "Client can't send a message if closed."
      )
    }
  }

  private mutating func serverNextOutboundMessage() throws -> OnNextOutboundMessage {
    switch self.state {
    case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
      try self.invalidState("Server is not open yet.")
    case .clientOpenServerOpen(var state):
      let response = try state.framer.next(compressor: state.compressor)
      self.state = .clientOpenServerOpen(state)
      return response.map { .sendMessage($0) } ?? .awaitMoreMessages
    case .clientClosedServerOpen(var state):
      let response = try state.framer.next(compressor: state.compressor)
      self.state = .clientClosedServerOpen(state)
      return response.map { .sendMessage($0) } ?? .awaitMoreMessages
    case .clientOpenServerClosed(var state):
      let response = try state.framer?.next(compressor: state.compressor)
      self.state = .clientOpenServerClosed(state)
      if let response {
        return .sendMessage(response)
      } else {
        return .noMoreMessages
      }
    case .clientClosedServerClosed(var state):
      let response = try state.framer?.next(compressor: state.compressor)
      self.state = .clientClosedServerClosed(state)
      if let response {
        return .sendMessage(response)
      } else {
        return .noMoreMessages
      }
    }
  }

  private mutating func serverNextInboundMessage() -> OnNextInboundMessage {
    switch self.state {
    case .clientOpenServerIdle(var state):
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerIdle(state)
      return request.map { .receiveMessage($0) } ?? .awaitMoreMessages
    case .clientOpenServerOpen(var state):
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerOpen(state)
      return request.map { .receiveMessage($0) } ?? .awaitMoreMessages
    case .clientOpenServerClosed(var state):
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerClosed(state)
      return request.map { .receiveMessage($0) } ?? .awaitMoreMessages
    case .clientClosedServerOpen(var state):
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerOpen(state)
      return request.map { .receiveMessage($0) } ?? .noMoreMessages
    case .clientClosedServerClosed(var state):
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerClosed(state)
      return request.map { .receiveMessage($0) } ?? .noMoreMessages
    case .clientClosedServerIdle:
      return .noMoreMessages
    case .clientIdleServerIdle:
      return .awaitMoreMessages
    }
  }
}

extension MethodDescriptor {
  init?(fullyQualifiedMethod: String) {
    let split = fullyQualifiedMethod.split(separator: "/")
    guard split.count == 2 else {
      return nil
    }
    self.init(service: String(split[0]), method: String(split[1]))
  }
}

internal enum GRPCHTTP2Keys: String {
  case path = ":path"
  case contentType = "content-type"
  case encoding = "grpc-encoding"
  case acceptEncoding = "grpc-accept-encoding"
  case scheme = ":scheme"
  case method = ":method"
  case te = "te"
  case status = ":status"
  case grpcStatus = "grpc-status"
  case grpcStatusMessage = "grpc-status-message"
}

extension HPACKHeaders {
  internal func firstString(forKey key: GRPCHTTP2Keys) -> String? {
    self.values(forHeader: key.rawValue, canonicalForm: true).first(where: { _ in true }).map {
      String($0)
    }
  }

  internal mutating func add(_ value: String, forKey key: GRPCHTTP2Keys) {
    self.add(name: key.rawValue, value: value)
  }
}

extension Zlib.Method {
  init?(encoding: CompressionAlgorithm) {
    switch encoding {
    case .identity:
      return nil
    case .deflate:
      self = .deflate
    case .gzip:
      self = .gzip
    default:
      return nil
    }
  }
}

extension Metadata {
  init(headers: HPACKHeaders) {
    var metadata = Metadata()
    metadata.reserveCapacity(headers.count)
    for header in headers {
      if header.name.hasSuffix("-bin") {
        do {
          let decodedBinary = try header.value.base64Decoded()
          metadata.addBinary(decodedBinary, forKey: header.name)
        } catch {
          metadata.addString(header.value, forKey: header.name)
        }
      } else {
        metadata.addString(header.value, forKey: header.name)
      }
    }
    self = metadata
  }
}

extension Status.Code {
  // See https://github.com/grpc/grpc/blob/master/doc/http-grpc-status-mapping.md
  init(httpStatusCode: HTTPResponseStatus) {
    switch httpStatusCode {
    case .badRequest:
      self = .internalError
    case .unauthorized:
      self = .unauthenticated
    case .forbidden:
      self = .permissionDenied
    case .notFound:
      self = .unimplemented
    case .tooManyRequests, .badGateway, .serviceUnavailable, .gatewayTimeout:
      self = .unavailable
    default:
      self = .unknown
    }
  }
}
