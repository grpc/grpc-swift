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
  case client(maximumPayloadSize: Int)
  case server(
    maximumPayloadSize: Int,
    supportedCompressionAlgorithms: [Encoding]
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
  
  struct ClientOpenServerIdleState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    
    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>
    var decompressor: Zlib.Decompressor?
    
    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>
    
    init(
      previousState: ClientIdleServerIdleState,
      compressionAlgorithm: Encoding?
    ) {
      if let zlibMethod = Zlib.Method(encoding: compressionAlgorithm) {
        self.compressor = Zlib.Compressor(method: zlibMethod)
        self.decompressor = Zlib.Decompressor(method: zlibMethod)
      }
      
      self.framer = GRPCMessageFramer()
      let decoder = GRPCMessageDeframer(
        maximumPayloadSize: previousState.maximumPayloadSize,
        decompressor: self.decompressor
      )
      self.deframer = NIOSingleStepByteToMessageProcessor(decoder)
      
      self.inboundMessageBuffer = .init()
    }
  }
  
  struct ClientOpenServerOpenState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    
    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>
    var decompressor: Zlib.Decompressor?
    
    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>
    
    init(previousState: ClientOpenServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
      self.inboundMessageBuffer = previousState.inboundMessageBuffer
    }
  }
  
  struct ClientOpenServerClosedState {
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
  }
  
  struct ClientClosedServerIdleState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    
    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>
    var decompressor: Zlib.Decompressor?
    
    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>
    
    init(previousState: ClientOpenServerIdleState) {
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
  }
  
  struct ClientClosedServerClosedState {
    var inboundMessageBuffer: OneOrManyQueue<[UInt8]>
    
    init(previousState: ClientClosedServerOpenState) {
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
    case .client(let maximumPayloadSize):
      self._stateMachine = Client(maximumPayloadSize: maximumPayloadSize, skipAssertions: skipAssertions)
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
    private let skipAssertions: Bool

    init(maximumPayloadSize: Int, skipAssertions: Bool) {
      self.state = .clientIdleServerIdle(.init(maximumPayloadSize: maximumPayloadSize))
      self.skipAssertions = skipAssertions
    }

    mutating func send(metadata: Metadata) throws {
      // Client sends metadata only when opening the stream.
      switch self.state {
      case .clientIdleServerIdle(let state):
        guard metadata.endpoint != nil else {
          throw RPCError(
            code: .invalidArgument,
            message: "Endpoint is missing: client cannot send initial metadata without it."
          )
        }

        self.state = .clientOpenServerIdle(.init(
          previousState: state,
          compressionAlgorithm: metadata.encoding
        ))
      case .clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client is already open: shouldn't be sending metadata.")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client is closed: can't send metadata.")
      }
    }

    mutating func send(message: [UInt8], endStream: Bool) throws {
      // Client sends message.
      switch self.state {
      case .clientIdleServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client not yet open.")
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
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client is closed, cannot send a message.")
      }
    }
    
    mutating func send(status: String, trailingMetadata: Metadata) throws {
      throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client cannot send status and trailer.")
    }
    
    /// Returns the client's next request to the server.
    /// - Returns: The request to be made to the server.
    mutating func nextOutboundMessage() throws -> ByteBuffer? {
      switch self.state {
      case .clientIdleServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client is not open yet.")
      case .clientOpenServerIdle(var state):
        let request = try state.framer.next(compressor: state.compressor)
        self.state = .clientOpenServerIdle(state)
        return request
      case .clientOpenServerOpen(var state):
        let request = try state.framer.next(compressor: state.compressor)
        self.state = .clientOpenServerOpen(state)
        return request
      case .clientOpenServerClosed, .clientClosedServerClosed:
        // Nothing to do: no point in sending request if server is closed.
        return nil
      case .clientClosedServerIdle(var state):
        let request = try state.framer.next(compressor: state.compressor)
        self.state = .clientClosedServerIdle(state)
        return request
      case .clientClosedServerOpen(var state):
        let request = try state.framer.next(compressor: state.compressor)
        self.state = .clientClosedServerOpen(state)
        return request
      }
    }
    
    mutating func receive(metadata: Metadata, endStream: Bool) throws -> OnMetadataReceived {
      // This is metadata received by the client from the server.
      // It can be initial, which confirms that the server is now open;
      // or an END_STREAM trailer, meaning the response is over.
      if endStream {
        try self.clientReceivedEndHeader()
      } else {
        try self.clientReceivedMetadata()
      }
      return .doNothing
    }
    
    mutating func clientReceivedEndHeader() throws {
      switch self.state {
      case .clientIdleServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client can't have received a stream end trailer if both client and server are idle.")
      case .clientOpenServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server cannot have sent an end stream header if it is still idle.")
      case .clientOpenServerOpen(let state):
        self.state = .clientOpenServerClosed(.init(previousState: state))
      case .clientOpenServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server is already closed, can't have received the end stream trailer twice.")
      case .clientClosedServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server cannot have sent end stream trailer if it is idle.")
      case .clientClosedServerOpen(let state):
        state.compressor?.end()
        state.decompressor?.end()
        self.state = .clientClosedServerClosed(.init(previousState: state))
      case .clientClosedServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server cannot have sent end stream trailer if it is already closed.")
      }
    }
    
    mutating func clientReceivedMetadata() throws {
      switch self.state {
      case .clientIdleServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server cannot have sent metadata if the client is idle.")
      case .clientOpenServerIdle(let state):
        self.state = .clientOpenServerOpen(.init(previousState: state))
      case .clientOpenServerOpen:
        // This state is valid: server can send trailing metadata without END_STREAM
        // set, and follow it with an empty message frame where the flag *is* set.
        ()
        // TODO: I believe we should set some flag in the state to signal that
        // we're expecting an empty data frame with END_STREAM set; otherwise,
        // we could get an infinite number of metadata frames from the server -
        // not sure this should be allowed.
      case .clientOpenServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server is closed, nothing could have been sent.")
      case .clientClosedServerClosed, .clientClosedServerIdle, .clientClosedServerOpen:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client is closed, shouldn't have received anything.")
      }
    }
    
    mutating func receive(message: ByteBuffer, endStream: Bool) throws {
      // This is a message received by the client, from the server.
      switch self.state {
      case .clientIdleServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Cannot have received anything from server if client is not yet open.")
      case .clientOpenServerIdle, .clientClosedServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server cannot have sent a message before sending the initial metadata.")
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
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Cannot have received anything from a closed server.")
      case .clientClosedServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Shouldn't have received anything if both client and server are closed.")
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
      case .clientOpenServerIdle,
          .clientIdleServerIdle, 
          .clientClosedServerIdle:
        return nil
      }
    }
    
    private func assertionFailureAndCreateRPCErrorOnFailedPrecondition(_ message: String) -> RPCError {
      if !self.skipAssertions {
        assertionFailure(message)
      }
      return RPCError(code: .failedPrecondition, message: message)
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine {
  struct Server: GRPCStreamStateMachineProtocol {
    fileprivate var state: GRPCStreamStateMachineState
    let supportedCompressionAlgorithms: [Encoding]
    private let skipAssertions: Bool
    
    init(
      maximumPayloadSize: Int,
      supportedCompressionAlgorithms: [Encoding],
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
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client cannot be idle if server is sending initial metadata: it must have opened.")
      case .clientOpenServerIdle(let state):
        self.state = .clientOpenServerOpen(.init(previousState: state))
      case .clientOpenServerOpen:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server has already sent initial metadata.")
      case .clientOpenServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server cannot send metadata if closed.")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("No point in sending initial metadata if client is closed.")
      }
    }
    
    mutating func send(message: [UInt8], endStream: Bool) throws {
      switch self.state {
      case .clientIdleServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Cannot send a message when idle.")
      case .clientOpenServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server must have sent initial metadata before sending a message.")
      case .clientOpenServerOpen(var state):
        state.framer.append(message)
        self.state = .clientOpenServerOpen(state)
      case .clientOpenServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server can't send a message if it's closed.")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server can't send a message to a closed client.")
      }
    }
    
    mutating func send(status: String, trailingMetadata: Metadata) throws {
      // Close the server.
      switch self.state {
      case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server can't send anything if idle.")
      case .clientOpenServerOpen(let state):
        self.state = .clientOpenServerClosed(.init(previousState: state))
      case .clientOpenServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server is closed, can't send anything else.")
      case .clientClosedServerOpen(let state):
        state.compressor?.end()
        state.decompressor?.end()
        self.state = .clientClosedServerClosed(.init(previousState: state))
      case .clientClosedServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server can't send anything if closed.")
      }
    }

    mutating func receive(metadata: Metadata, endStream: Bool) throws -> OnMetadataReceived {
      if endStream {
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition(
          """
          Client should have opened before ending the stream:
          stream shouldn't have been closed when sending initial metadata.
          """
        )
      }
      
      guard let contentType = metadata.contentType else {
        throw RPCError(code: .invalidArgument, message: "Invalid or empty content-type.")
      }
      
      guard let endpoint = metadata.endpoint else {
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
        guard let encoding = Encoding(rawValue: rawEncoding) else {
          let status = Status(
            code: .unimplemented,
            message: "\(rawEncoding) compression is not supported; supported algorithms are listed in grpc-accept-encoding"
          )
          let trailers = Metadata(dictionaryLiteral: (
            "grpc-accept-encoding",
            .string(self.supportedCompressionAlgorithms
              .map({ $0.rawValue })
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
                .map({ $0.rawValue })
                .joined(separator: ",")
              )
            ))
            return .reject(status: status, trailers: trailers)
          }
        }
        
        // All good
      }

      switch self.state {
      case .clientIdleServerIdle(let state):
        self.state = .clientOpenServerIdle(.init(
          previousState: state,
          compressionAlgorithm: metadata.encoding
        ))
        return .doNothing
      case .clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client shouldn't have sent metadata twice.")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client can't have sent metadata if closed.")
      }
    }
    
    mutating func receive(message: ByteBuffer, endStream: Bool) throws {
      switch self.state {
      case .clientIdleServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Can't have received a message if client is idle.")
      case .clientOpenServerIdle(var state):
        try state.deframer.process(buffer: message) { deframedMessage in
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
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Client can't send a message if closed.")
      }
    }
    
    mutating func nextOutboundMessage() throws -> ByteBuffer? {
      switch self.state {
      case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Server is not open yet.")
      case .clientOpenServerOpen(var state):
        let response = try state.framer.next(compressor: state.compressor)
        self.state = .clientOpenServerOpen(state)
        return response
      case .clientClosedServerOpen:
        // No point in sending response if client is closed: do nothing.
        return nil
      case .clientOpenServerClosed, .clientClosedServerClosed:
        throw assertionFailureAndCreateRPCErrorOnFailedPrecondition("Can't send response if server is closed.")
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
      case .clientClosedServerOpen(var state):
        let request = state.inboundMessageBuffer.pop()
        self.state = .clientClosedServerOpen(state)
        return request
      case .clientClosedServerIdle,
          .clientIdleServerIdle,
          .clientOpenServerClosed,
          .clientClosedServerClosed:
        return nil
      }
    }
    
    private func assertionFailureAndCreateRPCErrorOnFailedPrecondition(_ message: String) -> RPCError {
      if !self.skipAssertions {
        assertionFailure(message)
      }
      return RPCError(code: .failedPrecondition, message: message)
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
  public var endpoint: MethodDescriptor? {
    get {
      self[stringValues: ":path"]
        .first(where: { _ in true })
        .flatMap { MethodDescriptor(fullyQualifiedMethod: $0) }
    }
    set {
      if let newValue {
        self.replaceOrAddString(newValue.fullyQualifiedMethod, forKey: ":path")
      } else {
        self.removeAllValues(forKey: ":path")
      }
    }
  }
  
  public var contentType: ContentType? {
    get {
      self[stringValues: "content-type"]
        .first(where: { _ in true })
        .flatMap { ContentType(value: $0) }
    }
    set {
      if let newValue {
        self.replaceOrAddString(newValue.canonicalValue, forKey: "content-type")
      } else {
        self.removeAllValues(forKey: "content-type")
      }
    }
  }
}

extension Zlib.Method {
  init?(encoding: Encoding?) {
    switch encoding {
    case .none, .identity:
      return nil
    case .deflate:
      self = .deflate
    case .gzip:
      self = .gzip
    }
  }
}
