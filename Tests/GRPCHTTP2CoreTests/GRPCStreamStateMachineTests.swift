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
import XCTest

@testable import GRPCHTTP2Core

final class GRPCStreamClientStateMachineTests: XCTestCase {
  private let testMetadata = Metadata(dictionaryLiteral: (":path", "test/test"))
  private func makeClientStateMachine() -> GRPCStreamStateMachine {
    return GRPCStreamStateMachine(configuration: .client(maximumPayloadSize: 100), skipAssertions: true)
  }
  
  func testSendMetadataWhenIdle() throws {
    var stateMachine = makeClientStateMachine()
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
  }
  
  func testSendMetadataWhenOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open the stream
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is already open: shouldn't be sending metadata.")
    }
  }
  
  func testSendMetadataWhenClosed() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // ...and then close it.
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed: can't send metadata.")
    }
  }
  
  func testSendMessageWhenIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Try to send a message without opening (i.e. without sending initial metadata)
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client not yet open.")
    }
  }
  
  func testSendMessageWhenOpen() {
    var stateMachine = makeClientStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Now send a message
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
  }
  
  func testSendMessageWhenClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Send a message successfully
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
    
    // ...and then close it by setting END_STREAM.
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Try sending another message: it should fail
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed, cannot send a message.")
    }
  }
  
  func testSendStatusAndTrailersWhenIdle() {
    var stateMachine = makeClientStateMachine()
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testSendStatusAndTrailersWhenOpen() {
    var stateMachine = makeClientStateMachine()
    
    // Open stream
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testSendStatusAndTrailersWhenClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // ...and then close it.
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testReceiveInitialMetadataWhenIdle() {
    var stateMachine = makeClientStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Server cannot have sent metadata if the client is idle.")
    }
  }
  
  func testReceiveInitialMetadataWhenOpen() {
    var stateMachine = makeClientStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Server should open now
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
  }
  
  func testReceiveInitialMetadataWhenClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // ...and then close it.
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed, shouldn't have received anything.")
    }
  }
  
  func testReceiveEndTrailerWhenIdle() {
    var stateMachine = makeClientStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: true)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client can't have received a stream end trailer if both client and server are idle.")
    }
  }
  
  func testReceiveEndTrailerWhenOpen() {
    var stateMachine = makeClientStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
  }
  
  func testReceiveEndTrailerWhenClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // ...and then close it.
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: true)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed, shouldn't have received anything.")
    }
  }
  
  func testReceiveMessageWhenIdle() {
    
  }
  
  func testReceiveMessageWhenOpen() {
    
  }
  
  func testReceiveMessageWhenClosed() {
    
  }
  
  func testNextOutboundMessageWhenIdle() {
    
  }
  
  func testNextOutboundMessageWhenOpen() {
    
  }
  
  func testNextOutboundMessageWhenClosed() {
    
  }
  
  func testNextInboundMessageWhenIdle() {
    
  }
  
  func testNextInboundMessageWhenOpen() {
    
  }
  
  func testNextInboundMessageWhenClosed() {
    
  }
}

final class GRPCStreamServerStateMachineTests: XCTestCase {
  private func makeServerStateMachine() -> GRPCStreamStateMachine {
    return GRPCStreamStateMachine(configuration: .server(maximumPayloadSize: 100, supportedCompressionAlgorithms: []), skipAssertions: true)
  }
  
  func testSendMetadataWhenIdle() throws {
    var stateMachine = makeServerStateMachine()
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
  }
  
  func testSendMetadataWhenOpen() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open the stream
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is already open: shouldn't be sending metadata.")
    }
  }
  
  func testSendMetadataWhenClosed() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // ...and then close it.
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed: can't send metadata.")
    }
  }
  
  func testSendMessageWhenIdle() {
    var stateMachine = makeServerStateMachine()
    
    // Try to send a message without opening (i.e. without sending initial metadata)
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client not yet open.")
    }
  }
  
  func testSendMessageWhenOpen() {
    var stateMachine = makeServerStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Now send a message
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
  }
  
  func testSendMessageWhenClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Send a message successfully
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
    
    // ...and then close it by setting END_STREAM.
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Try sending another message: it should fail
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed, cannot send a message.")
    }
  }
  
  func testSendStatusAndTrailersWhenIdle() {
    var stateMachine = makeServerStateMachine()
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testSendStatusAndTrailersWhenOpen() {
    var stateMachine = makeServerStateMachine()
    
    // Open stream
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testSendStatusAndTrailersWhenClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // ...and then close it.
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testReceiveInitialMetadataWhenIdle() {
    var stateMachine = makeServerStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Server cannot have sent metadata if the client is idle.")
    }
  }
  
  func testReceiveInitialMetadataWhenOpen() {
    var stateMachine = makeServerStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Server should open now
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
  }
  
  func testReceiveInitialMetadataWhenClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open the stream...
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // ...and then close it.
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed, shouldn't have received anything.")
    }
  }
  
  func testReceiveMessageWhenIdle() {
    
  }
  
  func testReceiveMessageWhenOpen() {
    
  }
  
  func testReceiveMessageWhenClosed() {
    
  }
  
  func testNextOutboundMessageWhenIdle() {
    
  }
  
  func testNextOutboundMessageWhenOpen() {
    
  }
  
  func testNextOutboundMessageWhenClosed() {
    
  }
  
  func testNextInboundMessageWhenIdle() {
    
  }
  
  func testNextInboundMessageWhenOpen() {
    
  }
  
  func testNextInboundMessageWhenClosed() {
    
  }
}
