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

fileprivate protocol GRPCStreamStateMachineProtocol {
  var state: GRPCStreamStateMachineState { get set }

  mutating func send(metadata: Metadata)
  mutating func send(message: [UInt8], endStream: Bool)
  mutating func send(status: String, trailingMetadata: Metadata)
  
  mutating func receive(metadata: Metadata, endStream: Bool)
  mutating func receive(message: ByteBuffer, endStream: Bool) throws
  
  mutating func nextOutboundMessage() throws -> ByteBuffer?
  mutating func nextInboundMessage() -> [UInt8]?
}

enum GRPCStreamStateMachineConfiguration {
  enum CompressionAlgorithm: String {
    case identity
    case deflate
    case gzip
    
    func getZlibMethod() -> Zlib.Method? {
      switch self {
      case .identity:
        return nil
      case .deflate:
        return .deflate
      case .gzip:
        return .gzip
      }
    }
  }

  case client(maximumPayloadSize: Int)
  case server(
    maximumPayloadSize: Int,
    supportedCompressionAlgorithms: [CompressionAlgorithm]
  )
}

fileprivate enum GRPCStreamStateMachineState {
  case clientIdleServerIdle(ClientIdleServerIdleState)
  case clientOpenServerIdle(ClientOpenServerIdleState)
  case clientOpenServerOpen(ClientOpenServerOpenState)
  case clientOpenServerClosed(ClientOpenServerClosedState)
  case clientClosedServerIdle(ClientClosedServerIdleState)
  case clientClosedServerOpen(ClientClosedServerOpenState)
  case clientClosedServerClosed

  struct ClientIdleServerIdleState {
    let maximumPayloadSize: Int
  }
  
  struct ClientOpenServerIdleState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    
    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>
    var decompressor: Zlib.Decompressor?
    
    var messageBuffer: OneOrManyQueue<[UInt8]>
    
    init(
      previousState: ClientIdleServerIdleState,
      compressionAlgorithm: GRPCStreamStateMachineConfiguration.CompressionAlgorithm?
    ) {
      if let zlibMethod = compressionAlgorithm?.getZlibMethod() {
        self.compressor = Zlib.Compressor(method: zlibMethod)
        self.decompressor = Zlib.Decompressor(method: zlibMethod)
      }
      
      self.framer = GRPCMessageFramer()
      let decoder = GRPCMessageDeframer(
        maximumPayloadSize: previousState.maximumPayloadSize,
        decompressor: self.decompressor
      )
      self.deframer = NIOSingleStepByteToMessageProcessor(decoder)
      
      self.messageBuffer = .init()
    }
  }
  
  struct ClientOpenServerOpenState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    
    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>
    var decompressor: Zlib.Decompressor?
    
    var messageBuffer: OneOrManyQueue<[UInt8]>
    
    init(previousState: ClientOpenServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
      self.messageBuffer = previousState.messageBuffer
    }
  }
  
  struct ClientOpenServerClosedState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    
    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>
    var decompressor: Zlib.Decompressor?
    
    var messageBuffer: OneOrManyQueue<[UInt8]>
    
    init(previousState: ClientOpenServerOpenState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
      self.messageBuffer = previousState.messageBuffer
    }
  }
  
  struct ClientClosedServerIdleState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    
    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>
    var decompressor: Zlib.Decompressor?
    
    init(previousState: ClientOpenServerIdleState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
    }
  }
  
  struct ClientClosedServerOpenState {
    var framer: GRPCMessageFramer
    var compressor: Zlib.Compressor?
    
    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>
    var decompressor: Zlib.Decompressor?
    
    var messageBuffer: OneOrManyQueue<[UInt8]>
    
    init(previousState: ClientOpenServerOpenState) {
      self.framer = previousState.framer
      self.compressor = previousState.compressor
      self.deframer = previousState.deframer
      self.decompressor = previousState.decompressor
      self.messageBuffer = previousState.messageBuffer
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct GRPCStreamStateMachine {
  private var _stateMachine: GRPCStreamStateMachineProtocol
  
  init(configuration: GRPCStreamStateMachineConfiguration) {
    switch configuration {
    case .client(let maximumPayloadSize):
      self._stateMachine = Client(maximumPayloadSize: maximumPayloadSize)
    case .server(let maximumPayloadSize, let supportedCompressionAlgorithms):
      self._stateMachine = Server(
        maximumPayloadSize: maximumPayloadSize,
        supportedCompressionAlgorithms: supportedCompressionAlgorithms
      )
    }
  }
  
  mutating func send(metadata: Metadata) {
    self._stateMachine.send(metadata: metadata)
  }
  
  mutating func send(message: [UInt8], endStream: Bool) {
    self._stateMachine.send(message: message, endStream: endStream)
  }
  
  mutating func send(status: String, trailingMetadata: Metadata) {
    self._stateMachine.send(status: status, trailingMetadata: trailingMetadata)
  }
  
  mutating func receive(metadata: Metadata, endStream: Bool) {
    self._stateMachine.receive(metadata: metadata, endStream: endStream)
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

    init(maximumPayloadSize: Int) {
      self.state = .clientIdleServerIdle(.init(maximumPayloadSize: maximumPayloadSize))
    }

    mutating func send(metadata: Metadata) {
      // Client sends metadata only when opening the stream.
      // They send grpc-timeout and method name along with it.
      // TODO: should these things be validated in the handler or here?
      
      let compressionAlgorithm = GRPCStreamStateMachineConfiguration.CompressionAlgorithm(rawValue: metadata.encoding ?? "")
      
      switch self.state {
      case .clientIdleServerIdle(let state):
        self.state = .clientOpenServerIdle(.init(
          previousState: state,
          compressionAlgorithm: compressionAlgorithm
        ))
      case .clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed:
        // Client is already open: we shouldn't be sending metadata.
        preconditionFailure("Invalid state: client is already open")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        // Client is closed: we shouldn't be sending metadata again.
        preconditionFailure("Invalid state: client is closed")
      }
    }

    mutating func send(message: [UInt8], endStream: Bool) {
      // Client sends message.
      switch self.state {
      case .clientIdleServerIdle:
        preconditionFailure("Client not yet open")
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
      case .clientOpenServerClosed:
        // The server has closed, so it makes no sense to send the rest of the request.
        // Do nothing.
        ()
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        preconditionFailure("Client is closed, cannot send a message")
      }
    }
    
    mutating func send(status: String, trailingMetadata: Metadata) {
      // Nothing to do: only server send status and trailing metadata.
    }
    
    /// Returns the client's next request to the server.
    /// - Returns: The request to be made to the server.
    mutating func nextOutboundMessage() throws -> ByteBuffer? {
      switch self.state {
      case .clientIdleServerIdle:
        preconditionFailure("Client is not open yet.")
      case .clientOpenServerIdle(var clientOpenState):
        let request = try clientOpenState.framer.next(compressor: clientOpenState.compressor)
        self.state = .clientOpenServerIdle(clientOpenState)
        return request
      case .clientOpenServerOpen(var clientOpenState):
        let request = try clientOpenState.framer.next(compressor: clientOpenState.compressor)
        self.state = .clientOpenServerOpen(clientOpenState)
        return request
      case .clientOpenServerClosed:
        // Nothing to do: no point in sending request if server is closed.
        return nil
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        preconditionFailure("Can't send request if client is closed")
      }
    }
    
    mutating func receive(metadata: Metadata, endStream: Bool) {
      // This is metadata received by the client from the server.
      // It can be initial, which confirms that the server is now open;
      // or an END_STREAM trailer, meaning the response is over.
      if endStream {
        self.clientReceivedEndHeader()
      } else {
        self.clientReceivedMetadata()
      }
    }
    
    mutating func clientReceivedEndHeader() {
      switch self.state {
      case .clientIdleServerIdle:
        preconditionFailure("Client can't have received a stream end trailer if both client and server are idle.")
      case .clientOpenServerIdle:
        preconditionFailure("Server cannot have sent an end stream header if it is still idle.")
      case .clientOpenServerOpen(let state):
        self.state = .clientOpenServerClosed(.init(previousState: state))
      case .clientOpenServerClosed:
        preconditionFailure("Server is already closed, can't have received the end stream trailer twice.")
      case .clientClosedServerIdle:
        preconditionFailure("Server cannot have sent end stream trailer if it is idle.")
      case .clientClosedServerOpen:
        self.state = .clientClosedServerClosed
      case .clientClosedServerClosed:
        preconditionFailure("Server cannot have sent end stream trailer if it is already closed.")
      }
    }
    
    mutating func clientReceivedMetadata() {
      switch self.state {
      case .clientIdleServerIdle:
        preconditionFailure("Server cannot have sent metadata if the client is idle.")
      case .clientOpenServerIdle(let state):
        self.state = .clientOpenServerOpen(.init(previousState: state))
      case .clientOpenServerOpen:
        // This state is valid: server can send trailing metadata without END_STREAM
        // set, and follow it with an empty message frame where the flag *is* set.
        // Do nothing in this case.
        ()
      case .clientOpenServerClosed, .clientClosedServerClosed:
        preconditionFailure("Server is closed, nothing could have been sent.")
      case .clientClosedServerIdle, .clientClosedServerOpen:
        preconditionFailure("Client is closed, cannot have received anything.")
        ()
      }
    }
    
    mutating func receive(message: ByteBuffer, endStream: Bool) throws {
      // This is a message received by the client, from the server.
      switch self.state {
      case .clientIdleServerIdle:
        preconditionFailure("Cannot have received anything from server if client is not yet open.")
      case .clientOpenServerIdle:
        preconditionFailure("Server cannot have sent a message before sending the initial metadata.")
      case .clientOpenServerOpen(var state):
        try state.deframer.process(buffer: message) { deframedMessage in
          state.messageBuffer.append(deframedMessage)
        }
        if endStream {
          self.state = .clientOpenServerClosed(.init(previousState: state))
        } else {
          self.state = .clientOpenServerOpen(state)
        }
      case .clientOpenServerClosed:
        preconditionFailure("Cannot have received anything from a closed server.")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        preconditionFailure("Shouldn't receive anything if client's closed.")
      }
    }
    
    mutating func nextInboundMessage() -> [UInt8]? {
      switch self.state {
      case .clientOpenServerOpen(var state):
        let message = state.messageBuffer.pop()
        self.state = .clientOpenServerOpen(state)
        return message
      case .clientOpenServerClosed(var state):
        let message = state.messageBuffer.pop()
        self.state = .clientOpenServerClosed(state)
        return message
      case .clientOpenServerIdle, 
          .clientIdleServerIdle, 
          .clientClosedServerIdle,
          .clientClosedServerOpen,
          .clientClosedServerClosed:
        return nil
      }
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine {
  struct Server: GRPCStreamStateMachineProtocol {
    typealias SupportedCompressionAlgorithms = [GRPCStreamStateMachineConfiguration.CompressionAlgorithm]
    fileprivate var state: GRPCStreamStateMachineState
    let supportedCompressionAlgorithms: SupportedCompressionAlgorithms
    
    init(
      maximumPayloadSize: Int,
      supportedCompressionAlgorithms: SupportedCompressionAlgorithms
    ) {
      self.state = .clientIdleServerIdle(.init(maximumPayloadSize: maximumPayloadSize))
      self.supportedCompressionAlgorithms = supportedCompressionAlgorithms
    }
    
    mutating func send(metadata: Metadata) {
      // Server sends initial metadata. This transitions server to open.
      switch self.state {
      case .clientIdleServerIdle:
        preconditionFailure("Client cannot be idle if server is sending initial metadata: it must have opened.")
      case .clientOpenServerIdle(let state):
        self.state = .clientOpenServerOpen(.init(previousState: state))
      case .clientOpenServerOpen:
        preconditionFailure("Server has already sent initial metadata.")
      case .clientOpenServerClosed:
        preconditionFailure("Server cannot send metadata if closed.")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        preconditionFailure("No point in sending initial metadata if client is closed.")
      }
    }
    
    mutating func send(message: [UInt8], endStream: Bool) {
      switch self.state {
      case .clientIdleServerIdle:
        preconditionFailure("Cannot send a message when idle.")
      case .clientOpenServerIdle:
        preconditionFailure("Server must have sent initial metadata before sending a message.")
      case .clientOpenServerOpen(var state):
        state.framer.append(message)
        self.state = .clientOpenServerOpen(state)
      case .clientOpenServerClosed:
        preconditionFailure("Server can't send a message if it's closed.")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        preconditionFailure("Server can't send a message to a closed client.")
      }
    }
    
    mutating func send(status: String, trailingMetadata: Metadata) {
      // Close the server.
      switch self.state {
      case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
        preconditionFailure("Server can't send anything if idle.")
      case .clientOpenServerOpen(let state):
        self.state = .clientOpenServerClosed(.init(previousState: state))
      case .clientOpenServerClosed:
        preconditionFailure("Server is closed, can't send anything else.")
      case .clientClosedServerOpen:
        self.state = .clientClosedServerClosed
      case .clientClosedServerClosed:
        preconditionFailure("Server can't send anything if closed.")
      }
    }
    
    mutating func receive(metadata: Metadata, endStream: Bool) {
      if endStream {
        preconditionFailure("Client should have opened before ending the stream: stream shouldn't have been closed when sending initial metadata.")
      }
        
      // We validate the received headers: compression must be valid if set, and
      // grpc-timeout and method name must be present.
      // If end stream is set, the client will be closed - otherwise, it will be opened.
      guard self.hasValidHeaders(metadata) else {
        self.state = .clientClosedServerClosed
        return
      }

      switch self.state {
      case .clientIdleServerIdle(let state):
        self.state = .clientOpenServerIdle(.init(
          previousState: state,
          compressionAlgorithm: GRPCStreamStateMachineConfiguration.CompressionAlgorithm(rawValue: metadata.encoding ?? "")
        ))
      case .clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed:
        preconditionFailure("Client shouldn't have sent metadata twice.")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        preconditionFailure("Client can't have sent metadata if closed.")
      }
    }
    
    private func hasValidHeaders(_ metadata: Metadata) -> Bool {
      // TODO: validate grpc-timeout and method name are present, content type, compression if present. 
      return false
    }
    
    mutating func receive(message: ByteBuffer, endStream: Bool) throws {
      switch self.state {
      case .clientIdleServerIdle:
        preconditionFailure("Can't have received a message if client is idle.")
      case .clientOpenServerIdle(var state):
        try state.deframer.process(buffer: message) { deframedMessage in
          state.messageBuffer.append(deframedMessage)
        }
        
        if endStream {
          self.state = .clientClosedServerIdle(.init(previousState: state))
        } else {
          self.state = .clientOpenServerIdle(state)
        }
      case .clientOpenServerOpen(var state):
        try state.deframer.process(buffer: message) { deframedMessage in
          state.messageBuffer.append(deframedMessage)
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
        preconditionFailure("Client can't send a message if closed.")
      }
    }
    
    mutating func nextOutboundMessage() throws -> ByteBuffer? {
      switch self.state {
      case .clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle:
        throw assertionFailureAndCreateRPCError(
          errorCode: .failedPrecondition,
          message: "Server is not open yet."
        )
      case .clientOpenServerOpen(var state):
        let response = try state.framer.next(compressor: state.compressor)
        self.state = .clientOpenServerOpen(state)
        return response
      case .clientClosedServerOpen:
        // No point in sending response if client is closed: do nothing.
        return nil
      case .clientOpenServerClosed, .clientClosedServerClosed:
        throw assertionFailureAndCreateRPCError(
          errorCode: .failedPrecondition,
          message: "Can't send response if server is closed."
        )
      }
    }
    
    mutating func nextInboundMessage() -> [UInt8]? {
      switch self.state {
      case .clientOpenServerIdle(var state):
        let request = state.messageBuffer.pop()
        self.state = .clientOpenServerIdle(state)
        return request
      case .clientOpenServerOpen(var state):
        let request = state.messageBuffer.pop()
        self.state = .clientOpenServerOpen(state)
        return request
      case .clientClosedServerOpen(var state):
        let request = state.messageBuffer.pop()
        self.state = .clientClosedServerOpen(state)
        return request
      case .clientClosedServerIdle,
          .clientIdleServerIdle,
          .clientOpenServerClosed,
          .clientClosedServerClosed:
        return nil
      }
    }
  }
}

fileprivate func assertionFailureAndCreateRPCError(errorCode: RPCError.Code, message: String) -> RPCError {
  assertionFailure(message)
  return RPCError(code: errorCode, message: message)
}
