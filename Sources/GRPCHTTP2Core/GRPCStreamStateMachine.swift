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

// TODO: this is all done from client's perspective for now - work on server-side later.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct GRPCStreamStateMachine {
  struct Configuration {
    let maximumPayloadSize: Int
    let compressor: Zlib.Compressor?
    let decompressor: Zlib.Decompressor?
  }

  private var state: State
  
  enum State {
    case clientIdleServerIdle(Configuration)
    case clientOpenServerIdle(ClientOpenState)
    case clientOpenServerOpen(ClientOpenState)
    case clientOpenServerClosed(ClientOpenState)
    case clientClosedServerIdle
    case clientClosedServerOpen
    case clientClosedServerClosed
  }
  
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
  
  init(configuration: Configuration) {
    self.state = .clientIdleServerIdle(configuration)
  }
  
  mutating func send(metadata: Metadata) throws {
    // Client only sends metadata when opening.
    try self.clientSentMetadata()
  }
  
  mutating func send(message: [UInt8]) {
    // Client sends message.
    switch self.state {
    case .clientIdleServerIdle(let configuration):
      preconditionFailure("Client not yet open")
    case .clientOpenServerIdle(var clientOpenState):
      clientOpenState.framer.append(message)
      self.state = .clientOpenServerClosed(clientOpenState)
    case .clientOpenServerOpen(var clientOpenState):
      clientOpenState.framer.append(message)
      self.state = .clientOpenServerClosed(clientOpenState)
    case .clientOpenServerClosed:
      // Nothing to do: no point in sending a message if the server's closed.
      ()
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      preconditionFailure("Client is closed, cannot send a message")
    }
  }
  
  mutating func send(status: String, trailingMetadata: Metadata) throws {
    // Only server does this.
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
  
  mutating func receive(message: ByteBuffer, messageProcessor: ([UInt8]) throws -> Void) throws {
    // This is a message received by the client, from the server.
    switch self.state {
    case .clientIdleServerIdle(let configuration):
      preconditionFailure("Cannot have received anything from server if client is not yet open.")
    case .clientOpenServerIdle(let clientOpenState):
      preconditionFailure("Server cannot have sent a message before sending the initial metadata.")
    case .clientOpenServerOpen(let clientOpenState):
      try clientOpenState.deframer.process(buffer: message, messageProcessor)
    case .clientOpenServerClosed:
      preconditionFailure("Cannot have received anything from a closed server.")
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      preconditionFailure("Shouldn't receive anything if client's closed.")
    }
  }
  
  // - MARK: Client-opening transitions

  mutating func clientSentMetadata() throws {
    // Client sends metadata only when opening the stream.
    // They send grpc-timeout and method name along with it.
    // TODO: should these things be validated in the handler or here?
    switch self.state {
    case .clientIdleServerIdle(let configuration):
      let clientOpenState = ClientOpenState(
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
  
  // - MARK: Client-closing transitions
  
  mutating func clientSentEnd() throws {
    switch self.state {
    case .clientIdleServerIdle:
      self.state = .clientClosedServerIdle
    case .clientOpenServerIdle:
      self.state = .clientClosedServerIdle
    case .clientOpenServerOpen:
      self.state = .clientClosedServerOpen
    case .clientOpenServerClosed:
      self.state = .clientClosedServerClosed
    case .clientClosedServerIdle, .clientClosedServerOpen, .clientClosedServerClosed:
      // TODO: think what to do
      preconditionFailure("Client cannot have sent anything if it's closed.")
    }
  }
  
  // - MARK: Server-opening transitions
  
  mutating func clientReceivedMetadata() {
    switch self.state {
    case .clientIdleServerIdle:
      preconditionFailure("Server cannot have sent metadata if the client is idle.")
    case .clientOpenServerIdle(let clientOpenState):
      self.state = .clientOpenServerOpen(clientOpenState)
    case .clientOpenServerOpen:
      // Do nothing
      ()
    case .clientOpenServerClosed, .clientClosedServerClosed:
      preconditionFailure("Server is closed, nothing could have been sent.")
    case .clientClosedServerIdle, .clientClosedServerOpen:
      preconditionFailure("Client is closed, cannot have received anything.")
      ()
    }
  }
  
  // - MARK: Server-closing transitions
  
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
}
