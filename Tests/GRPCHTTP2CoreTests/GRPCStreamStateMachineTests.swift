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
import NIOCore

@testable import GRPCHTTP2Core

final class GRPCStreamClientStateMachineTests: XCTestCase {
  private let testMetadata: Metadata = [":path": "test/test"]
  private let testMetadataWithDeflateCompression: Metadata = [
    ":path": "test/test",
    "grpc-encoding": "deflate"
  ]
  
  private func makeClientStateMachine() -> GRPCStreamStateMachine {
    GRPCStreamStateMachine(
      configuration: .client(maximumPayloadSize: 100),
      skipAssertions: true
    )
  }
  
  // - MARK: Send Metadata

  func testSendMetadataWhenClientIdleAndServerIdle() throws {
    var stateMachine = makeClientStateMachine()
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
  }
  
  func testSendMetadataWhenClientOpenAndServerIdle() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is already open: shouldn't be sending metadata.")
    }
  }
  
  func testSendMetadataWhenClientOpenAndServerOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is already open: shouldn't be sending metadata.")
    }
  }
  
  func testSendMetadataWhenClientOpenAndServerClosed() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is already open: shouldn't be sending metadata.")
    }
  }
  
  func testSendMetadataWhenClientClosedAndServerIdle() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed: can't send metadata.")
    }
  }
  
  func testSendMetadataWhenClientClosedAndServerOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed: can't send metadata.")
    }
  }
  
  func testSendMetadataWhenClientClosedAndServerClosed() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed: can't send metadata.")
    }
  }
  
  // - MARK: Send Message

  func testSendMessageWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Try to send a message without opening (i.e. without sending initial metadata)
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client not yet open.")
    }
  }
  
  func testSendMessageWhenClientOpenAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Now send a message
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
  }
  
  func testSendMessageWhenClientOpenAndServerOpen() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Now send a message
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
  }
  
  func testSendMessageWhenClientOpenAndServerClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    // Now send a message
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
  }
  
  func testSendMessageWhenClientClosedAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Try sending another message: it should fail
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed, cannot send a message.")
    }
  }
  
  func testSendMessageWhenClientClosedAndServerOpen() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Try sending another message: it should fail
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed, cannot send a message.")
    }
  }
  
  func testSendMessageWhenClientClosedAndServerClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    // Try sending another message: it should fail
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed, cannot send a message.")
    }
  }
  
  // - MARK: Send Status and Trailers
  
  func testSendStatusAndTrailersWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientOpenAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientOpenAndServerOpen() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientOpenAndServerClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open stream
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientClosedAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientClosedAndServerOpen() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientClosedAndServerClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: "test", trailingMetadata: .init())) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  // - MARK: Receive initial metadata
    
  func testReceiveInitialMetadataWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Server cannot have sent metadata if the client is idle.")
    }
  }
  
  func testReceiveInitialMetadataWhenClientOpenAndServerIdle() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    let action = try stateMachine.receive(metadata: .init(), endStream: false)
    guard case .doNothing = action else {
      XCTFail("Expected action to be doNothing")
      return
    }
  }
  
  func testReceiveInitialMetadataWhenClientOpenAndServerOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Try opening server again
    let action = try stateMachine.receive(metadata: .init(), endStream: false)
    guard case .doNothing = action else {
      XCTFail("Expected action to be doNothing")
      return
    }
  }
  
  func testReceiveInitialMetadataWhenClientOpenAndServerClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Server is closed, nothing could have been sent.")
    }
  }
  
  func testReceiveInitialMetadataWhenClientClosedAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed, shouldn't have received anything.")
    }
  }
  
  func testReceiveInitialMetadataWhenClientClosedAndServerOpen() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed, shouldn't have received anything.")
    }
  }
  
  func testReceiveInitialMetadataWhenClientClosedAndServerClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is closed, shouldn't have received anything.")
    }
  }
  
  // - MARK: Receive end trailers
  
  func testReceiveEndTrailerWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Receive an end trailer
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: true)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client can't have received a stream end trailer if both client and server are idle.")
    }
  }
  
  func testReceiveEndTrailerWhenClientOpenAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Receive an end trailer
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: true)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Server cannot have sent an end stream header if it is still idle.")
    }
  }
  
  func testReceiveEndTrailerWhenClientOpenAndServerOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Receive an end trailer
    let action = try stateMachine.receive(metadata: .init(), endStream: true)
    guard case .doNothing = action else {
      XCTFail("Expected action to be doNothing")
      return
    }
  }
  
  func testReceiveEndTrailerWhenClientOpenAndServerClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    // Receive another end trailer
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: true)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Server is already closed, can't have received the end stream trailer twice.")
    }
  }
  
  func testReceiveEndTrailerWhenClientClosedAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Closing the server now should throw
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: true)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Server cannot have sent end stream trailer if it is idle.")
    }
  }
  
  func testReceiveEndTrailerWhenClientClosedAndServerOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close the client stream
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Closing the server now should not throw
    let action = try stateMachine.receive(metadata: .init(), endStream: true)
    guard case .doNothing = action else {
      XCTFail("Expected action to be doNothing")
      return
    }
  }
  
  func testReceiveEndTrailerWhenClientClosedAndServerClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    // Closing the server again should throw
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: true)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Server cannot have sent end stream trailer if it is already closed.")
    }
  }
  
  // - MARK: Receive message
  
  func testReceiveMessageWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Cannot have received anything from server if client is not yet open.")
    }
  }
  
  func testReceiveMessageWhenClientOpenAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Server cannot have sent a message before sending the initial metadata.")
    }
  }
  
  func testReceiveMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: false))
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
  }
  
  func testReceiveMessageWhenClientOpenAndServerClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Cannot have received anything from a closed server.")
    }
  }
  
  func testReceiveMessageWhenClientClosedAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Server cannot have sent a message before sending the initial metadata.")
    }
  }
  
  func testReceiveMessageWhenClientClosedAndServerOpen() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: false))
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
  }
  
  func testReceiveMessageWhenClientClosedAndServerClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Shouldn't have received anything if both client and server are closed.")
    }
  }
  
  // - MARK: Next outbound message
  
  func testNextOutboundMessageWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.nextOutboundMessage()) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Client is not open yet.")
    }
  }
  
  func testNextOutboundMessageWhenClientOpenAndServerIdle() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    var request = try stateMachine.nextOutboundMessage()
    XCTAssertNil(request)
    
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))
    request = try XCTUnwrap(stateMachine.nextOutboundMessage())
    
    let expectedBytes: [UInt8] = [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42 // original message
    ]
    XCTAssertEqual(Array(buffer: request!), expectedBytes)
  }
  
  func testNextOutboundMessageWhenClientOpenAndServerIdle_WithCompression() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadataWithDeflateCompression))
    
    var request = try stateMachine.nextOutboundMessage()
    XCTAssertNil(request)
    
    let originalMessage = [UInt8]([42, 42, 43, 43])
    XCTAssertNoThrow(try stateMachine.send(message: originalMessage, endStream: false))
    request = try XCTUnwrap(stateMachine.nextOutboundMessage())
    
    var framer = GRPCMessageFramer()
    let compressor = Zlib.Compressor(method: .deflate)
    defer { compressor.end() }
    framer.append(originalMessage)
    
    let framedMessage = try XCTUnwrap(framer.next(compressor: compressor))
    let expectedBytes = Array(buffer: framedMessage)
    XCTAssertEqual(Array(buffer: request!), expectedBytes)
  }
  
  func testNextOutboundMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    var request = try stateMachine.nextOutboundMessage()
    XCTAssertNil(request)
    
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))
    request = try XCTUnwrap(stateMachine.nextOutboundMessage())
    
    let expectedBytes: [UInt8] = [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42 // original message
    ]
    XCTAssertEqual(Array(buffer: request!), expectedBytes)
  }
  
  func testNextOutboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadataWithDeflateCompression))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    var request = try stateMachine.nextOutboundMessage()
    XCTAssertNil(request)
    
    let originalMessage = [UInt8]([42, 42, 43, 43])
    XCTAssertNoThrow(try stateMachine.send(message: originalMessage, endStream: false))
    request = try XCTUnwrap(stateMachine.nextOutboundMessage())
    
    var framer = GRPCMessageFramer()
    let compressor = Zlib.Compressor(method: .deflate)
    defer { compressor.end() }
    framer.append(originalMessage)
    
    let framedMessage = try XCTUnwrap(framer.next(compressor: compressor))
    let expectedBytes = Array(buffer: framedMessage)
    XCTAssertEqual(Array(buffer: request!), expectedBytes)
  }
  
  func testNextOutboundMessageWhenClientOpenAndServerClosed() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    // No messages to send, so make sure nil is returned
    XCTAssertNil(try stateMachine.nextOutboundMessage())
    
    // Queue a message, but assert the next outbound message is nil nevertheless,
    // because the server is closed.
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))
    XCTAssertNil(try stateMachine.nextOutboundMessage())
  }

  func testNextOutboundMessageWhenClientClosedAndServerIdle() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Send a message and close client
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: true))
    
    // Make sure that getting the next outbound message _does_ return the message
    // we have enqueued.
    let request = try XCTUnwrap(stateMachine.nextOutboundMessage())
    let expectedBytes: [UInt8] = [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42 // original message
    ]
    XCTAssertEqual(Array(buffer: request), expectedBytes)
    
    // And then make sure that nothing else is returned anymore
    XCTAssertNil(try stateMachine.nextOutboundMessage())
  }
  
  func testNextOutboundMessageWhenClientClosedAndServerOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Send a message and close client
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: true))
    
    // Make sure that getting the next outbound message _does_ return the message
    // we have enqueued.
    let request = try XCTUnwrap(stateMachine.nextOutboundMessage())
    let expectedBytes: [UInt8] = [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42 // original message
    ]
    XCTAssertEqual(Array(buffer: request), expectedBytes)
    
    // And then make sure that nothing else is returned anymore
    XCTAssertNil(try stateMachine.nextOutboundMessage())
  }
  
  func testNextOutboundMessageWhenClientClosedAndServerClosed() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Send a message
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Even though we have enqueued a message, don't send it, because the server
    // is closed.
    XCTAssertNil(try stateMachine.nextOutboundMessage())
  }
  
  // - MARK: Next inbound message
  
  func testNextInboundMessageWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientOpenAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    let receivedBytes = ByteBuffer(bytes: [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42 // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)
    
    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])
    
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadataWithDeflateCompression))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    let originalMessage = [UInt8]([42, 42, 43, 43])
    var framer = GRPCMessageFramer()
    let compressor = Zlib.Compressor(method: .deflate)
    defer { compressor.end() }
    framer.append(originalMessage)
    let receivedBytes = try framer.next(compressor: compressor)!
    
    try stateMachine.receive(message: receivedBytes, endStream: false)
    
    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, originalMessage)
    
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientOpenAndServerClosed() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    let receivedBytes = ByteBuffer(bytes: [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42 // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])
    
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientClosedAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // If server is idle it means we never got any messages, assert no inbound
    // message is present.
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientClosedAndServerOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    let receivedBytes = ByteBuffer(bytes: [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42 // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Even though the client is closed, because it received a message while open,
    // we must get the message now.
    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])
    
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientClosedAndServerClosed() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    let receivedBytes = ByteBuffer(bytes: [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42 // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)
    
    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Even though the client is closed, because it received a message while open,
    // we must get the message now.
    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])
    
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
}

final class GRPCStreamServerStateMachineTests: XCTestCase {
  private func makeServerStateMachine() -> GRPCStreamStateMachine {
    return GRPCStreamStateMachine(configuration: .server(maximumPayloadSize: 100, supportedCompressionAlgorithms: []), skipAssertions: true)
  }
  
}
