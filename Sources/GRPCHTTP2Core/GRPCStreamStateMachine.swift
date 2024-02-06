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
  mutating func receive(message: ByteBuffer, endStream: Bool)
  
  mutating func nextRequest() throws -> ByteBuffer?
}

struct GRPCStreamStateMachineConfiguration {
  enum Party {
    case client
    case server
  }
  
  let party: Party
  let maximumPayloadSize: Int
  let compressor: Zlib.Compressor?
  let decompressor: Zlib.Decompressor?
}

fileprivate enum GRPCStreamStateMachineState {
  case clientIdleServerIdle(GRPCStreamStateMachineConfiguration)
  case clientOpenServerIdle(ClientOpenState)
  case clientOpenServerOpen(ClientOpenState)
  case clientOpenServerClosed(ClientOpenState)
  case clientClosedServerIdle(ClientOpenState)
  case clientClosedServerOpen(ClientOpenState)
  case clientClosedServerClosed

  struct ClientOpenState {
    var framer: GRPCMessageFramer
    let deframer: NIOSingleStepByteToMessageProcessor<GRPCMessageDeframer>
    var compressor: Zlib.Compressor?
    
    init(
      maximumPayloadSize: Int,
      compressor: Zlib.Compressor?,
      decompressor: Zlib.Decompressor?
    ) {
      self.framer = GRPCMessageFramer()
      let messageDeframer = GRPCMessageDeframer(
        maximumPayloadSize: maximumPayloadSize,
        decompressor: decompressor
      )
      self.deframer = NIOSingleStepByteToMessageProcessor(messageDeframer)
      self.compressor = compressor
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct GRPCStreamStateMachine {
  
  private var _stateMachine: GRPCStreamStateMachineProtocol
  
  init(configuration: GRPCStreamStateMachineConfiguration) {
    switch configuration.party {
    case .client:
      self._stateMachine = Client(configuration: configuration)
    case .server:
      self._stateMachine = Server(configuration: configuration)
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
  
  mutating func receive(message: ByteBuffer, endStream: Bool) {
    self._stateMachine.receive(message: message, endStream: endStream)
  }
  
  mutating func nextRequest() throws -> ByteBuffer? {
    try self._stateMachine.nextRequest()
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine {
  struct Client: GRPCStreamStateMachineProtocol {
    fileprivate var state: GRPCStreamStateMachineState

    init(configuration: GRPCStreamStateMachineConfiguration) {
      self.state = .clientIdleServerIdle(configuration)
    }

    mutating func send(metadata: Metadata) {
      // Client sends metadata only when opening the stream.
      // They send grpc-timeout and method name along with it.
      // TODO: should these things be validated in the handler or here?
      switch self.state {
      case .clientIdleServerIdle(let configuration):
        let clientOpenState = GRPCStreamStateMachineState.ClientOpenState(
          maximumPayloadSize: configuration.maximumPayloadSize,
          compressor: configuration.compressor,
          decompressor: configuration.decompressor
        )
        self.state = .clientOpenServerIdle(clientOpenState)
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
      case .clientIdleServerIdle(let configuration):
        preconditionFailure("Client not yet open")
      case .clientOpenServerIdle(var clientOpenState):
        clientOpenState.framer.append(message)
        if endStream {
          self.state = .clientClosedServerIdle(clientOpenState)
        } else {
          self.state = .clientOpenServerIdle(clientOpenState)
        }
      case .clientOpenServerOpen(var clientOpenState):
        clientOpenState.framer.append(message)
        if endStream {
          self.state = .clientClosedServerOpen(clientOpenState)
        } else {
          self.state = .clientOpenServerOpen(clientOpenState)
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
    mutating func nextRequest() throws -> ByteBuffer? {
      switch self.state {
      case .clientIdleServerIdle(let configuration):
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
      case .clientOpenServerOpen(let clientOpenState):
        self.state = .clientOpenServerClosed(clientOpenState)
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
      case .clientOpenServerIdle(let clientOpenState):
        self.state = .clientOpenServerOpen(clientOpenState)
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
    
    mutating func receive(message: ByteBuffer, endStream: Bool) {
      // This is a message received by the client, from the server.
      switch self.state {
      case .clientIdleServerIdle:
        preconditionFailure("Cannot have received anything from server if client is not yet open.")
      case .clientOpenServerIdle:
        preconditionFailure("Server cannot have sent a message before sending the initial metadata.")
      case .clientOpenServerOpen(let clientOpenState):
        // TODO: figure out how to do this
        try? clientOpenState.deframer.process(buffer: message, { _ in })
        if endStream {
          self.state = .clientOpenServerClosed(clientOpenState)
        }
      case .clientOpenServerClosed:
        preconditionFailure("Cannot have received anything from a closed server.")
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        preconditionFailure("Shouldn't receive anything if client's closed.")
      }
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine {
  struct Server: GRPCStreamStateMachineProtocol {
    fileprivate var state: GRPCStreamStateMachineState
    
    init(configuration: GRPCStreamStateMachineConfiguration) {
      self.state = .clientIdleServerIdle(configuration)
    }
    
    mutating func send(metadata: Metadata) {
      // Server sends initial metadata. This transitions server to open.
      switch self.state {
      case .clientIdleServerIdle:
        preconditionFailure("Client cannot be idle if server is sending initial metadata: it must have opened.")
      case .clientOpenServerIdle(let clientOpenState):
        self.state = .clientOpenServerOpen(clientOpenState)
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
      case .clientIdleServerIdle(let configuration):
        preconditionFailure("Cannot send a message when idle.")
      case .clientOpenServerIdle(let clientOpenState):
        preconditionFailure("Server must have sent initial metadata before sending a message.")
      case .clientOpenServerOpen(var clientOpenState):
        clientOpenState.framer.append(message)
        self.state = .clientOpenServerOpen(clientOpenState)
      case .clientOpenServerClosed(let clientOpenState):
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
      case .clientOpenServerOpen(let clientOpenState):
        self.state = .clientOpenServerClosed(clientOpenState)
      case .clientOpenServerClosed:
        preconditionFailure("Server is closed, can't send anything else.")
      case .clientClosedServerOpen:
        self.state = .clientClosedServerClosed
      case .clientClosedServerClosed:
        preconditionFailure("Server can't send anything if closed.")
      }
    }
    
    mutating func receive(metadata: Metadata, endStream: Bool) {
      // We validate the received headers: compression must be valid if set, and
      // grpc-timeout and method name must be present.
      // If end stream is set, the client will be closed - otherwise, it will be opened.
      guard self.hasValidHeaders(metadata) else {
        self.state = .clientClosedServerClosed
        return
      }

      switch self.state {
      case .clientIdleServerIdle(let configuration):
        let state = GRPCStreamStateMachineState.ClientOpenState(
          maximumPayloadSize: configuration.maximumPayloadSize,
          compressor: configuration.compressor,
          decompressor: configuration.decompressor
        )
        if endStream {
          self.state = .clientClosedServerIdle(state)
        } else {
          self.state = .clientOpenServerIdle(state)
        }
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
    
    mutating func receive(message: ByteBuffer, endStream: Bool) {
      switch self.state {
      case .clientIdleServerIdle(let configuration):
        preconditionFailure("Can't have received a message if client is idle.")
      case .clientOpenServerIdle(let clientOpenState):
        // TODO: figure out how to do this.
        try? clientOpenState.deframer.process(buffer: message, { _ in })
        if endStream {
          self.state = .clientClosedServerIdle(clientOpenState)
        }
      case .clientOpenServerOpen(let clientOpenState):
        // TODO: figure out how to do this.
        try? clientOpenState.deframer.process(buffer: message, { _ in })
        if endStream {
          self.state = .clientClosedServerIdle(clientOpenState)
        }
      case .clientOpenServerClosed(let clientOpenState):
        // Client is not done sending request, but server has already closed.
        // Ignore the rest of the request: do nothing.
        ()
      case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
        preconditionFailure("Client can't send a message if closed.")
      }
    }
    
    mutating func nextRequest() throws -> ByteBuffer? {
      return nil
    }
  }
}
