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
    var outboundEncoding: CompressionAlgorithm?
    var acceptedEncodings: [CompressionAlgorithm]
  }

  struct ServerConfiguration {
    var scheme: Scheme
    var acceptedEncodings: [CompressionAlgorithm]
  }
}

enum GRPCStreamStateMachineState {
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

  enum DecompressionConfiguration {
    case decompressionNotYetKnown
    case decompression(CompressionAlgorithm?)
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
      compressionAlgorithm: CompressionAlgorithm?,
      decompressionConfiguration: DecompressionConfiguration
    ) {
      self.maximumPayloadSize = previousState.maximumPayloadSize

      if let zlibMethod = Zlib.Method(encoding: compressionAlgorithm) {
        self.compressor = Zlib.Compressor(method: zlibMethod)
      }
      self.framer = GRPCMessageFramer()
      self.outboundCompression = compressionAlgorithm

      // In the case of the server, we will know what the decompression algorithm
      // will be, since we know what the inbound encoding is, as the client has
      // sent it when starting the request.
      // In the case of the client, it will need to wait until the server responds
      // with its initial metadata.
      if case .decompression(let decompressionAlgorithm) = decompressionConfiguration {
        if let zlibMethod = Zlib.Method(encoding: decompressionAlgorithm) {
          self.decompressor = Zlib.Decompressor(method: zlibMethod)
        }
        let decoder = GRPCMessageDeframer(
          maximumPayloadSize: previousState.maximumPayloadSize,
          decompressor: self.decompressor
        )
        self.deframer = NIOSingleStepByteToMessageProcessor(decoder)
      } else {
        self.deframer = nil
      }

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
      decompressionAlgorithm: CompressionAlgorithm? = nil
    ) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor

      // In the case of the server, it will already have a deframer set up,
      // because it already knows what encoding the client is using.
      // In the case of the client, it will only be able to set it up
      // after it receives the chosen encoding from the server.
      if let previousDeframer = previousState.deframer {
        self.deframer = previousDeframer
        self.decompressor = previousState.decompressor
      } else {
        if let zlibMethod = Zlib.Method(encoding: decompressionAlgorithm) {
          self.decompressor = Zlib.Decompressor(method: zlibMethod)
        }
        let decoder = GRPCMessageDeframer(
          maximumPayloadSize: previousState.maximumPayloadSize,
          decompressor: self.decompressor
        )
        self.deframer = NIOSingleStepByteToMessageProcessor(decoder)
      }

      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }
  }

  struct ClientOpenServerClosedState {
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

    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>
    var decompressor: Zlib.Decompressor?
    
    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    init(previousState: ClientOpenServerOpenState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    init(
      previousState: ClientClosedServerIdleState,
      decompressionAlgorithm: CompressionAlgorithm? = nil
    ) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer

      // In the case of the server, it will already have a deframer set up,
      // because it already knows what encoding the client is using.
      // In the case of the client, it will only be able to set it up
      // after it receives the chosen encoding from the server.
      if let previousDeframer = previousState.deframer {
        self.deframer = previousDeframer
        self.decompressor = previousState.decompressor
      } else {
        if let zlibMethod = Zlib.Method(encoding: decompressionAlgorithm) {
          self.decompressor = Zlib.Decompressor(method: zlibMethod)
        }
        let decoder = GRPCMessageDeframer(
          maximumPayloadSize: previousState.maximumPayloadSize,
          decompressor: self.decompressor
        )
        self.deframer = NIOSingleStepByteToMessageProcessor(decoder)
      }
    }
  }

  struct ClientClosedServerClosedState {
    // We still need the framer and compressor in case the server has closed
    // but its buffer is not yet empty and still needs to send messages out to
    // the client.
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?

    // These are already deframed, so we don't need the deframer anymore.
    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    init(previousState: ClientClosedServerOpenState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
      previousState.decompressor?.end()
    }

    init(previousState: ClientClosedServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
      previousState.decompressor?.end()
    }

    init(previousState: ClientOpenServerClosedState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
      previousState.decompressor?.end()
    }
  }
}

// - MARK: Client

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

  mutating func send(message: [UInt8], endStream: Bool) throws {
    switch self.configuration {
    case .client:
      try self.clientSend(message: message, endStream: endStream)
    case .server:
      try self.serverSend(message: message, endStream: endStream)
    }
  }

  mutating func send(status: Status, metadata: Metadata, trailersOnly: Bool) throws -> HPACKHeaders
  {
    switch self.configuration {
    case .client:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Client cannot send status and trailer."
      )
    case .server:
      return try self.serverSend(status: status, metadata: metadata, trailersOnly: trailersOnly)
    }
  }

  enum OnMetadataReceived: Equatable {
    case receivedMetadata(Metadata)

    // Client-specific actions
    case failedRequest(Status)
    case doNothing

    // Server-specific actions
    case rejectRPC(trailers: HPACKHeaders)
  }
  
  mutating func receive(metadata: HPACKHeaders, endStream: Bool) throws -> OnMetadataReceived {
    switch self.configuration {
    case .client:
      return try self.clientReceive(metadata: metadata, endStream: endStream)
    case .server(let serverConfiguration):
      return try self.serverReceive(
        metadata: metadata,
        endStream: endStream,
        configuration: serverConfiguration
      )
    }
  }

  mutating func receive(message: ByteBuffer, endStream: Bool) throws {
    switch self.configuration {
    case .client:
      try self.clientReceive(bytes: message, endStream: endStream)
    case .server:
      try self.serverReceive(bytes: message, endStream: endStream)
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

  mutating func nextInboundMessage() -> [UInt8]? {
    switch self.configuration {
    case .client:
      return self.clientNextInboundMessage()
    case .server:
      return self.serverNextInboundMessage()
    }
  }
}

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

    // Add required headers
    // See https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#requests
    headers.path = methodDescriptor
    headers.scheme = scheme
    headers.method = "POST"
    headers.contentType = .protobuf
    headers.te = "trailers"  // Used to detect incompatible proxies

    if let encoding = outboundEncoding {
      headers.encoding = encoding
    }

    if !acceptedEncodings.isEmpty {
      headers.acceptedEncodings = acceptedEncodings
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
      self.state = .clientOpenServerIdle(
        .init(
          previousState: state,
          compressionAlgorithm: configuration.outboundEncoding,
          decompressionConfiguration: .decompressionNotYetKnown
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
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Client is already open: shouldn't be sending metadata."
      )
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Client is closed: can't send metadata."
      )
    }
  }

  private mutating func clientSend(message: [UInt8], endStream: Bool) throws {
    // Client sends message.
    switch self.state {
    case .clientIdleServerIdle:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError("Client not yet open.")
    case .clientOpenServerIdle(var state):
      state.framer.append(message)
      if endStream {
        self.state = .clientClosedServerIdle(.init(previousState: state))
      } else {
        self.state = .clientOpenServerIdle(state)
      }
    case .clientOpenServerOpen(var state):
      state.framer.append(message)
      if endStream {
        self.state = .clientClosedServerOpen(.init(previousState: state))
      } else {
        self.state = .clientOpenServerOpen(state)
      }
    case .clientOpenServerClosed(let state):
      // The server has closed, so it makes no sense to send the rest of the request.
      // However, do close if endStream is set.
      if endStream {
        self.state = .clientClosedServerClosed(.init(previousState: state))
      }
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Client is closed, cannot send a message."
      )
    }
  }
  
  /// Returns the client's next request to the server.
  /// - Returns: The request to be made to the server.
  private mutating func clientNextOutboundMessage() throws -> OnNextOutboundMessage {
    switch self.state {
    case .clientIdleServerIdle:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError("Client is not open yet.")
    case .clientOpenServerIdle(var state):
      let request = try state.framer.next(compressor: state.compressor)
      self.state = .clientOpenServerIdle(state)
      return request != nil ? .sendMessage(request!) : .awaitMoreMessages
    case .clientOpenServerOpen(var state):
      let request = try state.framer.next(compressor: state.compressor)
      self.state = .clientOpenServerOpen(state)
      return request != nil ? .sendMessage(request!) : .awaitMoreMessages
    case .clientClosedServerIdle(var state):
      let request = try state.framer.next(compressor: state.compressor)
      self.state = .clientClosedServerIdle(state)
      if let request {
        return .sendMessage(request)
      } else {
        // If the client is closed and there is no message to be sent, then we
        // are done sending messages, as we cannot call send(message:) anymore.
        // There are no more messages to be sent, so we can end the compressor.
        state.compressor?.end()
        return .noMoreMessages
      }
    case .clientClosedServerOpen(var state):
      let request = try state.framer.next(compressor: state.compressor)
      self.state = .clientClosedServerOpen(state)
      if let request {
        return .sendMessage(request)
      } else {
        // If the client is closed and there is no message to be sent, then we
        // are done sending messages, as we cannot call send(message:) anymore.
        // There are no more messages to be sent, so we can end the compressor.
        state.compressor?.end()
        return .noMoreMessages
      }
    case .clientOpenServerClosed(let state):
      // No point in sending any more requests if the server is closed:
      // we end the compressor.
      state.compressor?.end()
      return .noMoreMessages
    case .clientClosedServerClosed(let state):
      // No point in sending any more requests if the server is closed:
      // we end the compressor.
      state.compressor?.end()
      return .noMoreMessages
    }
  }

  private mutating func clientReceive(
    metadata: HPACKHeaders,
    endStream: Bool
  ) throws -> OnMetadataReceived {
    switch self.state {
    case .clientOpenServerIdle(let state):
      guard metadata.grpcStatus != nil || metadata.status == "200" else {
        let httpStatusCode = metadata.status
          .flatMap { Int($0) }
          .map { HTTPResponseStatus(statusCode: $0) }

        guard let httpStatusCode else {
          return .failedRequest(
            .init(code: .unknown, message: "Unexpected non-200 HTTP Status Code.")
          )
        }

        if (100 ... 199).contains(httpStatusCode.code) {
          // For 1xx status codes, the entire header should be skipped and a
          // subsequent header should be read.
          // See https://github.com/grpc/grpc/blob/master/doc/http-grpc-status-mapping.md
          return .doNothing
        }

        // Close the client and forward the mapped status code.
        self.state = .clientClosedServerIdle(.init(previousState: state))
        return .failedRequest(
          .init(
            code: Status.Code(httpStatusCode: httpStatusCode),
            message: "Unexpected non-200 HTTP Status Code."
          )
        )
      }

      let contentTypeHeader = metadata.first(name: GRPCHTTP2Keys.contentType.rawValue)
      guard contentTypeHeader.flatMap(ContentType.init) != nil else {
        return .failedRequest(
          .init(code: .internalError, message: "Missing \(GRPCHTTP2Keys.contentType) header")
        )
      }

      if endStream {
        // This is a trailers-only response: close server.
        self.state = .clientOpenServerClosed(.init(previousState: state))
      } else {
        var inboundEncoding: CompressionAlgorithm?
        if let serverEncoding = metadata.first(name: GRPCHTTP2Keys.encoding.rawValue) {
          guard let parsedEncoding = CompressionAlgorithm(rawValue: serverEncoding) else {
            return .failedRequest(
              .init(
                code: .internalError,
                message: "The server picked a compression algorithm the client does not know about."
              )
            )
          }
          inboundEncoding = parsedEncoding
        }

        self.state = .clientOpenServerOpen(
          .init(
            previousState: state,
            decompressionAlgorithm: inboundEncoding
          )
        )
      }
      return .receivedMetadata(Metadata(headers: metadata))
    case .clientOpenServerOpen(let state):
      if endStream {
        self.state = .clientOpenServerClosed(.init(previousState: state))
      } else {
        // This state is valid: server can send trailing metadata without grpc-status
        // or END_STREAM set, and follow it with an empty message frame where they are set.
        ()
        // TODO: I believe we should set some flag in the state to signal that
        // we're expecting an empty data frame with END_STREAM set; otherwise,
        // we could get an infinite number of metadata frames from the server -
        // not sure this should be allowed.
      }
      return .receivedMetadata(Metadata(headers: metadata))
    case .clientClosedServerIdle(let state):
      guard metadata.grpcStatus != nil || metadata.status == "200" else {
        let httpStatusCode = metadata.status
          .flatMap { Int($0) }
          .map { HTTPResponseStatus(statusCode: $0) }

        guard let httpStatusCode else {
          return .failedRequest(
            .init(code: .unknown, message: "Unexpected non-200 HTTP Status Code.")
          )
        }

        if (100 ... 199).contains(httpStatusCode.code) {
          // For 1xx status codes, the entire header should be skipped and a
          // subsequent header should be read.
          // See https://github.com/grpc/grpc/blob/master/doc/http-grpc-status-mapping.md
          return .doNothing
        }

        // Forward the mapped status code.
        return .failedRequest(
          .init(
            code: Status.Code(httpStatusCode: httpStatusCode),
            message: "Unexpected non-200 HTTP Status Code."
          )
        )
      }

      let contentTypeHeader = metadata.first(name: GRPCHTTP2Keys.contentType.rawValue)
      guard contentTypeHeader.flatMap(ContentType.init) != nil else {
        return .failedRequest(
          .init(code: .internalError, message: "Missing \(GRPCHTTP2Keys.contentType) header")
        )
      }

      if endStream {
        // This is a trailers-only response.
        self.state = .clientClosedServerClosed(.init(previousState: state))
      } else {
        var inboundEncoding: CompressionAlgorithm?
        if let serverEncoding = metadata.first(name: GRPCHTTP2Keys.encoding.rawValue) {
          guard let parsedEncoding = CompressionAlgorithm(rawValue: serverEncoding) else {
            return .failedRequest(
              .init(
                code: .internalError,
                message: "The server picked a compression algorithm the client does not know about."
              )
            )
          }
          inboundEncoding = parsedEncoding
        }

        self.state = .clientClosedServerOpen(
          .init(
            previousState: state,
            decompressionAlgorithm: inboundEncoding
          )
        )
      }
      return .receivedMetadata(Metadata(headers: metadata))
    case .clientClosedServerOpen(let state):
      if endStream {
        self.state = .clientClosedServerClosed(.init(previousState: state))
      } else {
        // This state is valid: server can send trailing metadata without grpc-status
        // or END_STREAM set, and follow it with an empty message frame where they are set.
        ()
        // TODO: I believe we should set some flag in the state to signal that
        // we're expecting an empty data frame with END_STREAM set; otherwise,
        // we could get an infinite number of metadata frames from the server -
        // not sure this should be allowed.
      }
      return .receivedMetadata(Metadata(headers: metadata))
    case .clientClosedServerClosed:
      // We could end up here if we received a grpc-status header in a previous
      // frame (which would have already close the server) and then we receive
      // an empty frame with EOS set.
      // We wouldn't want to throw in that scenario, so we just ignore it.
      // Note that we don't want to ignore it if EOS is not set here though, as
      // then it would be an invalid payload.
      if !endStream || metadata.count > 0 {
        throw self.assertionFailureAndCreateRPCErrorOnInternalError(
          "Server is closed, nothing could have been sent."
        )
      }
      return .receivedMetadata([])
    case .clientIdleServerIdle:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Server cannot have sent metadata if the client is idle."
      )
    case .clientOpenServerClosed:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Server is closed, nothing could have been sent."
      )
    }
  }

  private mutating func clientReceive(bytes: ByteBuffer, endStream: Bool) throws {
    // This is a message received by the client, from the server.
    switch self.state {
    case .clientIdleServerIdle:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Cannot have received anything from server if client is not yet open."
      )
    case .clientOpenServerIdle, .clientClosedServerIdle:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Server cannot have sent a message before sending the initial metadata."
      )
    case .clientOpenServerOpen(var state):
      try state.deframer.process(buffer: bytes) { deframedMessage in
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
      try state.deframer.process(buffer: bytes) { deframedMessage in
        state.inboundMessageBuffer.append(deframedMessage)
      }
      if endStream {
        self.state = .clientClosedServerClosed(.init(previousState: state))
      } else {
        self.state = .clientClosedServerOpen(state)
      }
    case .clientOpenServerClosed, .clientClosedServerClosed:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Cannot have received anything from a closed server."
      )
    }
  }

  private mutating func clientNextInboundMessage() -> [UInt8]? {
    switch self.state {
    case .clientOpenServerOpen(var state):
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerOpen(state)
      return message
    case .clientOpenServerClosed(var state):
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerClosed(state)
      return message
    case .clientClosedServerOpen(var state):
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerOpen(state)
      return message
    case .clientClosedServerClosed(var state):
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerClosed(state)
      return message
    case .clientIdleServerIdle,
      .clientOpenServerIdle,
      .clientClosedServerIdle:
      return nil
    }
  }

  private func assertionFailureAndCreateRPCErrorOnInternalError(
    _ message: String,
    line: UInt = #line
  ) -> RPCError {
    if !self.skipAssertions {
      assertionFailure(message, line: line)
    }
    return RPCError(code: .internalError, message: message)
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

    headers.status = "200"
    headers.contentType = .protobuf

    if let outboundEncoding {
      headers.encoding = outboundEncoding
    }

    if !configuration.acceptedEncodings.isEmpty {
      headers.acceptedEncodings = configuration.acceptedEncodings
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
      self.state = .clientOpenServerOpen(.init(previousState: state))
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
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Client cannot be idle if server is sending initial metadata: it must have opened."
      )
    case .clientOpenServerClosed, .clientClosedServerClosed:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Server cannot send metadata if closed."
      )
    case .clientOpenServerOpen, .clientClosedServerOpen:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Server has already sent initial metadata."
      )
    }
  }

  private mutating func serverSend(message: [UInt8], endStream: Bool) throws {
    switch self.state {
    case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Server must have sent initial metadata before sending a message."
      )
    case .clientOpenServerOpen(var state):
      state.framer.append(message)
      if endStream {
        self.state = .clientOpenServerClosed(.init(previousState: state))
      } else {
        self.state = .clientOpenServerOpen(state)
      }
    case .clientClosedServerOpen(var state):
      state.framer.append(message)
      if endStream {
        self.state = .clientClosedServerClosed(.init(previousState: state))
      } else {
        self.state = .clientClosedServerOpen(state)
      }
    case .clientOpenServerClosed, .clientClosedServerClosed:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Server can't send a message if it's closed."
      )
    }
  }

  private func makeTrailers(
    status: Status,
    customMetadata: Metadata,
    trailersOnly: Bool
  ) -> HPACKHeaders {
    // Trailers always contain the grpc-status header, and optionally,
    // grpc-status-message, and custom metadata.
    // If it's a trailers-only response, they will also contain :status and
    // content-type.
    var headers = HPACKHeaders()

    if trailersOnly {
      // Reserve 4 for capacity: 3 for the required headers, and 1 for the
      // optional status message.
      headers.reserveCapacity(4 + customMetadata.count)
      headers.status = "200"
      headers.contentType = .protobuf
    } else {
      // Reserve 2 for capacity: one for the required grpc-status, and
      // one for the optional message.
      headers.reserveCapacity(2 + customMetadata.count)
    }

    headers.grpcStatus = status.code

    if !status.message.isEmpty {
      // TODO: this message has to be percent-encoded
      headers.grpcStatusMessage = status.message
    }

    for metadataPair in customMetadata {
      headers.add(name: metadataPair.key, value: metadataPair.value.encoded())
    }

    return headers
  }

  private mutating func serverSend(
    status: Status,
    metadata: Metadata,
    trailersOnly: Bool
  ) throws -> HPACKHeaders {
    // Close the server.
    switch self.state {
    case .clientOpenServerOpen(let state):
      self.state = .clientOpenServerClosed(.init(previousState: state))
      return self.makeTrailers(status: status, customMetadata: metadata, trailersOnly: trailersOnly)
    case .clientClosedServerOpen(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return self.makeTrailers(status: status, customMetadata: metadata, trailersOnly: trailersOnly)
    case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Server can't send status if idle."
      )
    case .clientOpenServerClosed, .clientClosedServerClosed:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Server can't send anything if closed."
      )
    }
  }

  private mutating func serverReceive(
    metadata: HPACKHeaders,
    endStream: Bool,
    configuration: GRPCStreamStateMachineConfiguration.ServerConfiguration
  ) throws -> OnMetadataReceived {
    switch self.state {
    case .clientIdleServerIdle(let state):
      if endStream {
        throw self.assertionFailureAndCreateRPCErrorOnInternalError(
          """
          Client should have opened before ending the stream: \
          stream shouldn't have been closed when sending initial metadata.
          """
        )
      }

      guard metadata.contentType != nil else {
        // Respond with HTTP-level Unsupported Media Type status code.
        var trailers = HPACKHeaders()
        trailers.status = "415"
        return .rejectRPC(trailers: trailers)
      }

      guard metadata.path != nil else {
        var trailers = HPACKHeaders()
        trailers.reserveCapacity(2)
        trailers.grpcStatus = .unimplemented
        trailers.grpcStatusMessage = "No \(GRPCHTTP2Keys.path.rawValue) header has been set."
        return .rejectRPC(trailers: trailers)
      }

      func isIdentityOrCompatibleEncoding(_ clientEncoding: CompressionAlgorithm) -> Bool {
        clientEncoding == .identity || configuration.acceptedEncodings.contains(clientEncoding)
      }

      // Firstly, find out if we support the client's chosen encoding, and reject
      // the RPC if we don't.
      var inboundEncoding: CompressionAlgorithm? = nil
      let encodingValues = metadata.values(
        forHeader: GRPCHTTP2Keys.encoding.rawValue,
        canonicalForm: true
      )
      var encodingValuesIterator = encodingValues.makeIterator()
      if let rawEncoding = encodingValuesIterator.next() {
        guard encodingValuesIterator.next() == nil else {
          var trailers = HPACKHeaders()
          trailers.reserveCapacity(2)
          trailers.grpcStatus = .internalError
          trailers.grpcStatusMessage =
            "\(GRPCHTTP2Keys.encoding) must contain no more than one value."
          return .rejectRPC(trailers: trailers)
        }

        guard let clientEncoding = CompressionAlgorithm(rawValue: String(rawEncoding)),
          isIdentityOrCompatibleEncoding(clientEncoding)
        else {
          if configuration.acceptedEncodings.isEmpty {
            var trailers = HPACKHeaders()
            trailers.reserveCapacity(2)
            trailers.grpcStatus = .unimplemented
            trailers.grpcStatusMessage = "Compression is not supported"
            return .rejectRPC(trailers: trailers)
          } else {
            var trailers = HPACKHeaders()
            trailers.reserveCapacity(3)
            trailers.grpcStatus = .unimplemented
            trailers.grpcStatusMessage = """
              \(rawEncoding) compression is not supported; \
              supported algorithms are listed in grpc-accept-encoding
              """
            trailers.acceptedEncodings = configuration.acceptedEncodings
            return .rejectRPC(trailers: trailers)
          }
        }

        // Server supports client's encoding.
        // If it's identity, just skip it altogether.
        if clientEncoding != .identity {
          inboundEncoding = clientEncoding
        }
      }

      // Secondly, find a compatible encoding the server can use to compress outbound messages,
      // based on the encodings the client has advertised.
      var outboundEncoding: CompressionAlgorithm? = nil
      if let clientAdvertisedEncodings = metadata.acceptedEncodings {
        // Find the preferred encoding and use it to compress responses.
        // If it's identity, just skip it altogether, since we won't be
        // compressing.
        outboundEncoding =
          clientAdvertisedEncodings
          .first { isIdentityOrCompatibleEncoding($0) }
          .flatMap { $0 == .identity ? nil : $0 }
      }

      self.state = .clientOpenServerIdle(
        .init(
          previousState: state,
          compressionAlgorithm: outboundEncoding,
          decompressionConfiguration: .decompression(inboundEncoding)
        )
      )

      return .receivedMetadata(Metadata(headers: metadata))
    case .clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Client shouldn't have sent metadata twice."
      )
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Client can't have sent metadata if closed."
      )
    }
  }

  private mutating func serverReceive(bytes: ByteBuffer, endStream: Bool) throws {
    switch self.state {
    case .clientIdleServerIdle:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Can't have received a message if client is idle."
      )
    case .clientOpenServerIdle(var state):
      // Deframer must be present on the server side, as we know the decompression
      // algorithm from the moment the client opens.
      assert(state.deframer != nil)
      try state.deframer!.process(buffer: bytes) { deframedMessage in
        state.inboundMessageBuffer.append(deframedMessage)
      }

      if endStream {
        self.state = .clientClosedServerIdle(.init(previousState: state))
      } else {
        self.state = .clientOpenServerIdle(state)
      }
    case .clientOpenServerOpen(var state):
      try state.deframer.process(buffer: bytes) { deframedMessage in
        state.inboundMessageBuffer.append(deframedMessage)
      }

      if endStream {
        self.state = .clientClosedServerOpen(.init(previousState: state))
      } else {
        self.state = .clientOpenServerOpen(state)
      }
    case .clientOpenServerClosed:
      // Client is not done sending request, but server has already closed.
      // Ignore the rest of the request: do nothing.
      ()
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError(
        "Client can't send a message if closed."
      )
    }
  }

  private mutating func serverNextOutboundMessage() throws -> OnNextOutboundMessage {
    switch self.state {
    case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
      throw self.assertionFailureAndCreateRPCErrorOnInternalError("Server is not open yet.")
    case .clientOpenServerOpen(var state):
      let response = try state.framer.next(compressor: state.compressor)
      self.state = .clientOpenServerOpen(state)
      return response != nil ? .sendMessage(response!) : .awaitMoreMessages
    case .clientClosedServerOpen(var state):
      let response = try state.framer.next(compressor: state.compressor)
      self.state = .clientClosedServerOpen(state)
      return response != nil ? .sendMessage(response!) : .awaitMoreMessages
    case .clientOpenServerClosed(var state):
      let response = try state.framer.next(compressor: state.compressor)
      self.state = .clientOpenServerClosed(state)
      if let response {
        return .sendMessage(response)
      } else {
        // There are no more messages to be sent, so we can end the compressor.
        state.compressor?.end()
        return .noMoreMessages
      }
    case .clientClosedServerClosed(var state):
      let response = try state.framer.next(compressor: state.compressor)
      self.state = .clientClosedServerClosed(state)
      if let response {
        return .sendMessage(response)
      } else {
        // There are no more messages to be sent, so we can end the compressor.
        state.compressor?.end()
        return .noMoreMessages
      }
    }
  }

  private mutating func serverNextInboundMessage() -> [UInt8]? {
    switch self.state {
    case .clientOpenServerIdle(var state):
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerIdle(state)
      return request
    case .clientOpenServerOpen(var state):
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerOpen(state)
      return request
    case .clientOpenServerClosed(var state):
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerClosed(state)
      return request
    case .clientClosedServerOpen(var state):
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerOpen(state)
      return request
    case .clientClosedServerClosed(var state):
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerClosed(state)
      return request
    case .clientClosedServerIdle, .clientIdleServerIdle:
      return nil
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
  var path: MethodDescriptor? {
    get {
      self.firstString(forKey: .path)
        .flatMap { MethodDescriptor(fullyQualifiedMethod: $0) }
    }
    set {
      if let newValue {
        self.add(newValue.fullyQualifiedMethod, forKey: .path)
      } else {
        self.removeAllValues(forKey: .path)
      }
    }
  }

  var contentType: ContentType? {
    get {
      self.firstString(forKey: .contentType)
        .flatMap { ContentType(value: $0) }
    }
    set {
      if let newValue {
        self.add(newValue.canonicalValue, forKey: .contentType)
      } else {
        self.removeAllValues(forKey: .contentType)
      }
    }
  }

  var encoding: CompressionAlgorithm? {
    get {
      self.firstString(forKey: .encoding)
        .flatMap { CompressionAlgorithm(rawValue: $0) }
    }
    set {
      if let newValue {
        self.add(newValue.name, forKey: .encoding)
      } else {
        self.removeAllValues(forKey: .encoding)
      }
    }
  }

  var acceptedEncodings: [CompressionAlgorithm]? {
    get {
      self.values(forHeader: GRPCHTTP2Keys.acceptEncoding.rawValue, canonicalForm: true)
        .compactMap { CompressionAlgorithm(rawValue: String($0)) }
    }
    set {
      if let newValue {
        for value in newValue {
          self.add(value.name, forKey: .acceptEncoding)
        }
      } else {
        self.removeAllValues(forKey: .acceptEncoding)
      }
    }
  }

  var scheme: Scheme? {
    get {
      self.firstString(forKey: .scheme).flatMap { Scheme(rawValue: $0) }
    }
    set {
      if let newValue {
        self.add(newValue.rawValue, forKey: .scheme)
      } else {
        self.removeAllValues(forKey: .scheme)
      }
    }
  }

  var method: String? {
    get {
      self.firstString(forKey: .method)
    }
    set {
      if let newValue {
        self.add(newValue, forKey: .method)
      } else {
        self.removeAllValues(forKey: .method)
      }
    }
  }

  var te: String? {
    get {
      self.firstString(forKey: .te)
    }
    set {
      if let newValue {
        self.add(newValue, forKey: .te)
      } else {
        self.removeAllValues(forKey: .te)
      }
    }
  }

  var status: String? {
    get {
      self.firstString(forKey: .status)
    }
    set {
      if let newValue {
        self.add(newValue, forKey: .status)
      } else {
        self.removeAllValues(forKey: .status)
      }
    }
  }

  var grpcStatus: Status.Code? {
    get {
      self.firstString(forKey: .grpcStatus)
        .flatMap { Int($0) }
        .flatMap { Status.Code(rawValue: $0) }
    }
    set {
      if let newValue {
        self.add(String(newValue.rawValue), forKey: .grpcStatus)
      } else {
        self.removeAllValues(forKey: .grpcStatus)
      }
    }
  }

  var grpcStatusMessage: String? {
    get {
      self.firstString(forKey: .grpcStatusMessage)
    }
    set {
      if let newValue {
        self.add(newValue, forKey: .grpcStatusMessage)
      } else {
        self.removeAllValues(forKey: .grpcStatusMessage)
      }
    }
  }

  private func firstString(forKey key: GRPCHTTP2Keys) -> String? {
    self.values(forHeader: key.rawValue, canonicalForm: true).first(where: { _ in true }).map {
      String($0)
    }
  }

  private mutating func add(_ value: String, forKey key: GRPCHTTP2Keys) {
    self.add(name: key.rawValue, value: value)
  }

  private mutating func removeAllValues(forKey key: GRPCHTTP2Keys) {
    self.remove(name: key.rawValue)
  }
}

extension Zlib.Method {
  init?(encoding: CompressionAlgorithm?) {
    guard let encoding else {
      return nil
    }

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
