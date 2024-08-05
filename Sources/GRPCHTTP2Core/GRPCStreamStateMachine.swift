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

internal import GRPCCore
internal import NIOCore
internal import NIOHPACK
internal import NIOHTTP1

package enum Scheme: String {
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
    var acceptedEncodings: CompressionAlgorithmSet

    init(
      methodDescriptor: MethodDescriptor,
      scheme: Scheme,
      outboundEncoding: CompressionAlgorithm,
      acceptedEncodings: CompressionAlgorithmSet
    ) {
      self.methodDescriptor = methodDescriptor
      self.scheme = scheme
      self.outboundEncoding = outboundEncoding
      self.acceptedEncodings = acceptedEncodings.union(.none)
    }
  }

  struct ServerConfiguration {
    var scheme: Scheme
    var acceptedEncodings: CompressionAlgorithmSet

    init(scheme: Scheme, acceptedEncodings: CompressionAlgorithmSet) {
      self.scheme = scheme
      self.acceptedEncodings = acceptedEncodings.union(.none)
    }
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
  case _modifying

  struct ClientIdleServerIdleState {
    let maximumPayloadSize: Int
  }

  struct ClientOpenServerIdleState {
    let maximumPayloadSize: Int
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    var outboundCompression: CompressionAlgorithm

    // The deframer must be optional because the client will not have one configured
    // until the server opens and sends a grpc-encoding header.
    // It will be present for the server though, because even though it's idle,
    // it can still receive compressed messages from the client.
    var deframer: GRPCMessageDeframer?
    var decompressor: Zlib.Decompressor?

    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    // Store the headers received from the remote peer, its storage can be reused when sending
    // headers back to the remote peer.
    var headers: HPACKHeaders

    init(
      previousState: ClientIdleServerIdleState,
      compressor: Zlib.Compressor?,
      outboundCompression: CompressionAlgorithm,
      framer: GRPCMessageFramer,
      decompressor: Zlib.Decompressor?,
      deframer: GRPCMessageDeframer?,
      headers: HPACKHeaders
    ) {
      self.maximumPayloadSize = previousState.maximumPayloadSize
      self.compressor = compressor
      self.outboundCompression = outboundCompression
      self.framer = framer
      self.decompressor = decompressor
      self.deframer = deframer
      self.inboundMessageBuffer = .init()
      self.headers = headers
    }
  }

  struct ClientOpenServerOpenState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    var outboundCompression: CompressionAlgorithm

    var deframer: GRPCMessageDeframer
    var decompressor: Zlib.Decompressor?

    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    // Store the headers received from the remote peer, its storage can be reused when sending
    // headers back to the remote peer.
    var headers: HPACKHeaders

    init(
      previousState: ClientOpenServerIdleState,
      deframer: GRPCMessageDeframer,
      decompressor: Zlib.Decompressor?
    ) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression

      self.deframer = deframer
      self.decompressor = decompressor

      self.inboundMessageBuffer = previousState.inboundMessageBuffer
      self.headers = previousState.headers
    }
  }

  struct ClientOpenServerClosedState {
    var framer: GRPCMessageFramer?
    var compressor: Zlib.Compressor?
    var outboundCompression: CompressionAlgorithm

    let deframer: GRPCMessageDeframer?
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
      self.outboundCompression = .none
      self.deframer = nil
      self.decompressor = nil
      self.inboundMessageBuffer = .init()
    }

    init(previousState: ClientOpenServerOpenState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    init(previousState: ClientOpenServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression
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
    var outboundCompression: CompressionAlgorithm

    let deframer: GRPCMessageDeframer?
    var decompressor: Zlib.Decompressor?

    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    // Store the headers received from the remote peer, its storage can be reused when sending
    // headers back to the remote peer.
    var headers: HPACKHeaders

    /// This transition should only happen on the client-side.
    /// It can happen if the request times out before the client outbound can be opened, or if the stream is
    /// unexpectedly closed for some other reason on the client before it can transition to open.
    init(previousState: ClientIdleServerIdleState) {
      self.maximumPayloadSize = previousState.maximumPayloadSize
      // We don't need a compressor since we won't be sending any messages.
      self.framer = GRPCMessageFramer()
      self.compressor = nil
      self.outboundCompression = .none

      // We haven't received anything from the server.
      self.deframer = nil
      self.decompressor = nil

      self.inboundMessageBuffer = .init()
      self.headers = [:]
    }

    /// This transition should only happen on the server-side.
    /// We are closing the client as soon as it opens (i.e., endStream was set when receiving the client's
    /// initial metadata). We don't need to know a decompression algorithm, since we won't receive
    /// any more messages from the client anyways, as it's closed.
    init(
      previousState: ClientIdleServerIdleState,
      compressionAlgorithm: CompressionAlgorithm,
      headers: HPACKHeaders
    ) {
      self.maximumPayloadSize = previousState.maximumPayloadSize

      if let zlibMethod = Zlib.Method(encoding: compressionAlgorithm) {
        self.compressor = Zlib.Compressor(method: zlibMethod)
        self.outboundCompression = compressionAlgorithm
      } else {
        self.compressor = nil
        self.outboundCompression = .none
      }
      self.framer = GRPCMessageFramer()
      // We don't need a deframer since we won't receive any messages from the
      // client: it's closed.
      self.deframer = nil
      self.inboundMessageBuffer = .init()
      self.headers = headers
    }

    init(previousState: ClientOpenServerIdleState) {
      self.maximumPayloadSize = previousState.maximumPayloadSize
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
      self.headers = previousState.headers
    }
  }

  struct ClientClosedServerOpenState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    var outboundCompression: CompressionAlgorithm

    var deframer: GRPCMessageDeframer?
    var decompressor: Zlib.Decompressor?

    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>

    // Store the headers received from the remote peer, its storage can be reused when sending
    // headers back to the remote peer.
    var headers: HPACKHeaders

    init(previousState: ClientOpenServerOpenState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
      self.headers = previousState.headers
    }

    /// This should be called from the server path, as the deframer will already be configured in this scenario.
    init(previousState: ClientClosedServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression

      // In the case of the server, we don't need to deframe/decompress any more
      // messages, since the client's closed.
      self.deframer = nil
      self.decompressor = nil

      self.inboundMessageBuffer = previousState.inboundMessageBuffer
      self.headers = previousState.headers
    }

    /// This should only be called from the client path, as the deframer has not yet been set up.
    init(
      previousState: ClientClosedServerIdleState,
      decompressionAlgorithm: CompressionAlgorithm
    ) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression

      // In the case of the client, it will only be able to set up the deframer
      // after it receives the chosen encoding from the server.
      if let zlibMethod = Zlib.Method(encoding: decompressionAlgorithm) {
        self.decompressor = Zlib.Decompressor(method: zlibMethod)
      }

      self.deframer = GRPCMessageDeframer(
        maxPayloadSize: previousState.maximumPayloadSize,
        decompressor: self.decompressor
      )

      self.inboundMessageBuffer = previousState.inboundMessageBuffer
      self.headers = previousState.headers
    }
  }

  struct ClientClosedServerClosedState {
    // We still need the framer and compressor in case the server has closed
    // but its buffer is not yet empty and still needs to send messages out to
    // the client.
    var framer: GRPCMessageFramer?
    var compressor: Zlib.Compressor?
    var outboundCompression: CompressionAlgorithm

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
      self.outboundCompression = .none
      self.inboundMessageBuffer = .init()
    }

    init(previousState: ClientClosedServerOpenState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    init(previousState: ClientClosedServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    init(previousState: ClientOpenServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    init(previousState: ClientOpenServerOpenState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }

    init(previousState: ClientOpenServerClosedState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.outboundCompression = previousState.outboundCompression
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct GRPCStreamStateMachine {
  private var state: GRPCStreamStateMachineState
  private var configuration: GRPCStreamStateMachineConfiguration
  private var skipAssertions: Bool

  struct InvalidState: Error {
    var message: String
    init(_ message: String) {
      self.message = message
    }
  }

  init(
    configuration: GRPCStreamStateMachineConfiguration,
    maximumPayloadSize: Int,
    skipAssertions: Bool = false
  ) {
    self.state = .clientIdleServerIdle(.init(maximumPayloadSize: maximumPayloadSize))
    self.configuration = configuration
    self.skipAssertions = skipAssertions
  }

  mutating func send(metadata: Metadata) throws(InvalidState) -> HPACKHeaders {
    switch self.configuration {
    case .client(let clientConfiguration):
      return try self.clientSend(metadata: metadata, configuration: clientConfiguration)
    case .server(let serverConfiguration):
      return try self.serverSend(metadata: metadata, configuration: serverConfiguration)
    }
  }

  mutating func send(message: [UInt8], promise: EventLoopPromise<Void>?) throws(InvalidState) {
    switch self.configuration {
    case .client:
      try self.clientSend(message: message, promise: promise)
    case .server:
      try self.serverSend(message: message, promise: promise)
    }
  }

  mutating func closeOutbound() throws(InvalidState) {
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
  ) throws(InvalidState) -> HPACKHeaders {
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
    case receivedMetadata(Metadata, MethodDescriptor?)
    case doNothing

    // Client-specific actions
    case receivedStatusAndMetadata_clientOnly(status: Status, metadata: Metadata)

    // Server-specific actions
    case rejectRPC_serverOnly(trailers: HPACKHeaders)
    case protocolViolation_serverOnly
  }

  mutating func receive(
    headers: HPACKHeaders,
    endStream: Bool
  ) throws(InvalidState) -> OnMetadataReceived {
    switch self.configuration {
    case .client(let clientConfiguration):
      return try self.clientReceive(
        headers: headers,
        endStream: endStream,
        configuration: clientConfiguration
      )
    case .server(let serverConfiguration):
      return try self.serverReceive(
        headers: headers,
        endStream: endStream,
        configuration: serverConfiguration
      )
    }
  }

  enum OnBufferReceivedAction: Equatable {
    case readInbound
    case doNothing

    // This will be returned when the server sends a data frame with EOS set.
    // This is invalid as per the protocol specification, because the server
    // can only close by sending trailers, not by setting EOS when sending
    // a message.
    case endRPCAndForwardErrorStatus_clientOnly(Status)

    case forwardErrorAndClose_serverOnly(RPCError)
  }

  mutating func receive(
    buffer: ByteBuffer,
    endStream: Bool
  ) throws(InvalidState) -> OnBufferReceivedAction {
    switch self.configuration {
    case .client:
      return try self.clientReceive(buffer: buffer, endStream: endStream)
    case .server:
      return try self.serverReceive(buffer: buffer, endStream: endStream)
    }
  }

  /// The result of requesting the next outbound frame, which may contain multiple messages.
  enum OnNextOutboundFrame {
    /// Either the receiving party is closed, so we shouldn't send any more frames; or the sender is done
    /// writing messages (i.e. we are now closed).
    case noMoreMessages
    /// There isn't a frame ready to be sent, but we could still receive more messages, so keep trying.
    case awaitMoreMessages
    /// A frame is ready to be sent.
    case sendFrame(
      frame: ByteBuffer,
      promise: EventLoopPromise<Void>?
    )
    case closeAndFailPromise(EventLoopPromise<Void>?, RPCError)

    init(result: Result<ByteBuffer, RPCError>, promise: EventLoopPromise<Void>?) {
      switch result {
      case .success(let buffer):
        self = .sendFrame(frame: buffer, promise: promise)
      case .failure(let error):
        self = .closeAndFailPromise(promise, error)
      }
    }
  }

  mutating func nextOutboundFrame() throws(InvalidState) -> OnNextOutboundFrame {
    switch self.configuration {
    case .client:
      return try self.clientNextOutboundFrame()
    case .server:
      return try self.serverNextOutboundFrame()
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
    case ._modifying:
      preconditionFailure()
    }
  }

  enum OnUnexpectedInboundClose {
    case forwardStatus_clientOnly(Status)
    case fireError_serverOnly(any Error)
    case doNothing

    init(serverCloseReason: UnexpectedInboundCloseReason) {
      switch serverCloseReason {
      case .streamReset, .channelInactive:
        self = .fireError_serverOnly(RPCError(serverCloseReason))
      case .errorThrown(let error):
        self = .fireError_serverOnly(error)
      }
    }
  }

  enum UnexpectedInboundCloseReason {
    case streamReset
    case channelInactive
    case errorThrown(any Error)
  }

  mutating func unexpectedInboundClose(
    reason: UnexpectedInboundCloseReason
  ) -> OnUnexpectedInboundClose {
    switch self.configuration {
    case .client:
      return self.clientUnexpectedInboundClose(reason: reason)
    case .server:
      return self.serverUnexpectedInboundClose(reason: reason)
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
    acceptedEncodings: CompressionAlgorithmSet,
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
    headers.add(methodDescriptor.path, forKey: .path)

    // Add required gRPC headers.
    headers.add(ContentType.grpc.canonicalValue, forKey: .contentType)
    headers.add("trailers", forKey: .te)  // Used to detect incompatible proxies

    if let encoding = outboundEncoding, encoding != .none {
      headers.add(encoding.name, forKey: .encoding)
    }

    for encoding in acceptedEncodings.elements.filter({ $0 != .none }) {
      headers.add(encoding.name, forKey: .acceptEncoding)
    }

    for metadataPair in customMetadata {
      headers.add(name: metadataPair.key, value: metadataPair.value.encoded())
    }

    return headers
  }

  private mutating func clientSend(
    metadata: Metadata,
    configuration: GRPCStreamStateMachineConfiguration.ClientConfiguration
  ) throws(InvalidState) -> HPACKHeaders {
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
          outboundCompression: outboundEncoding,
          framer: GRPCMessageFramer(),
          decompressor: nil,
          deframer: nil,
          headers: [:]
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
    case ._modifying:
      preconditionFailure()
    }
  }

  private mutating func clientSend(
    message: [UInt8],
    promise: EventLoopPromise<Void>?
  ) throws(InvalidState) {
    switch self.state {
    case .clientIdleServerIdle:
      try self.invalidState("Client not yet open.")

    case .clientOpenServerIdle(var state):
      self.state = ._modifying
      state.framer.append(message, promise: promise)
      self.state = .clientOpenServerIdle(state)

    case .clientOpenServerOpen(var state):
      self.state = ._modifying
      state.framer.append(message, promise: promise)
      self.state = .clientOpenServerOpen(state)

    case .clientOpenServerClosed:
      // The server has closed, so it makes no sense to send the rest of the request.
      ()

    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      try self.invalidState(
        "Client is closed, cannot send a message."
      )

    case ._modifying:
      preconditionFailure()
    }
  }

  private mutating func clientCloseOutbound() throws(InvalidState) {
    switch self.state {
    case .clientIdleServerIdle(let state):
      self.state = .clientClosedServerIdle(.init(previousState: state))
    case .clientOpenServerIdle(let state):
      self.state = .clientClosedServerIdle(.init(previousState: state))
    case .clientOpenServerOpen(let state):
      self.state = .clientClosedServerOpen(.init(previousState: state))
    case .clientOpenServerClosed(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      // Client is already closed - nothing to do.
      ()
    case ._modifying:
      preconditionFailure()
    }
  }

  /// Returns the client's next request to the server.
  /// - Returns: The request to be made to the server.
  private mutating func clientNextOutboundFrame() throws(InvalidState) -> OnNextOutboundFrame {

    switch self.state {
    case .clientIdleServerIdle:
      try self.invalidState("Client is not open yet.")

    case .clientOpenServerIdle(var state):
      self.state = ._modifying
      let next = state.framer.nextResult(compressor: state.compressor)
      self.state = .clientOpenServerIdle(state)

      if let next = next {
        return OnNextOutboundFrame(result: next.result, promise: next.promise)
      } else {
        return .awaitMoreMessages
      }

    case .clientOpenServerOpen(var state):
      self.state = ._modifying
      let next = state.framer.nextResult(compressor: state.compressor)
      self.state = .clientOpenServerOpen(state)

      if let next = next {
        return OnNextOutboundFrame(result: next.result, promise: next.promise)
      } else {
        return .awaitMoreMessages
      }

    case .clientClosedServerIdle(var state):
      self.state = ._modifying
      let next = state.framer.nextResult(compressor: state.compressor)
      self.state = .clientClosedServerIdle(state)

      if let next = next {
        return OnNextOutboundFrame(result: next.result, promise: next.promise)
      } else {
        return .noMoreMessages
      }

    case .clientClosedServerOpen(var state):
      self.state = ._modifying
      let next = state.framer.nextResult(compressor: state.compressor)
      self.state = .clientClosedServerOpen(state)

      if let next = next {
        return OnNextOutboundFrame(result: next.result, promise: next.promise)
      } else {
        return .noMoreMessages
      }

    case .clientOpenServerClosed, .clientClosedServerClosed:
      // No point in sending any more requests if the server is closed.
      return .noMoreMessages

    case ._modifying:
      preconditionFailure()
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
          .receivedStatusAndMetadata_clientOnly(
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
        .receivedStatusAndMetadata_clientOnly(
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
        .receivedStatusAndMetadata_clientOnly(
          status: .init(
            code: .internalError,
            message: "Missing \(GRPCHTTP2Keys.contentType.rawValue) header"
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

  private func processInboundEncoding(
    headers: HPACKHeaders,
    configuration: GRPCStreamStateMachineConfiguration.ClientConfiguration
  ) -> ProcessInboundEncodingResult {
    let inboundEncoding: CompressionAlgorithm
    if let serverEncoding = headers.first(name: GRPCHTTP2Keys.encoding.rawValue) {
      guard let parsedEncoding = CompressionAlgorithm(name: serverEncoding),
        configuration.acceptedEncodings.contains(parsedEncoding)
      else {
        return .error(
          .receivedStatusAndMetadata_clientOnly(
            status: .init(
              code: .internalError,
              message:
                "The server picked a compression algorithm ('\(serverEncoding)') the client does not know about."
            ),
            metadata: Metadata(headers: headers)
          )
        )
      }
      inboundEncoding = parsedEncoding
    } else {
      inboundEncoding = .none
    }
    return .success(inboundEncoding)
  }

  private func validateTrailers(
    _ trailers: HPACKHeaders
  ) throws(InvalidState) -> OnMetadataReceived {
    let statusValue = trailers.firstString(forKey: .grpcStatus)
    let statusCode = statusValue.flatMap {
      Int($0)
    }.flatMap {
      Status.Code(rawValue: $0)
    }

    let status: Status
    if let code = statusCode {
      let messageFieldValue = trailers.firstString(forKey: .grpcStatusMessage, canonicalForm: false)
      let message = messageFieldValue.map { GRPCStatusMessageMarshaller.unmarshall($0) } ?? ""
      status = Status(code: code, message: message)
    } else {
      let message: String
      if let statusValue = statusValue {
        message = "Invalid 'grpc-status' in trailers (\(statusValue))"
      } else {
        message = "No 'grpc-status' value in trailers"
      }
      status = Status(code: .unknown, message: message)
    }

    var convertedMetadata = Metadata(headers: trailers)
    convertedMetadata.removeAllValues(forKey: GRPCHTTP2Keys.grpcStatus.rawValue)
    convertedMetadata.removeAllValues(forKey: GRPCHTTP2Keys.grpcStatusMessage.rawValue)

    return .receivedStatusAndMetadata_clientOnly(status: status, metadata: convertedMetadata)
  }

  private mutating func clientReceive(
    headers: HPACKHeaders,
    endStream: Bool,
    configuration: GRPCStreamStateMachineConfiguration.ClientConfiguration
  ) throws(InvalidState) -> OnMetadataReceived {
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
        return try self.validateTrailers(headers)
      case (.valid, false):
        switch self.processInboundEncoding(headers: headers, configuration: configuration) {
        case .error(let failure):
          return failure
        case .success(let inboundEncoding):
          let decompressor = Zlib.Method(encoding: inboundEncoding)
            .flatMap { Zlib.Decompressor(method: $0) }

          self.state = .clientOpenServerOpen(
            .init(
              previousState: state,
              deframer: GRPCMessageDeframer(
                maxPayloadSize: state.maximumPayloadSize,
                decompressor: decompressor
              ),
              decompressor: decompressor
            )
          )
          return .receivedMetadata(Metadata(headers: headers), nil)
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
      return try self.validateTrailers(headers)

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
        return try self.validateTrailers(headers)
      case (.valid, false):
        switch self.processInboundEncoding(headers: headers, configuration: configuration) {
        case .error(let failure):
          return failure
        case .success(let inboundEncoding):
          self.state = .clientClosedServerOpen(
            .init(
              previousState: state,
              decompressionAlgorithm: inboundEncoding
            )
          )
          return .receivedMetadata(Metadata(headers: headers), nil)
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
      return try self.validateTrailers(headers)

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
    case ._modifying:
      preconditionFailure()
    }
  }

  private mutating func clientReceive(
    buffer: ByteBuffer,
    endStream: Bool
  ) throws(InvalidState) -> OnBufferReceivedAction {
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
      self.state = ._modifying
      if endStream {
        // This is invalid as per the protocol specification, because the server
        // can only close by sending trailers, not by setting EOS when sending
        // a message.
        self.state = .clientClosedServerClosed(.init(previousState: state))
        return .endRPCAndForwardErrorStatus_clientOnly(
          Status(
            code: .internalError,
            message: """
              Server sent EOS alongside a data frame, but server is only allowed \
              to close by sending status and trailers.
              """
          )
        )
      }

      state.deframer.append(buffer)

      do {
        try state.deframer.decode(into: &state.inboundMessageBuffer)
        self.state = .clientOpenServerOpen(state)
        return .readInbound
      } catch {
        self.state = .clientOpenServerOpen(state)
        let status = Status(code: .internalError, message: "Failed to decode message")
        return .endRPCAndForwardErrorStatus_clientOnly(status)
      }

    case .clientClosedServerOpen(var state):
      self.state = ._modifying
      if endStream {
        self.state = .clientClosedServerClosed(.init(previousState: state))
        return .endRPCAndForwardErrorStatus_clientOnly(
          Status(
            code: .internalError,
            message: """
              Server sent EOS alongside a data frame, but server is only allowed \
              to close by sending status and trailers.
              """
          )
        )
      }

      // The client may have sent the end stream and thus it's closed,
      // but the server may still be responding.
      // The client must have a deframer set up, so force-unwrap is okay.
      do {
        state.deframer!.append(buffer)
        try state.deframer!.decode(into: &state.inboundMessageBuffer)
        self.state = .clientClosedServerOpen(state)
        return .readInbound
      } catch {
        self.state = .clientClosedServerOpen(state)
        let status = Status(code: .internalError, message: "Failed to decode message")
        return .endRPCAndForwardErrorStatus_clientOnly(status)
      }

    case .clientOpenServerClosed, .clientClosedServerClosed:
      try self.invalidState(
        "Cannot have received anything from a closed server."
      )
    case ._modifying:
      preconditionFailure()
    }
  }

  private mutating func clientNextInboundMessage() -> OnNextInboundMessage {
    switch self.state {
    case .clientOpenServerOpen(var state):
      self.state = ._modifying
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerOpen(state)
      return message.map { .receiveMessage($0) } ?? .awaitMoreMessages

    case .clientOpenServerClosed(var state):
      self.state = ._modifying
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerClosed(state)
      return message.map { .receiveMessage($0) } ?? .noMoreMessages

    case .clientClosedServerOpen(var state):
      self.state = ._modifying
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerOpen(state)
      return message.map { .receiveMessage($0) } ?? .awaitMoreMessages

    case .clientClosedServerClosed(var state):
      self.state = ._modifying
      let message = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerClosed(state)
      return message.map { .receiveMessage($0) } ?? .noMoreMessages

    case .clientIdleServerIdle,
      .clientOpenServerIdle,
      .clientClosedServerIdle:
      return .awaitMoreMessages
    case ._modifying:
      preconditionFailure()
    }
  }

  private func invalidState(_ message: String, line: UInt = #line) throws(InvalidState) -> Never {
    if !self.skipAssertions {
      assertionFailure(message, line: line)
    }
    throw InvalidState(message)
  }

  private mutating func clientUnexpectedInboundClose(
    reason: UnexpectedInboundCloseReason
  ) -> OnUnexpectedInboundClose {
    switch self.state {
    case .clientIdleServerIdle(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return .forwardStatus_clientOnly(Status(RPCError(reason)))

    case .clientOpenServerIdle(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return .forwardStatus_clientOnly(Status(RPCError(reason)))

    case .clientClosedServerIdle(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return .forwardStatus_clientOnly(Status(RPCError(reason)))

    case .clientOpenServerOpen(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return .forwardStatus_clientOnly(Status(RPCError(reason)))

    case .clientClosedServerOpen(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return .forwardStatus_clientOnly(Status(RPCError(reason)))

    case .clientOpenServerClosed, .clientClosedServerClosed:
      return .doNothing

    case ._modifying:
      preconditionFailure()
    }
  }
}

// - MARK: Server

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine {
  private func formResponseHeaders(
    in headers: inout HPACKHeaders,
    outboundEncoding: CompressionAlgorithm?,
    configuration: GRPCStreamStateMachineConfiguration.ServerConfiguration,
    customMetadata: Metadata
  ) {
    headers.removeAll(keepingCapacity: true)

    // Response headers always contain :status (HTTP Status 200) and content-type.
    // They may also contain grpc-encoding, grpc-accept-encoding, and custom metadata.
    headers.reserveCapacity(4 + customMetadata.count)

    headers.add("200", forKey: .status)
    headers.add(ContentType.grpc.canonicalValue, forKey: .contentType)

    if let outboundEncoding, outboundEncoding != .none {
      headers.add(outboundEncoding.name, forKey: .encoding)
    }

    for metadataPair in customMetadata {
      headers.add(name: metadataPair.key, value: metadataPair.value.encoded())
    }
  }

  private mutating func serverSend(
    metadata: Metadata,
    configuration: GRPCStreamStateMachineConfiguration.ServerConfiguration
  ) throws(InvalidState) -> HPACKHeaders {
    // Server sends initial metadata
    switch self.state {
    case .clientOpenServerIdle(var state):
      self.state = ._modifying
      let outboundEncoding = state.outboundCompression
      self.formResponseHeaders(
        in: &state.headers,
        outboundEncoding: outboundEncoding,
        configuration: configuration,
        customMetadata: metadata
      )

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

      return state.headers

    case .clientClosedServerIdle(var state):
      self.state = ._modifying
      let outboundEncoding = state.outboundCompression
      self.formResponseHeaders(
        in: &state.headers,
        outboundEncoding: outboundEncoding,
        configuration: configuration,
        customMetadata: metadata
      )
      self.state = .clientClosedServerOpen(.init(previousState: state))
      return state.headers

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
    case ._modifying:
      preconditionFailure()
    }
  }

  private mutating func serverSend(
    message: [UInt8],
    promise: EventLoopPromise<Void>?
  ) throws(InvalidState) {
    switch self.state {
    case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
      try self.invalidState(
        "Server must have sent initial metadata before sending a message."
      )

    case .clientOpenServerOpen(var state):
      self.state = ._modifying
      state.framer.append(message, promise: promise)
      self.state = .clientOpenServerOpen(state)

    case .clientClosedServerOpen(var state):
      self.state = ._modifying
      state.framer.append(message, promise: promise)
      self.state = .clientClosedServerOpen(state)

    case .clientOpenServerClosed, .clientClosedServerClosed:
      try self.invalidState(
        "Server can't send a message if it's closed."
      )
    case ._modifying:
      preconditionFailure()
    }
  }

  private mutating func serverSend(
    status: Status,
    customMetadata: Metadata
  ) throws(InvalidState) -> HPACKHeaders {
    // Close the server.
    switch self.state {
    case .clientOpenServerOpen(var state):
      self.state = ._modifying
      state.headers.formTrailers(status: status, metadata: customMetadata)
      self.state = .clientOpenServerClosed(.init(previousState: state))
      return state.headers

    case .clientClosedServerOpen(var state):
      self.state = ._modifying
      state.headers.formTrailers(status: status, metadata: customMetadata)
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return state.headers

    case .clientOpenServerIdle(var state):
      self.state = ._modifying
      state.headers.formTrailersOnly(status: status, metadata: customMetadata)
      self.state = .clientOpenServerClosed(.init(previousState: state))
      return state.headers

    case .clientClosedServerIdle(var state):
      self.state = ._modifying
      state.headers.formTrailersOnly(status: status, metadata: customMetadata)
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return state.headers

    case .clientIdleServerIdle:
      try self.invalidState(
        "Server can't send status if client is idle."
      )
    case .clientOpenServerClosed, .clientClosedServerClosed:
      try self.invalidState(
        "Server can't send anything if closed."
      )
    case ._modifying:
      preconditionFailure()
    }
  }

  private mutating func serverReceive(
    headers: HPACKHeaders,
    endStream: Bool,
    configuration: GRPCStreamStateMachineConfiguration.ServerConfiguration
  ) throws(InvalidState) -> OnMetadataReceived {
    func closeServer(
      from state: GRPCStreamStateMachineState.ClientIdleServerIdleState,
      endStream: Bool
    ) -> GRPCStreamStateMachineState {
      if endStream {
        return .clientClosedServerClosed(.init(previousState: state))
      } else {
        return .clientOpenServerClosed(.init(previousState: state))
      }
    }

    switch self.state {
    case .clientIdleServerIdle(let state):
      let contentType = headers.firstString(forKey: .contentType)
        .flatMap { ContentType(value: $0) }
      if contentType == nil {
        self.state = .clientOpenServerClosed(.init(previousState: state))

        // Respond with HTTP-level Unsupported Media Type status code.
        var trailers = HPACKHeaders()
        trailers.add("415", forKey: .status)
        return .rejectRPC_serverOnly(trailers: trailers)
      }

      guard let pathHeader = headers.firstString(forKey: .path) else {
        self.state = closeServer(from: state, endStream: endStream)
        return .rejectRPC_serverOnly(
          trailers: .trailersOnly(
            code: .invalidArgument,
            message: "No \(GRPCHTTP2Keys.path.rawValue) header has been set."
          )
        )
      }

      guard let path = MethodDescriptor(path: pathHeader) else {
        self.state = closeServer(from: state, endStream: endStream)
        return .rejectRPC_serverOnly(
          trailers: .trailersOnly(
            code: .unimplemented,
            message:
              "The given \(GRPCHTTP2Keys.path.rawValue) (\(pathHeader)) does not correspond to a valid method."
          )
        )
      }

      let scheme = headers.firstString(forKey: .scheme).flatMap { Scheme(rawValue: $0) }
      if scheme == nil {
        self.state = closeServer(from: state, endStream: endStream)
        return .rejectRPC_serverOnly(
          trailers: .trailersOnly(
            code: .invalidArgument,
            message: ":scheme header must be present and one of \"http\" or \"https\"."
          )
        )
      }

      guard let method = headers.firstString(forKey: .method), method == "POST" else {
        self.state = closeServer(from: state, endStream: endStream)
        return .rejectRPC_serverOnly(
          trailers: .trailersOnly(
            code: .invalidArgument,
            message: ":method header is expected to be present and have a value of \"POST\"."
          )
        )
      }

      guard let te = headers.firstString(forKey: .te), te == "trailers" else {
        self.state = closeServer(from: state, endStream: endStream)
        return .rejectRPC_serverOnly(
          trailers: .trailersOnly(
            code: .invalidArgument,
            message: "\"te\" header is expected to be present and have a value of \"trailers\"."
          )
        )
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
          self.state = closeServer(from: state, endStream: endStream)
          return .rejectRPC_serverOnly(
            trailers: .trailersOnly(
              code: .internalError,
              message: "\(GRPCHTTP2Keys.encoding) must contain no more than one value."
            )
          )
        }

        guard let clientEncoding = CompressionAlgorithm(name: rawEncoding),
          configuration.acceptedEncodings.contains(clientEncoding)
        else {
          self.state = closeServer(from: state, endStream: endStream)
          var trailers = HPACKHeaders.trailersOnly(
            code: .unimplemented,
            message: """
              \(rawEncoding) compression is not supported; \
              supported algorithms are listed in grpc-accept-encoding
              """
          )

          for acceptedEncoding in configuration.acceptedEncodings.elements {
            trailers.add(name: GRPCHTTP2Keys.acceptEncoding.rawValue, value: acceptedEncoding.name)
          }

          return .rejectRPC_serverOnly(trailers: trailers)
        }

        // Server supports client's encoding.
        inboundEncoding = clientEncoding
      } else {
        inboundEncoding = .none
      }

      // Secondly, find a compatible encoding the server can use to compress outbound messages,
      // based on the encodings the client has advertised.
      var outboundEncoding: CompressionAlgorithm = .none
      let clientAdvertisedEncodings = headers.values(
        forHeader: GRPCHTTP2Keys.acceptEncoding.rawValue,
        canonicalForm: true
      )
      // Find the preferred encoding and use it to compress responses.
      for clientAdvertisedEncoding in clientAdvertisedEncodings {
        if let algorithm = CompressionAlgorithm(name: clientAdvertisedEncoding),
          configuration.acceptedEncodings.contains(algorithm)
        {
          outboundEncoding = algorithm
          break
        }
      }

      if endStream {
        self.state = .clientClosedServerIdle(
          .init(
            previousState: state,
            compressionAlgorithm: outboundEncoding,
            headers: headers
          )
        )
      } else {
        let compressor = Zlib.Method(encoding: outboundEncoding)
          .flatMap { Zlib.Compressor(method: $0) }
        let decompressor = Zlib.Method(encoding: inboundEncoding)
          .flatMap { Zlib.Decompressor(method: $0) }

        self.state = .clientOpenServerIdle(
          .init(
            previousState: state,
            compressor: compressor,
            outboundCompression: outboundEncoding,
            framer: GRPCMessageFramer(),
            decompressor: decompressor,
            deframer: GRPCMessageDeframer(
              maxPayloadSize: state.maximumPayloadSize,
              decompressor: decompressor
            ),
            headers: headers
          )
        )
      }

      return .receivedMetadata(Metadata(headers: headers), path)

    case .clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed:
      // Metadata has already been received, should only be sent once by clients.
      return .protocolViolation_serverOnly

    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      try self.invalidState("Client can't have sent metadata if closed.")

    case ._modifying:
      preconditionFailure()
    }
  }

  private mutating func serverReceive(
    buffer: ByteBuffer,
    endStream: Bool
  ) throws(InvalidState) -> OnBufferReceivedAction {
    let action: OnBufferReceivedAction

    switch self.state {
    case .clientIdleServerIdle:
      try self.invalidState("Can't have received a message if client is idle.")

    case .clientOpenServerIdle(var state):
      self.state = ._modifying
      // Deframer must be present on the server side, as we know the decompression
      // algorithm from the moment the client opens.
      do {
        state.deframer!.append(buffer)
        try state.deframer!.decode(into: &state.inboundMessageBuffer)
        action = .readInbound
      } catch {
        let error = RPCError(code: .internalError, message: "Failed to decode message")
        action = .forwardErrorAndClose_serverOnly(error)
      }

      if endStream {
        self.state = .clientClosedServerIdle(.init(previousState: state))
      } else {
        self.state = .clientOpenServerIdle(state)
      }

    case .clientOpenServerOpen(var state):
      self.state = ._modifying
      do {
        state.deframer.append(buffer)
        try state.deframer.decode(into: &state.inboundMessageBuffer)
        action = .readInbound
      } catch {
        let error = RPCError(code: .internalError, message: "Failed to decode message")
        action = .forwardErrorAndClose_serverOnly(error)
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

      action = .doNothing

    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      try self.invalidState("Client can't send a message if closed.")

    case ._modifying:
      preconditionFailure()
    }

    return action
  }

  private mutating func serverNextOutboundFrame() throws(InvalidState) -> OnNextOutboundFrame {
    switch self.state {
    case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
      try self.invalidState("Server is not open yet.")

    case .clientOpenServerOpen(var state):
      self.state = ._modifying
      let next = state.framer.nextResult(compressor: state.compressor)
      self.state = .clientOpenServerOpen(state)

      if let next = next {
        return OnNextOutboundFrame(result: next.result, promise: next.promise)
      } else {
        return .awaitMoreMessages
      }

    case .clientClosedServerOpen(var state):
      self.state = ._modifying
      let next = state.framer.nextResult(compressor: state.compressor)
      self.state = .clientClosedServerOpen(state)

      if let next = next {
        return OnNextOutboundFrame(result: next.result, promise: next.promise)
      } else {
        return .awaitMoreMessages
      }

    case .clientOpenServerClosed(var state):
      self.state = ._modifying
      let next = state.framer?.nextResult(compressor: state.compressor)
      self.state = .clientOpenServerClosed(state)

      if let next = next {
        return OnNextOutboundFrame(result: next.result, promise: next.promise)
      } else {
        return .noMoreMessages
      }

    case .clientClosedServerClosed(var state):
      self.state = ._modifying
      let next = state.framer?.nextResult(compressor: state.compressor)
      self.state = .clientClosedServerClosed(state)

      if let next = next {
        return OnNextOutboundFrame(result: next.result, promise: next.promise)
      } else {
        return .noMoreMessages
      }

    case ._modifying:
      preconditionFailure()
    }
  }

  private mutating func serverNextInboundMessage() -> OnNextInboundMessage {
    switch self.state {
    case .clientOpenServerIdle(var state):
      self.state = ._modifying
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerIdle(state)
      return request.map { .receiveMessage($0) } ?? .awaitMoreMessages

    case .clientOpenServerOpen(var state):
      self.state = ._modifying
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientOpenServerOpen(state)
      return request.map { .receiveMessage($0) } ?? .awaitMoreMessages

    case .clientClosedServerIdle(var state):
      self.state = ._modifying
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerIdle(state)
      return request.map { .receiveMessage($0) } ?? .noMoreMessages

    case .clientClosedServerOpen(var state):
      self.state = ._modifying
      let request = state.inboundMessageBuffer.pop()
      self.state = .clientClosedServerOpen(state)
      return request.map { .receiveMessage($0) } ?? .noMoreMessages

    case .clientOpenServerClosed, .clientClosedServerClosed:
      // Server has closed, no need to read.
      return .noMoreMessages

    case .clientIdleServerIdle:
      return .awaitMoreMessages

    case ._modifying:
      preconditionFailure()
    }
  }

  private mutating func serverUnexpectedInboundClose(
    reason: UnexpectedInboundCloseReason
  ) -> OnUnexpectedInboundClose {
    switch self.state {
    case .clientIdleServerIdle(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return OnUnexpectedInboundClose(serverCloseReason: reason)

    case .clientOpenServerIdle(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return OnUnexpectedInboundClose(serverCloseReason: reason)

    case .clientOpenServerOpen(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return OnUnexpectedInboundClose(serverCloseReason: reason)

    case .clientOpenServerClosed(let state):
      self.state = .clientClosedServerClosed(.init(previousState: state))
      return OnUnexpectedInboundClose(serverCloseReason: reason)

    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      return .doNothing

    case ._modifying:
      preconditionFailure()
    }
  }
}

extension MethodDescriptor {
  init?(path: String) {
    var view = path[...]
    guard view.popFirst() == "/" else { return nil }

    // Find the index of the "/" separating the service and method names.
    guard var index = view.firstIndex(of: "/") else { return nil }

    let service = String(view[..<index])
    view.formIndex(after: &index)
    let method = String(view[index...])

    self.init(service: service, method: method)
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
  case grpcStatusMessage = "grpc-message"
}

extension HPACKHeaders {
  func firstString(forKey key: GRPCHTTP2Keys, canonicalForm: Bool = true) -> String? {
    self.values(forHeader: key.rawValue, canonicalForm: canonicalForm).first(where: { _ in true })
      .map {
        String($0)
      }
  }

  fileprivate mutating func add(_ value: String, forKey key: GRPCHTTP2Keys) {
    self.add(name: key.rawValue, value: value)
  }

  fileprivate static func trailersOnly(code: Status.Code, message: String) -> Self {
    var trailers = HPACKHeaders()
    HPACKHeaders.formTrailers(
      &trailers,
      isTrailersOnly: true,
      status: Status(code: code, message: message),
      metadata: [:]
    )
    return trailers
  }

  fileprivate mutating func formTrailersOnly(status: Status, metadata: Metadata = [:]) {
    Self.formTrailers(&self, isTrailersOnly: true, status: status, metadata: metadata)
  }

  fileprivate mutating func formTrailers(status: Status, metadata: Metadata = [:]) {
    Self.formTrailers(&self, isTrailersOnly: false, status: status, metadata: metadata)
  }

  private static func formTrailers(
    _ trailers: inout HPACKHeaders,
    isTrailersOnly: Bool,
    status: Status,
    metadata: Metadata
  ) {
    trailers.removeAll(keepingCapacity: true)

    if isTrailersOnly {
      trailers.reserveCapacity(4 + metadata.count)
      trailers.add("200", forKey: .status)
      trailers.add(ContentType.grpc.canonicalValue, forKey: .contentType)
    } else {
      trailers.reserveCapacity(2 + metadata.count)
    }

    trailers.add(String(status.code.rawValue), forKey: .grpcStatus)
    if !status.message.isEmpty, let encoded = GRPCStatusMessageMarshaller.marshall(status.message) {
      trailers.add(encoded, forKey: .grpcStatusMessage)
    }

    for (key, value) in metadata {
      trailers.add(name: key, value: value.encoded())
    }
  }
}

extension Zlib.Method {
  init?(encoding: CompressionAlgorithm) {
    switch encoding {
    case .none:
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

extension MethodDescriptor {
  var path: String {
    return "/\(self.service)/\(self.method)"
  }
}

extension RPCError {
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  fileprivate init(_ reason: GRPCStreamStateMachine.UnexpectedInboundCloseReason) {
    switch reason {
    case .streamReset:
      self = RPCError(
        code: .unavailable,
        message: "Stream unexpectedly closed: a RST_STREAM frame was received."
      )
    case .channelInactive:
      self = RPCError(code: .unavailable, message: "Stream unexpectedly closed.")
    case .errorThrown:
      self = RPCError(code: .unavailable, message: "Stream unexpectedly closed with error.")
    }
  }
}

extension Status {
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  fileprivate init(_ error: RPCError) {
    self = Status(code: Status.Code(error.code), message: error.message)
  }
}

extension RPCError {
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  init(_ invalidState: GRPCStreamStateMachine.InvalidState) {
    self = RPCError(code: .internalError, message: "Invalid state", cause: invalidState)
  }
}
