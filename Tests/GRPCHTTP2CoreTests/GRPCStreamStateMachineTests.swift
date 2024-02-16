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
import NIOHPACK

@testable import GRPCHTTP2Core

final class GRPCStreamClientStateMachineTests: XCTestCase {
  private let testMetadata: Metadata = []
  
  private func makeClientStateMachine() -> GRPCStreamStateMachine {
    GRPCStreamStateMachine(
      configuration: .client(
        methodDescriptor: .init(service: "test", method: "test"),
        scheme: .http,
        maximumPayloadSize: 100,
        outboundEncoding: nil,
        acceptedEncodings: [.deflate]
      ),
      skipAssertions: true
    )
  }
  
  private func makeClientStateMachineWithCompression() -> GRPCStreamStateMachine {
    GRPCStreamStateMachine(
      configuration: .client(
        methodDescriptor: .init(service: "test", method: "test"),
        scheme: .http,
        maximumPayloadSize: 100,
        outboundEncoding: .deflate,
        acceptedEncodings: [.deflate]
      ),
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
      XCTAssertEqual(error.code, .internalError)
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
      XCTAssertEqual(error.code, .internalError)
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
      XCTAssertEqual(error.code, .internalError)
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
      XCTAssertEqual(error.code, .internalError)
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
      XCTAssertEqual(error.code, .internalError)
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
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client is closed: can't send metadata.")
    }
  }
  
  // - MARK: Send Message

  func testSendMessageWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Try to send a message without opening (i.e. without sending initial metadata)
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
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
      XCTAssertEqual(error.code, .internalError)
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
      XCTAssertEqual(error.code, .internalError)
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
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client is closed, cannot send a message.")
    }
  }
  
  // - MARK: Send Status and Trailers
  
  func testSendStatusAndTrailersWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: Status(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientOpenAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // This operation is never allowed on the client.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: Status(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
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
                         try stateMachine.send(status: Status(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
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
                         try stateMachine.send(status: Status(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
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
                         try stateMachine.send(status: Status(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
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
                         try stateMachine.send(status: Status(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
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
                         try stateMachine.send(status: Status(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client cannot send status and trailer.")
    }
  }
  
  // - MARK: Receive initial metadata
    
  func testReceiveInitialMetadataWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server cannot have sent metadata if the client is idle.")
    }
  }
  
  func testReceiveInitialMetadataWhenClientOpenAndServerIdle() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Receive metadata = open server
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
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is closed, nothing could have been sent.")
    }
  }
  
  func testReceiveInitialMetadataWhenClientClosedAndServerIdle() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Receive metadata = open server
    let action = try stateMachine.receive(metadata: .init(), endStream: false)
    guard case .doNothing = action else {
      XCTFail("Expected action to be doNothing")
      return
    }
  }
  
  func testReceiveInitialMetadataWhenClientClosedAndServerOpen() throws {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Receive metadata = open server
    let action = try stateMachine.receive(metadata: .init(), endStream: false)
    guard case .doNothing = action else {
      XCTFail("Expected action to be doNothing")
      return
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
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is closed, nothing could have been sent.")
    }
  }
  
  // - MARK: Receive end trailers
  
  func testReceiveEndTrailerWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Receive an end trailer
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: .init(), endStream: true)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server cannot have sent metadata if the client is idle.")
    }
  }
  
  func testReceiveEndTrailerWhenClientOpenAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Receive a trailer-only response
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
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
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is closed, nothing could have been sent.")
    }
  }
  
  func testReceiveEndTrailerWhenClientClosedAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Server sends a trailers-only response
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
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
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is closed, nothing could have been sent.")
    }
  }
  
  // - MARK: Receive message
  
  func testReceiveMessageWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Cannot have received anything from server if client is not yet open.")
    }
  }
  
  func testReceiveMessageWhenClientOpenAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
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
      XCTAssertEqual(error.code, .internalError)
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
      XCTAssertEqual(error.code, .internalError)
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
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Shouldn't have received anything if both client and server are closed.")
    }
  }
  
  // - MARK: Next outbound message
  
  func testNextOutboundMessageWhenClientIdleAndServerIdle() {
    var stateMachine = makeClientStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.nextOutboundMessage()) { error in
      XCTAssertEqual(error.code, .internalError)
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
    var stateMachine = makeClientStateMachineWithCompression()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
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
    var stateMachine = makeClientStateMachineWithCompression()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
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
    var stateMachine = makeClientStateMachineWithCompression()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.send(metadata: self.testMetadata))
    
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
  private let receivedHeaders: HPACKHeaders = [
    ":path": "test/test",
    "content-type": "application/grpc"
  ]
  private let receivedHeadersWithDeflateCompression: HPACKHeaders = [
    ":path": "test/test",
    "content-type": "application/grpc",
    "grpc-encoding": "deflate"
  ]
  private let receivedHeadersWithoutContentType: HPACKHeaders = [":path": "test/test"]
  private let receivedHeadersWithInvalidContentType: HPACKHeaders = ["content-type": "invalid/invalid"]
  private let receivedHeadersWithoutEndpoint: HPACKHeaders = ["content-type": "application/grpc"]
  
  private func makeServerStateMachine() -> GRPCStreamStateMachine {
    GRPCStreamStateMachine(
      configuration: .server(
        scheme: .http,
        maximumPayloadSize: 100,
        acceptedEncodings: []
      ),
      skipAssertions: true
    )
  }
  
  private func makeServerStateMachineWithCompression() -> GRPCStreamStateMachine {
    GRPCStreamStateMachine(
      configuration: .server(
        scheme: .http,
        maximumPayloadSize: 100,
        acceptedEncodings: [.deflate]
      ),
      skipAssertions: true
    )
  }
  
  // - MARK: Send Metadata

  func testSendMetadataWhenClientIdleAndServerIdle() throws {
    var stateMachine = makeServerStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self, 
                         try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client cannot be idle if server is sending initial metadata: it must have opened.")
    }
  }
  
  func testSendMetadataWhenClientOpenAndServerIdle() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
  }
  
  func testSendMetadataWhenClientOpenAndServerOpen() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, 
                         try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server has already sent initial metadata.")
    }
  }
  
  func testSendMetadataWhenClientOpenAndServerClosed() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server cannot send metadata if closed.")
    }
  }
  
  func testSendMetadataWhenClientClosedAndServerIdle() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // We should be allowed to send initial metadata if client is closed:
    // client may be finished sending request but may still be awaiting response.
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
  }
  
  func testSendMetadataWhenClientClosedAndServerOpen() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server has already sent initial metadata.")
    }
  }
  
  func testSendMetadataWhenClientClosedAndServerClosed() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: .init(), endStream: true))
    
    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server cannot send metadata if closed.")
    }
  }
  
  // - MARK: Send Message

  func testSendMessageWhenClientIdleAndServerIdle() {
    var stateMachine = makeServerStateMachine()

    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server must have sent initial metadata before sending a message.")
    }
  }
  
  func testSendMessageWhenClientOpenAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Now send a message
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server must have sent initial metadata before sending a message.")
    }
  }
  
  func testSendMessageWhenClientOpenAndServerOpen() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Now send a message
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
  }
  
  func testSendMessageWhenClientOpenAndServerClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Try sending another message: it should fail
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send a message if it's closed.")
    }
  }
  
  func testSendMessageWhenClientClosedAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server must have sent initial metadata before sending a message.")
    }
  }
  
  func testSendMessageWhenClientClosedAndServerOpen() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Try sending a message: even though client is closed, we should send it
    // because it may be expecting a response.
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
  }
  
  func testSendMessageWhenClientClosedAndServerClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Try sending another message: it should fail
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send a message if it's closed.")
    }
  }
  
  // - MARK: Send Status and Trailers
  
  func testSendStatusAndTrailersWhenClientIdleAndServerIdle() {
    var stateMachine = makeServerStateMachine()

    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: .init(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send status if idle.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientOpenAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: .init(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send status if idle.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientOpenAndServerOpen() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    XCTAssertNoThrow(try stateMachine.send(status: .init(code: .ok, message: ""), metadata: .init(), trailersOnly: false))
    
    // Try sending another message: it should fail because server is now closed.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(message: [], endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send a message if it's closed.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientOpenAndServerClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: .init(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send anything if closed.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientClosedAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: .init(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send status if idle.")
    }
  }
  
  func testSendStatusAndTrailersWhenClientClosedAndServerOpen() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Client is closed but may still be awaiting response, so we should be able to send it.
    XCTAssertNoThrow(try stateMachine.send(status: .init(code: .ok, message: ""), metadata: .init(), trailersOnly: false))
  }
  
  func testSendStatusAndTrailersWhenClientClosedAndServerClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.send(status: .init(code: .ok, message: ""), metadata: .init(), trailersOnly: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send anything if closed.")
    }
  }
  
  // - MARK: Receive metadata
    
  func testReceiveMetadataWhenClientIdleAndServerIdle() throws {
    var stateMachine = makeServerStateMachine()
    
    let action = try stateMachine.receive(metadata: self.receivedHeaders, endStream: false)
    guard case .doNothing = action else {
      XCTFail("Expected action to be doNothing")
      return
    }
  }
  
  func testReceiveMetadataWhenClientIdleAndServerIdle_WithEndStream() {
    var stateMachine = makeServerStateMachine()
    
    // If endStream is set, we should fail, because the client can only close by
    // sending a message with endStream set. If they send metadata it has to be
    // to open the stream (initial metadata).
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: self.receivedHeaders, endStream: true)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(
        error.message,
        """
        Client should have opened before ending the stream: \
        stream shouldn't have been closed when sending initial metadata.
        """
      )
    }
  }
  
  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingContentType() {
    var stateMachine = makeServerStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: self.receivedHeadersWithoutContentType, endStream: false)) { error in
      XCTAssertEqual(error.code, .invalidArgument)
      XCTAssertEqual(error.message, "Invalid or empty content-type.")
    }
  }
  
  func testReceiveMetadataWhenClientIdleAndServerIdle_InvalidContentType() {
    var stateMachine = makeServerStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: self.receivedHeadersWithInvalidContentType, endStream: false)) { error in
      XCTAssertEqual(error.code, .invalidArgument)
      XCTAssertEqual(error.message, "Invalid or empty content-type.")
    }
  }
  
  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingPath() {
    var stateMachine = makeServerStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: self.receivedHeadersWithoutEndpoint, endStream: false)) { error in
      XCTAssertEqual(error.code, .unimplemented)
      XCTAssertEqual(error.message, "No :path header has been set.")
    }
  }
  
  func testReceiveMetadataWhenClientIdleAndServerIdle_Encoding() {
    var noCompressionStateMachine = makeServerStateMachine()
    
    // Try opening client if no compression has been configured in the server:
    // should fail.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try noCompressionStateMachine.receive(metadata: self.receivedHeadersWithDeflateCompression, endStream: false)) { error in
      XCTAssertEqual(error.code, .unimplemented)
      XCTAssertEqual(error.message, "Compression is not supported")
    }
    
    var stateMachine = makeServerStateMachineWithCompression()
    //TODO: add tests for encoding validation
  }
  
  func testReceiveMetadataWhenClientOpenAndServerIdle() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Try receiving initial metadata again - should fail
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: self.receivedHeaders, endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client shouldn't have sent metadata twice.")
    }
  }
  
  func testReceiveMetadataWhenClientOpenAndServerOpen() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: self.receivedHeaders, endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client shouldn't have sent metadata twice.")
    }
  }
  
  func testReceiveMetadataWhenClientOpenAndServerClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: self.receivedHeaders, endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client shouldn't have sent metadata twice.")
    }
  }
  
  func testReceiveMetadataWhenClientClosedAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: self.receivedHeaders, endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't have sent metadata if closed.")
    }
  }
  
  func testReceiveMetadataWhenClientClosedAndServerOpen() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: self.receivedHeaders, endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't have sent metadata if closed.")
    }
  }
  
  func testReceiveMetadataWhenClientClosedAndServerClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(metadata: self.receivedHeaders, endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't have sent metadata if closed.")
    }
  }
  
  // - MARK: Receive message
  
  func testReceiveMessageWhenClientIdleAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Can't have received a message if client is idle.")
    }
  }
  
  func testReceiveMessageWhenClientOpenAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Receive messages successfully: the second one should close client.
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: false))
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Verify client is now closed
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }
  
  func testReceiveMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Receive messages successfully: the second one should close client.
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: false))
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Verify client is now closed
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }
  
  func testReceiveMessageWhenClientOpenAndServerClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Client is not done sending request, don't fail.
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: false))
  }
  
  func testReceiveMessageWhenClientClosedAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }
  
  func testReceiveMessageWhenClientClosedAndServerOpen() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }
  
  func testReceiveMessageWhenClientClosedAndServerClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.receive(message: .init(), endStream: false)) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }
  
  // - MARK: Next outbound message
  
  func testNextOutboundMessageWhenClientIdleAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.nextOutboundMessage()) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }
  
  func testNextOutboundMessageWhenClientOpenAndServerIdle() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.nextOutboundMessage()) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }
  
  func testNextOutboundMessageWhenClientOpenAndServerIdle_WithCompression() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.nextOutboundMessage()) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }
  
  func testNextOutboundMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
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
    var stateMachine = makeServerStateMachineWithCompression()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeadersWithDeflateCompression, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
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
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.nextOutboundMessage()) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Can't send response if server is closed.")
    }
  }

  func testNextOutboundMessageWhenClientClosedAndServerIdle() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.nextOutboundMessage()) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }
  
  func testNextOutboundMessageWhenClientClosedAndServerOpen() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Send a message
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Send another message
    XCTAssertNoThrow(try stateMachine.send(message: [43, 43], endStream: false))
    
    // Make sure that getting the next outbound message _does_ return the message
    // we have enqueued.
    let request = try XCTUnwrap(stateMachine.nextOutboundMessage())
    let expectedBytes: [UInt8] = [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42, // original message
      // End of first message - beginning of second
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      43, 43 // original message
    ]
    XCTAssertEqual(Array(buffer: request), expectedBytes)

    // And then make sure that nothing else is returned anymore
    XCTAssertNil(try stateMachine.nextOutboundMessage())
  }
  
  func testNextOutboundMessageWhenClientClosedAndServerClosed() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    // Send a message
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Even though we have enqueued a message, don't send it, because the server
    // is closed.
    XCTAssertThrowsError(ofType: RPCError.self,
                         try stateMachine.nextOutboundMessage()) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Can't send response if server is closed.")
    }
  }
  
  // - MARK: Next inbound message
  
  func testNextInboundMessageWhenClientIdleAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientOpenAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
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
    var stateMachine = makeServerStateMachineWithCompression()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeadersWithDeflateCompression, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
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
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    let receivedBytes = ByteBuffer(bytes: [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42 // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])
    
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientClosedAndServerIdle() {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientClosedAndServerOpen() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    let receivedBytes = ByteBuffer(bytes: [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42 // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Even though the client is closed, because the server received a message
    // while it was still open, we must get the message now.
    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])
    
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
  
  func testNextInboundMessageWhenClientClosedAndServerClosed() throws {
    var stateMachine = makeServerStateMachine()
    
    // Open client
    XCTAssertNoThrow(try stateMachine.receive(metadata: self.receivedHeaders, endStream: false))
    
    // Open server
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
    
    let receivedBytes = ByteBuffer(bytes: [
      0, // compression flag: unset
      0, 0, 0, 2, // message length: 2 bytes
      42, 42 // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)
    
    // Close server
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    
    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    
    // Even though the client and server are closed, because the server received
    // a message while the client was still open, we must get the message now.
    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])
    
    XCTAssertNil(stateMachine.nextInboundMessage())
  }

}
