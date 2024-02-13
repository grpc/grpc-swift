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

enum OnMetadataReceived {
  case reject(status: Status, trailers: Metadata)
  case doNothing
}

fileprivate protocol GRPCStreamStateMachineProtocol {
  var state: GRPCStreamStateMachineState { get set }
  
  mutating func send(metadata: Metadata) throws
  mutating func send(message: [UInt8], endStream: Bool) throws
  mutating func send(status: String, trailingMetadata: Metadata) throws
  
  mutating func receive(metadata: Metadata, endStream: Bool) throws -> OnMetadataReceived
  mutating func receive(message: ByteBuffer, endStream: Bool) throws
  
  mutating func nextOutboundMessage() throws -> ByteBuffer?
  mutating func nextInboundMessage() -> [UInt8]?
}

enum GRPCStreamStateMachineConfiguration {
  case client(
    maximumPayloadSize: Int,
    supportedCompressionAlgorithms: [CompressionAlgorithm]
  )
  case server(
    maximumPayloadSize: Int,
    supportedCompressionAlgorithms: [CompressionAlgorithm]
  )
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
      
      // TODO: we should check here or in a `MessageEncoder` (instead of the state machine)
      // that the server supports the given encoding - otherwise return the corresponding response.
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
      decompressionAlgorithm: CompressionAlgorithm?
    ) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      
      if let previousDeframer = previousState.deframer {
        self.deframer = previousDeframer
        self.decompressor = previousState.decompressor
      } else {
        // TODO: we should check here or in a `MessageEncoder` (instead of the state machine)
        // that the client supports the given encoding - otherwise return the corresponding response.
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
    
    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>?
    var decompressor: Zlib.Decompressor?
    
    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>
    
    init(previousState: ClientOpenServerIdleState) {
      self.maximumPayloadSize = previousState.maximumPayloadSize
      self.framer = previousState.framer
      self.compressor = previousState.compressor
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
      decompressionAlgorithm: CompressionAlgorithm?
    ) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
      
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
    // These are already deframed, so we don't need the deframer anymore.
    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>
    
    init(previousState: ClientClosedServerOpenState) {
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }
    
    init(previousState: ClientClosedServerIdleState) {
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }
    
    init(previousState: ClientOpenServerClosedState) {
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct GRPCStreamStateMachine {
  private var _stateMachine: GRPCStreamStateMachineProtocol
  
  init(
    configuration: GRPCStreamStateMachineConfiguration,
    skipAssertions: Bool = false
  ) {
    switch configuration {
    case .client(let maximumPayloadSize, let supportedCompressionAlgorithms):
      self._stateMachine = Client(
        maximumPayloadSize: maximumPayloadSize,
        supportedCompressionAlgorithms: supportedCompressionAlgorithms,
        skipAssertions: skipAssertions
      )
    case .server(let maximumPayloadSize, let supportedCompressionAlgorithms):
      self._stateMachine = Server(
        maximumPayloadSize: maximumPayloadSize,
        supportedCompressionAlgorithms: supportedCompressionAlgorithms,
        skipAssertions: skipAssertions
      )
    }
  }
  
  mutating func send(metadata: Metadata) throws {
    try self._stateMachine.send(metadata: metadata)
  }
  
  mutating func send(message: [UInt8], endStream: Bool) throws {
    try self._stateMachine.send(message: message, endStream: endStream)
  }
  
  mutating func send(status: String, trailingMetadata: Metadata) throws {
    try self._stateMachine.send(status: status, trailingMetadata: trailingMetadata)
  }
  
  mutating func receive(metadata: Metadata, endStream: Bool) throws -> OnMetadataReceived {
    try self._stateMachine.receive(metadata: metadata, endStream: endStream)
  }
  
  mutating func receive(message: ByteBuffer, endStream: Bool) throws {
    try self._stateMachine.receive(message: message, endStream: endStream)
  }
  
  mutating func nextOutboundMessage() throws -> ByteBuffer? {
    try self._stateMachine.nextOutboundMessage()
  }
  
  mutating func nextInboundMessage() -> [UInt8]? {
    self._stateMachine.nextInboundMessage()
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine {
  struct Client: GRPCStreamStateMachineProtocol {
    fileprivate var state: GRPCStreamStateMachineState
    private let supportedCompressionAlgorithms: [CompressionAlgorithm]
    private let skipAssertions: Bool

    init(
      maximumPayloadSize: Int,
      supportedCompressionAlgorithms: [CompressionAlgorithm],
      skipAssertions: Bool
    ) {
      self.state = .clientIdleServerIdle(.init(maximumPayloadSize: maximumPayloadSize))
      self.supportedCompressionAlgorithms = supportedCompressionAlgorithms
      self.skipAssertions = skipAssertions
    }

    mutating func send(metadata: Metadata) throws {
      // Client sends metadata only when opening the stream.
      switch self.state {
      case .clientIdleServerIdle(let state):
        guard metadata.path != nil else {
          throw RPCError(
            code: .invalidArgument,
            message: "Endpoint is missing: client cannot send initial metadata without it."
          )
        }

        self.state = .clientOpenServerIdle(.init(
          previousState: state,
          compressionAlgorithm: metadata.encoding,
          decompressionConfiguration: .decompressionNotYetKnown
        ))
      case .clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Client is already open: shouldn't be sending metadata.")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Client is closed: can't send metadata.")
      }
    }

    mutating func send(message: [UInt8], endStream: Bool) throws {
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
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Client is closed, cannot send a message.")
      }
    }
    
    mutating func send(status: String, trailingMetadata: Metadata) throws {
      throw self.assertionFailureAndCreateRPCErrorOnInternalError("Client cannot send status and trailer.")
    }
    
    /// Returns the client's next request to the server.
    /// - Returns: The request to be made to the server.
    mutating func nextOutboundMessage() throws -> ByteBuffer? {
      switch self.state {
      case .clientIdleServerIdle:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Client is not open yet.")
      case .clientOpenServerIdle(var state):
        let request = try state.framer.next(compressor: state.compressor)
        self.state = .clientOpenServerIdle(state)
        return request
      case .clientOpenServerOpen(var state):
        let request = try state.framer.next(compressor: state.compressor)
        self.state = .clientOpenServerOpen(state)
        return request
      case .clientOpenServerClosed(var state):
        // Server may have closed but still be waiting for client messages,
        // for example if it's a client-streaming RPC.
        let request = try state.framer.next(compressor: state.compressor)
        self.state = .clientOpenServerClosed(state)
        return request
      case .clientClosedServerIdle(var state):
        let request = try state.framer.next(compressor: state.compressor)
        self.state = .clientClosedServerIdle(state)
        return request
      case .clientClosedServerOpen(var state):
        let request = try state.framer.next(compressor: state.compressor)
        self.state = .clientClosedServerOpen(state)
        return request
      case .clientClosedServerClosed:
        // Nothing to do if both are closed.
        return nil
      }
    }
    
    mutating func receive(metadata: Metadata, endStream: Bool) throws -> OnMetadataReceived {
      switch self.state {
      case .clientIdleServerIdle:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Server cannot have sent metadata if the client is idle.")
      case .clientOpenServerIdle(let state):
        if endStream {
          // This is a trailers-only response: close server.
          self.state = .clientOpenServerClosed(.init(previousState: state))
        } else {
          self.state = .clientOpenServerOpen(.init(
            previousState: state,
            decompressionAlgorithm: metadata.encoding
          ))
        }
      case .clientOpenServerOpen(let state):
        if endStream {
          self.state = .clientOpenServerClosed(.init(previousState: state))
        } else {
          // This state is valid: server can send trailing metadata without END_STREAM
          // set, and follow it with an empty message frame where the flag *is* set.
          ()
          // TODO: I believe we should set some flag in the state to signal that
          // we're expecting an empty data frame with END_STREAM set; otherwise,
          // we could get an infinite number of metadata frames from the server -
          // not sure this should be allowed.
        }
      case .clientClosedServerIdle(let state):
        if endStream {
          // This is a trailers-only response.
          self.state = .clientClosedServerClosed(.init(previousState: state))
        } else {
          self.state = .clientClosedServerOpen(.init(
            previousState: state,
            decompressionAlgorithm: metadata.encoding
          ))
        }
      case .clientClosedServerOpen(let state):
        if endStream {
          state.compressor?.end()
          state.decompressor?.end()
          self.state = .clientClosedServerClosed(.init(previousState: state))
        } else {
          // This state is valid: server can send trailing metadata without END_STREAM
          // set, and follow it with an empty message frame where the flag *is* set.
          ()
          // TODO: I believe we should set some flag in the state to signal that
          // we're expecting an empty data frame with END_STREAM set; otherwise,
          // we could get an infinite number of metadata frames from the server -
          // not sure this should be allowed.
        }
      case .clientOpenServerClosed, .clientClosedServerClosed:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Server is closed, nothing could have been sent.")
      }
      
      return .doNothing
    }
    
    mutating func receive(message: ByteBuffer, endStream: Bool) throws {
      // This is a message received by the client, from the server.
      switch self.state {
      case .clientIdleServerIdle:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Cannot have received anything from server if client is not yet open.")
      case .clientOpenServerIdle, .clientClosedServerIdle:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Server cannot have sent a message before sending the initial metadata.")
      case .clientOpenServerOpen(var state):
        try state.deframer.process(buffer: message) { deframedMessage in
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
        try state.deframer.process(buffer: message) { deframedMessage in
          state.inboundMessageBuffer.append(deframedMessage)
        }
        if endStream {
          self.state = .clientClosedServerClosed(.init(previousState: state))
        } else {
          self.state = .clientClosedServerOpen(state)
        }
      case .clientOpenServerClosed:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Cannot have received anything from a closed server.")
      case .clientClosedServerClosed:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Shouldn't have received anything if both client and server are closed.")
      }
    }
    
    mutating func nextInboundMessage() -> [UInt8]? {
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
    
    private func assertionFailureAndCreateRPCErrorOnInternalError(_ message: String, line: UInt = #line) -> RPCError {
      if !self.skipAssertions {
        assertionFailure(message, line: line)
      }
      return RPCError(code: .internalError, message: message)
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine {
  struct Server: GRPCStreamStateMachineProtocol {
    fileprivate var state: GRPCStreamStateMachineState
    let supportedCompressionAlgorithms: [CompressionAlgorithm]
    private let skipAssertions: Bool
    
    init(
      maximumPayloadSize: Int,
      supportedCompressionAlgorithms: [CompressionAlgorithm],
      skipAssertions: Bool
    ) {
      self.state = .clientIdleServerIdle(.init(maximumPayloadSize: maximumPayloadSize))
      self.supportedCompressionAlgorithms = supportedCompressionAlgorithms
      self.skipAssertions = skipAssertions
    }
    
    mutating func send(metadata: Metadata) throws {
      // Server sends initial metadata. This transitions server to open.
      switch self.state {
      case .clientIdleServerIdle:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Client cannot be idle if server is sending initial metadata: it must have opened.")
      case .clientOpenServerIdle(let state):
        self.state = .clientOpenServerOpen(.init(
          previousState: state,
          decompressionAlgorithm: metadata.encoding
        ))
      case .clientOpenServerClosed, .clientClosedServerClosed:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Server cannot send metadata if closed.")
      case .clientClosedServerIdle(let state):
        self.state = .clientClosedServerOpen(.init(
          previousState: state,
          decompressionAlgorithm: metadata.encoding
        ))
      case .clientOpenServerOpen, .clientClosedServerOpen:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Server has already sent initial metadata.")
        
      }
    }
    
    mutating func send(message: [UInt8], endStream: Bool) throws {
      switch self.state {
      case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Server must have sent initial metadata before sending a message.")
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
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Server can't send a message if it's closed.")
      }
    }
    
    mutating func send(status: String, trailingMetadata: Metadata) throws {
      // Close the server.
      switch self.state {
      case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Server can't send status if idle.")
      case .clientOpenServerOpen(let state):
        self.state = .clientOpenServerClosed(.init(previousState: state))
      case .clientClosedServerOpen(let state):
        state.compressor?.end()
        state.decompressor?.end()
        self.state = .clientClosedServerClosed(.init(previousState: state))
      case .clientOpenServerClosed, .clientClosedServerClosed:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Server can't send anything if closed.")
      }
    }

    mutating func receive(metadata: Metadata, endStream: Bool) throws -> OnMetadataReceived {
      if endStream, case .clientIdleServerIdle = self.state {
        throw self.assertionFailureAndCreateRPCErrorOnInternalError(
          """
          Client should have opened before ending the stream: \
          stream shouldn't have been closed when sending initial metadata.
          """
        )
      }
      
      switch self.state {
      case .clientIdleServerIdle(let state):
        var preferredCompressionEncoding: CompressionAlgorithm? = nil
        if let acceptedEncodings = metadata.acceptedEncodings {
          for acceptedEncoding in acceptedEncodings where self.supportedCompressionAlgorithms.contains(where: { $0 == acceptedEncoding }) {
            // Found the preferred encoding: use it to compress responses.
            preferredCompressionEncoding = acceptedEncoding
            break
          }
        }
        
        self.state = .clientOpenServerIdle(.init(
          previousState: state,
          compressionAlgorithm: preferredCompressionEncoding,
          decompressionConfiguration: .decompression(metadata.encoding)
        ))
        
        guard let contentType = metadata.contentType else {
          throw RPCError(code: .invalidArgument, message: "Invalid or empty content-type.")
        }
        
        guard let endpoint = metadata.path else {
          throw RPCError(code: .unimplemented, message: "No :path header has been set.")
        }
        
        // TODO: Should we verify the RPCRouter can handle this endpoint here,
        // or should we verify that in the handler?
        
        let encodingValues = metadata[stringValues: "grpc-encoding"]
        var encodingValuesIterator = encodingValues.makeIterator()
        if let rawEncoding = encodingValuesIterator.next() {
          guard encodingValuesIterator.next() == nil else {
            throw RPCError(
              code: .invalidArgument,
              message: "grpc-encoding must contain no more than one value"
            )
          }
          guard let encoding = CompressionAlgorithm(rawValue: rawEncoding) else {
            let status = Status(
              code: .unimplemented,
              message: "\(rawEncoding) compression is not supported; supported algorithms are listed in grpc-accept-encoding"
            )
            let trailers = Metadata(dictionaryLiteral: (
              "grpc-accept-encoding",
              .string(self.supportedCompressionAlgorithms
                .map({ $0.name })
                .joined(separator: ",")
              )
            ))
            return .reject(status: status, trailers: trailers)
          }

          guard self.supportedCompressionAlgorithms.contains(where: { $0 == encoding }) else {
            if self.supportedCompressionAlgorithms.isEmpty {
              throw RPCError(
                code: .unimplemented,
                message: "Compression is not supported"
              )
            } else {
              let status = Status(
                code: .unimplemented,
                message: "\(encoding) compression is not supported; supported algorithms are listed in grpc-accept-encoding"
              )
              let trailers = Metadata(dictionaryLiteral: (
                "grpc-accept-encoding",
                .string(self.supportedCompressionAlgorithms
                  .map({ $0.name })
                  .joined(separator: ",")
                )
              ))
              return .reject(status: status, trailers: trailers)
            }
          }
        }
        return .doNothing
      case .clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Client shouldn't have sent metadata twice.")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Client can't have sent metadata if closed.")
      }
    }
    
    mutating func receive(message: ByteBuffer, endStream: Bool) throws {
      switch self.state {
      case .clientIdleServerIdle:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Can't have received a message if client is idle.")
      case .clientOpenServerIdle(var state):
        // Deframer must be present on the server side, as we know the decompression
        // algorithm from the moment the client opens.
        assert(state.deframer != nil)
        try state.deframer!.process(buffer: message) { deframedMessage in
          state.inboundMessageBuffer.append(deframedMessage)
        }
        
        if endStream {
          self.state = .clientClosedServerIdle(.init(previousState: state))
        } else {
          self.state = .clientOpenServerIdle(state)
        }
      case .clientOpenServerOpen(var state):
        try state.deframer.process(buffer: message) { deframedMessage in
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
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Client can't send a message if closed.")
      }
    }
    
    mutating func nextOutboundMessage() throws -> ByteBuffer? {
      switch self.state {
      case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Server is not open yet.")
      case .clientOpenServerOpen(var state):
        let response = try state.framer.next(compressor: state.compressor)
        self.state = .clientOpenServerOpen(state)
        return response
      case .clientClosedServerOpen(var state):
        let response = try state.framer.next(compressor: state.compressor)
        self.state = .clientClosedServerOpen(state)
        return response
      case .clientOpenServerClosed, .clientClosedServerClosed:
        throw self.assertionFailureAndCreateRPCErrorOnInternalError("Can't send response if server is closed.")
      }
    }
    
    mutating func nextInboundMessage() -> [UInt8]? {
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
    
    private func assertionFailureAndCreateRPCErrorOnInternalError(_ message: String, line: UInt = #line) -> RPCError {
      assert(self.skipAssertions, message, line: line)
      return RPCError(code: .internalError, message: message)
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

extension Metadata {
  var path: MethodDescriptor? {
    get {
      self.firstString(forKey: .endpoint)
        .flatMap { MethodDescriptor(fullyQualifiedMethod: $0) }
    }
    set {
      if let newValue {
        self.replaceOrAddString(newValue.fullyQualifiedMethod, forKey: .endpoint)
      } else {
        self.removeAllValues(forKey: .endpoint)
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
        self.replaceOrAddString(newValue.canonicalValue, forKey: .contentType)
      } else {
        self.removeAllValues(forKey: .contentType)
      }
    }
  }
  
  var encoding: CompressionAlgorithm? {
    get {
      self.firstString(forKey: .encoding).flatMap { CompressionAlgorithm(rawValue: $0) }
    }
    set {
      if let newValue {
        self.replaceOrAddString(newValue.name, forKey: .encoding)
      } else {
        self.removeAllValues(forKey: .encoding)
      }
    }
  }
  
  var acceptedEncodings: [CompressionAlgorithm]? {
    get {
      self.firstString(forKey: .acceptEncoding)?
        .split(separator: ",")
        .compactMap { CompressionAlgorithm(rawValue: String($0)) }
    }
    set {
      if let newValue {
        self.replaceOrAddString(newValue.map({ $0.name }).joined(separator: ","), forKey: .acceptEncoding)
      } else {
        self.removeAllValues(forKey: .acceptEncoding)
      }
    }
  }
  
  private enum GRPCHTTP2Keys: String {
    case endpoint = ":path"
    case contentType = "content-type"
    case encoding = "grpc-encoding"
    case acceptEncoding = "grpc-accept-encoding"
  }
  
  private func firstString(forKey key: GRPCHTTP2Keys) -> String? {
    self[stringValues: key.rawValue].first(where: { _ in true })
  }
  
  private mutating func replaceOrAddString(_ value: String, forKey key: GRPCHTTP2Keys) {
    self.replaceOrAddString(value, forKey: key.rawValue)
  }

  private mutating func removeAllValues(forKey key: GRPCHTTP2Keys) {
    self.removeAllValues(forKey: key.rawValue)
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
