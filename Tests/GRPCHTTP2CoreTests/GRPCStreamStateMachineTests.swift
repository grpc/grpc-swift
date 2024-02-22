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
import XCTest

@testable import GRPCHTTP2Core

enum TargetStateMachineState: CaseIterable {
  case clientIdleServerIdle
  case clientOpenServerIdle
  case clientOpenServerOpen
  case clientOpenServerClosed
  case clientClosedServerIdle
  case clientClosedServerOpen
  case clientClosedServerClosed
}

extension HPACKHeaders {
  // Client
  static let clientInitialMetadata: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.scheme.rawValue: "http",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "trailers",
  ]
  static let clientInitialMetadataWithDeflateCompression: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.scheme.rawValue: "https",
    GRPCHTTP2Keys.te.rawValue: "te",
    GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
    GRPCHTTP2Keys.encoding.rawValue: "deflate",
  ]
  static let clientInitialMetadataWithGzipCompression: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.scheme.rawValue: "https",
    GRPCHTTP2Keys.te.rawValue: "te",
    GRPCHTTP2Keys.acceptEncoding.rawValue: "gzip",
    GRPCHTTP2Keys.encoding.rawValue: "gzip",
  ]
  static let receivedHeadersWithoutContentType: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test"
  ]
  static let receivedHeadersWithInvalidContentType: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.contentType.rawValue: "invalid/invalid",
  ]
  static let receivedHeadersWithoutEndpoint: Self = [
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc"
  ]

  // Server
  static let serverInitialMetadata: Self = [
    GRPCHTTP2Keys.status.rawValue: "200",
    GRPCHTTP2Keys.contentType.rawValue: ContentType.protobuf.canonicalValue,
    GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
  ]
  static let serverInitialMetadataWithDeflateCompression: Self = [
    GRPCHTTP2Keys.status.rawValue: "200",
    GRPCHTTP2Keys.contentType.rawValue: ContentType.protobuf.canonicalValue,
    GRPCHTTP2Keys.encoding.rawValue: "deflate",
    GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
  ]
  static let serverTrailers: Self = [
    GRPCHTTP2Keys.status.rawValue: "200",
    GRPCHTTP2Keys.contentType.rawValue: ContentType.protobuf.canonicalValue,
    GRPCHTTP2Keys.grpcStatus.rawValue: "0",
  ]
}

final class GRPCStreamClientStateMachineTests: XCTestCase {
  private func makeClientStateMachine(
    targetState: TargetStateMachineState,
    compressionEnabled: Bool = false
  ) -> GRPCStreamStateMachine {
    var stateMachine = GRPCStreamStateMachine(
      configuration: .client(
        .init(
          methodDescriptor: .init(service: "test", method: "test"),
          scheme: .http,
          outboundEncoding: compressionEnabled ? .deflate : nil,
          acceptedEncodings: [.deflate]
        )
      ),
      maximumPayloadSize: 100,
      skipAssertions: true
    )

    let serverMetadata: HPACKHeaders =
      compressionEnabled ? .serverInitialMetadataWithDeflateCompression : .serverInitialMetadata
    switch targetState {
    case .clientIdleServerIdle:
      break
    case .clientOpenServerIdle:
      // Open client
      XCTAssertNoThrow(try stateMachine.send(metadata: []))
    case .clientOpenServerOpen:
      // Open client
      XCTAssertNoThrow(try stateMachine.send(metadata: []))
      // Open server
      XCTAssertNoThrow(try stateMachine.receive(metadata: serverMetadata, endStream: false))
    case .clientOpenServerClosed:
      // Open client
      XCTAssertNoThrow(try stateMachine.send(metadata: []))
      // Open server
      XCTAssertNoThrow(try stateMachine.receive(metadata: serverMetadata, endStream: false))
      // Close server
      XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    case .clientClosedServerIdle:
      // Open client
      XCTAssertNoThrow(try stateMachine.send(metadata: []))
      // Close client
      XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    case .clientClosedServerOpen:
      // Open client
      XCTAssertNoThrow(try stateMachine.send(metadata: []))
      // Open server
      XCTAssertNoThrow(try stateMachine.receive(metadata: serverMetadata, endStream: false))
      // Close client
      XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
    case .clientClosedServerClosed:
      // Open client
      XCTAssertNoThrow(try stateMachine.send(metadata: []))
      // Open server
      XCTAssertNoThrow(try stateMachine.receive(metadata: serverMetadata, endStream: false))
      // Close client
      XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))
      // Close server
      XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
    }

    return stateMachine
  }

  // - MARK: Send Metadata

  func testSendMetadataWhenClientIdleAndServerIdle() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)
    XCTAssertNoThrow(try stateMachine.send(metadata: []))
  }

  func testSendMetadataWhenClientAlreadyOpen() throws {
    for targetState in [
      TargetStateMachineState.clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed,
    ] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Try sending metadata again: should throw
      XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) {
        error in
        XCTAssertEqual(error.code, .internalError)
        XCTAssertEqual(error.message, "Client is already open: shouldn't be sending metadata.")
      }
    }
  }

  func testSendMetadataWhenClientAlreadyClosed() throws {
    for targetState in [
      TargetStateMachineState.clientClosedServerIdle, .clientClosedServerOpen,
      .clientClosedServerClosed,
    ] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Try sending metadata again: should throw
      XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) {
        error in
        XCTAssertEqual(error.code, .internalError)
        XCTAssertEqual(error.message, "Client is closed: can't send metadata.")
      }
    }
  }

  // - MARK: Send Message

  func testSendMessageWhenClientIdleAndServerIdle() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)

    // Try to send a message without opening (i.e. without sending initial metadata)
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client not yet open.")
    }
  }

  func testSendMessageWhenClientOpen() {
    for targetState in [
      TargetStateMachineState.clientOpenServerIdle, .clientOpenServerOpen, .clientOpenServerClosed,
    ] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Now send a message
      XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
    }
  }

  func testSendMessageWhenClientClosed() {
    for targetState in [
      TargetStateMachineState.clientClosedServerIdle, .clientClosedServerOpen,
      .clientClosedServerClosed,
    ] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Try sending another message: it should fail
      XCTAssertThrowsError(
        ofType: RPCError.self,
        try stateMachine.send(message: [], endStream: false)
      ) { error in
        XCTAssertEqual(error.code, .internalError)
        XCTAssertEqual(error.message, "Client is closed, cannot send a message.")
      }
    }
  }

  // - MARK: Send Status and Trailers

  func testSendStatusAndTrailers() {
    for targetState in TargetStateMachineState.allCases {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // This operation is never allowed on the client.
      XCTAssertThrowsError(
        ofType: RPCError.self,
        try stateMachine.send(
          status: Status(code: .ok, message: ""),
          metadata: .init(),
          trailersOnly: false
        )
      ) { error in
        XCTAssertEqual(error.code, .internalError)
        XCTAssertEqual(error.message, "Client cannot send status and trailer.")
      }
    }

  }

  // - MARK: Receive initial metadata

  func testReceiveInitialMetadataWhenClientIdleAndServerIdle() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(metadata: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server cannot have sent metadata if the client is idle.")
    }
  }

  func testReceiveInitialMetadataWhenServerIdleOrOpen() throws {
    for targetState in [
      TargetStateMachineState.clientOpenServerIdle, .clientOpenServerOpen, .clientClosedServerIdle,
      .clientClosedServerOpen,
    ] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Receive metadata = open server
      let action = try stateMachine.receive(
        metadata: [
          GRPCHTTP2Keys.status.rawValue: "200",
          GRPCHTTP2Keys.contentType.rawValue: ContentType.protobuf.canonicalValue,
          GRPCHTTP2Keys.encoding.rawValue: "deflate",
          "custom": "123",
          "custom-bin": String(base64Encoding: [42, 43, 44]),
        ],
        endStream: false
      )

      var expectedMetadata: Metadata = [
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-encoding": "deflate",
        "custom": "123",
      ]
      expectedMetadata.addBinary([42, 43, 44], forKey: "custom-bin")
      XCTAssertEqual(action, .receivedMetadata(expectedMetadata))
    }
  }

  func testReceiveInitialMetadataWhenServerClosed() {
    for targetState in [TargetStateMachineState.clientOpenServerClosed, .clientClosedServerClosed] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      XCTAssertThrowsError(
        ofType: RPCError.self,
        try stateMachine.receive(metadata: .init(), endStream: false)
      ) { error in
        XCTAssertEqual(error.code, .internalError)
        XCTAssertEqual(error.message, "Server is closed, nothing could have been sent.")
      }
    }
  }

  // - MARK: Receive end trailers

  func testReceiveEndTrailerWhenClientIdleAndServerIdle() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)

    // Receive an end trailer
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(metadata: .init(), endStream: true)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server cannot have sent metadata if the client is idle.")
    }
  }

  func testReceiveEndTrailerWhenClientOpenAndServerIdle() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerIdle)

    // Receive a trailer-only response
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
  }

  func testReceiveEndTrailerWhenServerOpen() throws {
    for targetState in [TargetStateMachineState.clientOpenServerOpen, .clientClosedServerOpen] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Receive an end trailer
      let action = try stateMachine.receive(
        metadata: [
          GRPCHTTP2Keys.status.rawValue: "200",
          GRPCHTTP2Keys.contentType.rawValue: ContentType.protobuf.canonicalValue,
          GRPCHTTP2Keys.encoding.rawValue: "deflate",
          "custom": "123",
        ],
        endStream: true
      )

      let expectedMetadata: Metadata = [
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-encoding": "deflate",
        "custom": "123",
      ]
      XCTAssertEqual(action, .receivedMetadata(expectedMetadata))
    }
  }

  func testReceiveEndTrailerWhenClientOpenAndServerClosed() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerClosed)

    // Receive another end trailer
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(metadata: .init(), endStream: true)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is closed, nothing could have been sent.")
    }
  }

  func testReceiveEndTrailerWhenClientClosedAndServerIdle() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientClosedServerIdle)

    // Server sends a trailers-only response
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
  }

  func testReceiveEndTrailerWhenClientClosedAndServerClosed() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientClosedServerClosed)

    // Close server again (endStream = true) and assert we don't throw.
    // This can happen if the previous close was caused by a grpc-status header
    // and then the server sends an empty frame with EOS set.
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))
  }

  // - MARK: Receive message

  func testReceiveMessageWhenClientIdleAndServerIdle() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(message: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(
        error.message,
        "Cannot have received anything from server if client is not yet open."
      )
    }
  }

  func testReceiveMessageWhenServerIdle() {
    for targetState in [TargetStateMachineState.clientOpenServerIdle, .clientClosedServerIdle] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      XCTAssertThrowsError(
        ofType: RPCError.self,
        try stateMachine.receive(message: .init(), endStream: false)
      ) { error in
        XCTAssertEqual(error.code, .internalError)
        XCTAssertEqual(
          error.message,
          "Server cannot have sent a message before sending the initial metadata."
        )
      }
    }
  }

  func testReceiveMessageWhenServerOpen() throws {
    for targetState in [TargetStateMachineState.clientOpenServerOpen, .clientClosedServerOpen] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: false))
      XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    }
  }

  func testReceiveMessageWhenServerClosed() {
    for targetState in [TargetStateMachineState.clientOpenServerClosed, .clientClosedServerClosed] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      XCTAssertThrowsError(
        ofType: RPCError.self,
        try stateMachine.receive(message: .init(), endStream: false)
      ) { error in
        XCTAssertEqual(error.code, .internalError)
        XCTAssertEqual(error.message, "Cannot have received anything from a closed server.")
      }
    }
  }

  // - MARK: Next outbound message

  func testNextOutboundMessageWhenClientIdleAndServerIdle() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.nextOutboundMessage()
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client is not open yet.")
    }
  }

  func testNextOutboundMessageWhenClientOpenAndServerOpenOrIdle() throws {
    for targetState in [TargetStateMachineState.clientOpenServerIdle, .clientOpenServerOpen] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)

      XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))

      let expectedBytes: [UInt8] = [
        0,  // compression flag: unset
        0, 0, 0, 2,  // message length: 2 bytes
        42, 42,  // original message
      ]
      XCTAssertEqual(
        try stateMachine.nextOutboundMessage(),
        .sendMessage(ByteBuffer(bytes: expectedBytes))
      )

      // And then make sure that nothing else is returned anymore
      XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)
    }
  }

  func testNextOutboundMessageWhenClientOpenAndServerIdle_WithCompression() throws {
    var stateMachine = self.makeClientStateMachine(
      targetState: .clientOpenServerIdle,
      compressionEnabled: true
    )

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)

    let originalMessage = [UInt8]([42, 42, 43, 43])
    XCTAssertNoThrow(try stateMachine.send(message: originalMessage, endStream: false))

    let request = try stateMachine.nextOutboundMessage()
    let framedMessage = try self.frameMessage(originalMessage, compress: true)
    XCTAssertEqual(request, .sendMessage(framedMessage))
  }

  func testNextOutboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = self.makeClientStateMachine(
      targetState: .clientOpenServerOpen,
      compressionEnabled: true
    )

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)

    let originalMessage = [UInt8]([42, 42, 43, 43])
    XCTAssertNoThrow(try stateMachine.send(message: originalMessage, endStream: false))

    let request = try stateMachine.nextOutboundMessage()
    let framedMessage = try self.frameMessage(originalMessage, compress: true)
    XCTAssertEqual(request, .sendMessage(framedMessage))
  }

  func testNextOutboundMessageWhenClientOpenAndServerClosed() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerClosed)

    // No more messages to send
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)

    // Queue a message, but assert the action is .noMoreMessages nevertheless,
    // because the server is closed.
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
  }

  func testNextOutboundMessageWhenClientClosedAndServerIdle() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerIdle)

    // Send a message and close client
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: true))

    // Make sure that getting the next outbound message _does_ return the message
    // we have enqueued.
    let request = try stateMachine.nextOutboundMessage()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ]
    XCTAssertEqual(request, .sendMessage(ByteBuffer(bytes: expectedBytes)))

    // And then make sure that nothing else is returned anymore
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
  }

  func testNextOutboundMessageWhenClientClosedAndServerOpen() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerOpen)

    // Send a message and close client
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: true))

    // Make sure that getting the next outbound message _does_ return the message
    // we have enqueued.
    let request = try stateMachine.nextOutboundMessage()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ]
    XCTAssertEqual(request, .sendMessage(ByteBuffer(bytes: expectedBytes)))

    // And then make sure that nothing else is returned anymore
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
  }

  func testNextOutboundMessageWhenClientClosedAndServerClosed() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerOpen)
    // Send a message
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))

    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))

    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))

    // Even though we have enqueued a message, don't send it, because the server
    // is closed.
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
  }

  // - MARK: Next inbound message

  func testNextInboundMessageWhenServerIdle() {
    for targetState in [
      TargetStateMachineState.clientIdleServerIdle, .clientOpenServerIdle, .clientClosedServerIdle,
    ] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)
      XCTAssertNil(stateMachine.nextInboundMessage())
    }
  }

  func testNextInboundMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerOpen)

    let receivedBytes = ByteBuffer(bytes: [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)

    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])

    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testNextInboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = self.makeClientStateMachine(
      targetState: .clientOpenServerOpen,
      compressionEnabled: true
    )

    let originalMessage = [UInt8]([42, 42, 43, 43])
    let receivedBytes = try self.frameMessage(originalMessage, compress: true)
    try stateMachine.receive(message: receivedBytes, endStream: false)

    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, originalMessage)

    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testNextInboundMessageWhenClientOpenAndServerClosed() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerOpen)

    let receivedBytes = ByteBuffer(bytes: [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)

    // Close server
    XCTAssertNoThrow(try stateMachine.receive(metadata: .init(), endStream: true))

    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])

    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testNextInboundMessageWhenClientClosedAndServerOpen() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerOpen)

    let receivedBytes = ByteBuffer(bytes: [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
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
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerOpen)

    let receivedBytes = ByteBuffer(bytes: [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
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

  // - MARK: Common paths

  func testNormalFlow() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)

    // Client sends metadata
    let clientInitialMetadata = try stateMachine.send(metadata: .init())
    XCTAssertEqual(
      clientInitialMetadata,
      [
        GRPCHTTP2Keys.path.rawValue: "test/test",
        GRPCHTTP2Keys.scheme.rawValue: "http",
        GRPCHTTP2Keys.method.rawValue: "POST",
        GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
        GRPCHTTP2Keys.te.rawValue: "trailers",
        GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
      ]
    )

    // Server sends initial metadata
    let serverInitialHeadersAction = try stateMachine.receive(
      metadata: .serverInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      serverInitialHeadersAction,
      .receivedMetadata([
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-accept-encoding": "deflate",
      ])
    )

    // Client sends messages
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)

    let message = [UInt8]([1, 2, 3, 4])
    let framedMessage = try self.frameMessage(message, compress: false)
    try stateMachine.send(message: message, endStream: false)
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .sendMessage(framedMessage))
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)

    // Server sends response
    XCTAssertNil(stateMachine.nextInboundMessage())

    let firstResponseBytes = [UInt8]([5, 6, 7])
    let firstResponse = try self.frameMessage(firstResponseBytes, compress: false)
    let secondResponseBytes = [UInt8]([8, 9, 10])
    let secondResponse = try self.frameMessage(secondResponseBytes, compress: false)
    try stateMachine.receive(message: firstResponse, endStream: false)
    try stateMachine.receive(message: secondResponse, endStream: false)

    // Make sure messages have arrived
    XCTAssertEqual(stateMachine.nextInboundMessage(), firstResponseBytes)
    XCTAssertEqual(stateMachine.nextInboundMessage(), secondResponseBytes)
    XCTAssertNil(stateMachine.nextInboundMessage())

    // Client sends end
    try stateMachine.send(message: [], endStream: true)

    // Server ends
    let metadataReceivedAction = try stateMachine.receive(
      metadata: .serverTrailers,
      endStream: true
    )
    XCTAssertEqual(metadataReceivedAction, .receivedMetadata(Metadata(headers: .serverTrailers)))

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testClientClosesBeforeServerOpens() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)

    // Client sends metadata
    let clientInitialMetadata = try stateMachine.send(metadata: .init())
    XCTAssertEqual(
      clientInitialMetadata,
      [
        GRPCHTTP2Keys.path.rawValue: "test/test",
        GRPCHTTP2Keys.scheme.rawValue: "http",
        GRPCHTTP2Keys.method.rawValue: "POST",
        GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
        GRPCHTTP2Keys.te.rawValue: "trailers",
        GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
      ]
    )

    // Client sends messages and ends
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)

    let message = [UInt8]([1, 2, 3, 4])
    let framedMessage = try self.frameMessage(message, compress: false)
    try stateMachine.send(message: message, endStream: true)
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .sendMessage(framedMessage))
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)

    // Server sends initial metadata
    let serverInitialHeadersAction = try stateMachine.receive(
      metadata: .serverInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      serverInitialHeadersAction,
      .receivedMetadata([
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-accept-encoding": "deflate",
      ])
    )

    // Server sends response
    XCTAssertNil(stateMachine.nextInboundMessage())

    let firstResponseBytes = [UInt8]([5, 6, 7])
    let firstResponse = try self.frameMessage(firstResponseBytes, compress: false)
    let secondResponseBytes = [UInt8]([8, 9, 10])
    let secondResponse = try self.frameMessage(secondResponseBytes, compress: false)
    try stateMachine.receive(message: firstResponse, endStream: false)
    try stateMachine.receive(message: secondResponse, endStream: false)

    // Make sure messages have arrived
    XCTAssertEqual(stateMachine.nextInboundMessage(), firstResponseBytes)
    XCTAssertEqual(stateMachine.nextInboundMessage(), secondResponseBytes)
    XCTAssertNil(stateMachine.nextInboundMessage())

    // Server ends
    let metadataReceivedAction = try stateMachine.receive(
      metadata: .serverTrailers,
      endStream: true
    )
    XCTAssertEqual(metadataReceivedAction, .receivedMetadata(Metadata(headers: .serverTrailers)))

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testClientClosesBeforeServerResponds() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)

    // Client sends metadata
    let clientInitialMetadata = try stateMachine.send(metadata: .init())
    XCTAssertEqual(
      clientInitialMetadata,
      [
        GRPCHTTP2Keys.path.rawValue: "test/test",
        GRPCHTTP2Keys.scheme.rawValue: "http",
        GRPCHTTP2Keys.method.rawValue: "POST",
        GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
        GRPCHTTP2Keys.te.rawValue: "trailers",
        GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
      ]
    )

    // Client sends messages
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)

    let message = [UInt8]([1, 2, 3, 4])
    let framedMessage = try self.frameMessage(message, compress: false)
    try stateMachine.send(message: message, endStream: false)
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .sendMessage(framedMessage))
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)

    // Server sends initial metadata
    let serverInitialHeadersAction = try stateMachine.receive(
      metadata: .serverInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      serverInitialHeadersAction,
      .receivedMetadata([
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-accept-encoding": "deflate",
      ])
    )

    // Client sends end
    try stateMachine.send(message: [], endStream: true)

    // Server sends response
    XCTAssertNil(stateMachine.nextInboundMessage())

    let firstResponseBytes = [UInt8]([5, 6, 7])
    let firstResponse = try self.frameMessage(firstResponseBytes, compress: false)
    let secondResponseBytes = [UInt8]([8, 9, 10])
    let secondResponse = try self.frameMessage(secondResponseBytes, compress: false)
    try stateMachine.receive(message: firstResponse, endStream: false)
    try stateMachine.receive(message: secondResponse, endStream: false)

    // Make sure messages have arrived
    XCTAssertEqual(stateMachine.nextInboundMessage(), firstResponseBytes)
    XCTAssertEqual(stateMachine.nextInboundMessage(), secondResponseBytes)
    XCTAssertNil(stateMachine.nextInboundMessage())

    // Server ends
    let metadataReceivedAction = try stateMachine.receive(
      metadata: .serverTrailers,
      endStream: true
    )
    XCTAssertEqual(metadataReceivedAction, .receivedMetadata(Metadata(headers: .serverTrailers)))

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
}

final class GRPCStreamServerStateMachineTests: XCTestCase {
  private func makeServerStateMachine(
    targetState: TargetStateMachineState,
    compressionEnabled: Bool = false
  ) -> GRPCStreamStateMachine {

    var stateMachine = GRPCStreamStateMachine(
      configuration: .server(
        .init(
          scheme: .http,
          acceptedEncodings: [.deflate]
        )
      ),
      maximumPayloadSize: 100,
      skipAssertions: true
    )

    let clientMetadata: HPACKHeaders =
      compressionEnabled ? .clientInitialMetadataWithDeflateCompression : .clientInitialMetadata
    switch targetState {
    case .clientIdleServerIdle:
      break
    case .clientOpenServerIdle:
      // Open client
      XCTAssertNoThrow(try stateMachine.receive(metadata: clientMetadata, endStream: false))
    case .clientOpenServerOpen:
      // Open client
      XCTAssertNoThrow(try stateMachine.receive(metadata: clientMetadata, endStream: false))
      // Open server
      XCTAssertNoThrow(try stateMachine.send(metadata: Metadata(headers: .serverInitialMetadata)))
    case .clientOpenServerClosed:
      // Open client
      XCTAssertNoThrow(try stateMachine.receive(metadata: clientMetadata, endStream: false))
      // Open server
      XCTAssertNoThrow(try stateMachine.send(metadata: Metadata(headers: .serverInitialMetadata)))
      // Close server
      XCTAssertNoThrow(
        try stateMachine.send(
          status: .init(code: .ok, message: ""),
          metadata: [],
          trailersOnly: false
        )
      )
    case .clientClosedServerIdle:
      // Open client
      XCTAssertNoThrow(try stateMachine.receive(metadata: clientMetadata, endStream: false))
      // Close client
      XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    case .clientClosedServerOpen:
      // Open client
      XCTAssertNoThrow(try stateMachine.receive(metadata: clientMetadata, endStream: false))
      // Open server
      XCTAssertNoThrow(try stateMachine.send(metadata: Metadata(headers: .serverInitialMetadata)))
      // Close client
      XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
    case .clientClosedServerClosed:
      // Open client
      XCTAssertNoThrow(try stateMachine.receive(metadata: clientMetadata, endStream: false))
      // Open server
      XCTAssertNoThrow(try stateMachine.send(metadata: Metadata(headers: .serverInitialMetadata)))
      // Close client
      XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))
      // Close server
      XCTAssertNoThrow(
        try stateMachine.send(
          status: .init(code: .ok, message: ""),
          metadata: [],
          trailersOnly: false
        )
      )
    }

    return stateMachine
  }

  // - MARK: Send Metadata

  func testSendMetadataWhenClientIdleAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(metadata: .init())
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(
        error.message,
        "Client cannot be idle if server is sending initial metadata: it must have opened."
      )
    }
  }

  func testSendMetadataWhenClientOpenAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
  }

  func testSendMetadataWhenClientOpenAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    // Try sending metadata again: should throw
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(metadata: .init())
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server has already sent initial metadata.")
    }
  }

  func testSendMetadataWhenClientOpenAndServerClosed() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerClosed)

    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server cannot send metadata if closed.")
    }
  }

  func testSendMetadataWhenClientClosedAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    // We should be allowed to send initial metadata if client is closed:
    // client may be finished sending request but may still be awaiting response.
    XCTAssertNoThrow(try stateMachine.send(metadata: .init()))
  }

  func testSendMetadataWhenClientClosedAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerOpen)

    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server has already sent initial metadata.")
    }
  }

  func testSendMetadataWhenClientClosedAndServerClosed() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerClosed)

    // Try sending metadata again: should throw
    XCTAssertThrowsError(ofType: RPCError.self, try stateMachine.send(metadata: .init())) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server cannot send metadata if closed.")
    }
  }

  // - MARK: Send Message

  func testSendMessageWhenClientIdleAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(
        error.message,
        "Server must have sent initial metadata before sending a message."
      )
    }
  }

  func testSendMessageWhenClientOpenAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    // Now send a message
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(
        error.message,
        "Server must have sent initial metadata before sending a message."
      )
    }
  }

  func testSendMessageWhenClientOpenAndServerOpen() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    // Now send a message
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
  }

  func testSendMessageWhenClientOpenAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerClosed)

    // Try sending another message: it should fail
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send a message if it's closed.")
    }
  }

  func testSendMessageWhenClientClosedAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(
        error.message,
        "Server must have sent initial metadata before sending a message."
      )
    }
  }

  func testSendMessageWhenClientClosedAndServerOpen() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerOpen)

    // Try sending a message: even though client is closed, we should send it
    // because it may be expecting a response.
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: false))
  }

  func testSendMessageWhenClientClosedAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerClosed)

    // Try sending another message: it should fail
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send a message if it's closed.")
    }
  }

  // - MARK: Send Status and Trailers

  func testSendStatusAndTrailersWhenClientIdleAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: .init(),
        trailersOnly: false
      )
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send status if idle.")
    }
  }

  func testSendStatusAndTrailersWhenClientOpenAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: .init(),
        trailersOnly: false
      )
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send status if idle.")
    }
  }

  func testSendStatusAndTrailersWhenClientOpenAndServerOpen() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    XCTAssertNoThrow(
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: .init(),
        trailersOnly: false
      )
    )

    // Try sending another message: it should fail because server is now closed.
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send a message if it's closed.")
    }
  }

  func testSendStatusAndTrailersWhenClientOpenAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerClosed)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: .init(),
        trailersOnly: false
      )
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send anything if closed.")
    }
  }

  func testSendStatusAndTrailersWhenClientClosedAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: .init(),
        trailersOnly: false
      )
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send status if idle.")
    }
  }

  func testSendStatusAndTrailersWhenClientClosedAndServerOpen() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerOpen)

    // Client is closed but may still be awaiting response, so we should be able to send it.
    XCTAssertNoThrow(
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: .init(),
        trailersOnly: false
      )
    )
  }

  func testSendStatusAndTrailersWhenClientClosedAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerClosed)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: .init(),
        trailersOnly: false
      )
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send anything if closed.")
    }
  }

  // - MARK: Receive metadata

  func testReceiveMetadataWhenClientIdleAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(metadata: .clientInitialMetadata, endStream: false)
    XCTAssertEqual(
      action,
      .receivedMetadata(Metadata(headers: .clientInitialMetadata))
    )
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_WithEndStream() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    // If endStream is set, we should fail, because the client can only close by
    // sending a message with endStream set. If they send metadata it has to be
    // to open the stream (initial metadata).
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(metadata: .clientInitialMetadata, endStream: true)
    ) { error in
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

  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingContentType() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedHeadersWithoutContentType,
      endStream: false
    )

    try self.assertRejectedRPC(action) { grpcStatus, trailers in
      let unwrappedTrailers = try XCTUnwrap(trailers)
      XCTAssertEqual(unwrappedTrailers.count, 1)
      XCTAssertEqual(unwrappedTrailers.status, "415")
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_InvalidContentType() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedHeadersWithInvalidContentType,
      endStream: false
    )

    try self.assertRejectedRPC(action) { grpcStatus, trailers in
      let unwrappedTrailers = try XCTUnwrap(trailers)
      XCTAssertEqual(unwrappedTrailers.count, 1)
      XCTAssertEqual(unwrappedTrailers.status, "415")
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingPath() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedHeadersWithoutEndpoint,
      endStream: false
    )

    try self.assertRejectedRPC(action) { grpcStatus, trailers in
      XCTAssertNil(trailers)
      let unwrappedStatus = try XCTUnwrap(grpcStatus)
      XCTAssertEqual(unwrappedStatus.code, .unimplemented)
      XCTAssertEqual(unwrappedStatus.message, "No :path header has been set.")
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_ServerUnsupportedEncoding() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    // Try opening client with a compression algorithm that is not accepted
    // by the server.
    let action = try stateMachine.receive(
      metadata: .clientInitialMetadataWithGzipCompression,
      endStream: false
    )

    try self.assertRejectedRPC(action) { grpcStatus, trailers in
      let unwrappedTrailers = try XCTUnwrap(trailers)
      XCTAssertEqual(unwrappedTrailers.count, 1)
      XCTAssertEqual(unwrappedTrailers.acceptedEncodings, [.deflate])

      let unwrappedStatus = try XCTUnwrap(grpcStatus)
      XCTAssertEqual(unwrappedStatus.code, .unimplemented)
      XCTAssertEqual(
        unwrappedStatus.message,
        """
        gzip compression is not supported; \
        supported algorithms are listed in grpc-accept-encoding
        """
      )
    }
  }

  //TODO: add more encoding-related validation tests (for both client and server)
  // and message encoding tests

  func testReceiveMetadataWhenClientOpenAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    // Try receiving initial metadata again - should fail
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(metadata: .clientInitialMetadata, endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client shouldn't have sent metadata twice.")
    }
  }

  func testReceiveMetadataWhenClientOpenAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(metadata: .clientInitialMetadata, endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client shouldn't have sent metadata twice.")
    }
  }

  func testReceiveMetadataWhenClientOpenAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerClosed)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(metadata: .clientInitialMetadata, endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client shouldn't have sent metadata twice.")
    }
  }

  func testReceiveMetadataWhenClientClosedAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(metadata: .clientInitialMetadata, endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't have sent metadata if closed.")
    }
  }

  func testReceiveMetadataWhenClientClosedAndServerOpen() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerOpen)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(metadata: .clientInitialMetadata, endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't have sent metadata if closed.")
    }
  }

  func testReceiveMetadataWhenClientClosedAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerClosed)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(metadata: .clientInitialMetadata, endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't have sent metadata if closed.")
    }
  }

  // - MARK: Receive message

  func testReceiveMessageWhenClientIdleAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(message: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Can't have received a message if client is idle.")
    }
  }

  func testReceiveMessageWhenClientOpenAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    // Receive messages successfully: the second one should close client.
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: false))
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))

    // Verify client is now closed
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(message: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }

  func testReceiveMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    // Receive messages successfully: the second one should close client.
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: false))
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))

    // Verify client is now closed
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(message: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }

  func testReceiveMessageWhenClientOpenAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerClosed)

    // Client is not done sending request, don't fail.
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: false))
  }

  func testReceiveMessageWhenClientClosedAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(message: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }

  func testReceiveMessageWhenClientClosedAndServerOpen() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerOpen)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(message: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }

  func testReceiveMessageWhenClientClosedAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerClosed)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(message: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }

  // - MARK: Next outbound message

  func testNextOutboundMessageWhenClientIdleAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.nextOutboundMessage()
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }

  func testNextOutboundMessageWhenClientOpenAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.nextOutboundMessage()
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }

  func testNextOutboundMessageWhenClientOpenAndServerIdle_WithCompression() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.nextOutboundMessage()
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }

  func testNextOutboundMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)

    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))

    let response = try stateMachine.nextOutboundMessage()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ]
    XCTAssertEqual(response, .sendMessage(ByteBuffer(bytes: expectedBytes)))

    // And then make sure that nothing else is returned
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)
  }

  func testNextOutboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = self.makeServerStateMachine(
      targetState: .clientOpenServerOpen,
      compressionEnabled: true
    )

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)

    let originalMessage = [UInt8]([42, 42, 43, 43])
    XCTAssertNoThrow(try stateMachine.send(message: originalMessage, endStream: false))

    let response = try stateMachine.nextOutboundMessage()
    let framedMessage = try self.frameMessage(originalMessage, compress: true)
    XCTAssertEqual(response, .sendMessage(framedMessage))
  }

  func testNextOutboundMessageWhenClientOpenAndServerClosed() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    // Send message and close server
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))
    XCTAssertNoThrow(
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: [],
        trailersOnly: false
      )
    )

    let response = try stateMachine.nextOutboundMessage()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ]
    XCTAssertEqual(response, .sendMessage(ByteBuffer(bytes: expectedBytes)))

    // And then make sure that nothing else is returned anymore
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
  }

  func testNextOutboundMessageWhenClientClosedAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.nextOutboundMessage()
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }

  func testNextOutboundMessageWhenClientClosedAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    // Send a message
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))

    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))

    // Send another message
    XCTAssertNoThrow(try stateMachine.send(message: [43, 43], endStream: false))

    // Make sure that getting the next outbound message _does_ return the message
    // we have enqueued.
    let response = try stateMachine.nextOutboundMessage()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
      // End of first message - beginning of second
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      43, 43,  // original message
    ]
    XCTAssertEqual(response, .sendMessage(ByteBuffer(bytes: expectedBytes)))

    // And then make sure that nothing else is returned anymore
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)
  }

  func testNextOutboundMessageWhenClientClosedAndServerClosed() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerOpen)

    // Send a message and close server
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], endStream: false))
    XCTAssertNoThrow(
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: [],
        trailersOnly: false
      )
    )

    // We have enqueued a message, make sure we return it even though server is closed,
    // because we haven't yet drained all of the pending messages.
    let response = try stateMachine.nextOutboundMessage()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ]
    XCTAssertEqual(response, .sendMessage(ByteBuffer(bytes: expectedBytes)))

    // And then make sure that nothing else is returned anymore
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
  }

  // - MARK: Next inbound message

  func testNextInboundMessageWhenClientIdleAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)
    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testNextInboundMessageWhenClientOpenAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testNextInboundMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    let receivedBytes = ByteBuffer(bytes: [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)

    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])

    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testNextInboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = self.makeServerStateMachine(
      targetState: .clientOpenServerOpen,
      compressionEnabled: true
    )

    let originalMessage = [UInt8]([42, 42, 43, 43])
    let receivedBytes = try self.frameMessage(originalMessage, compress: true)

    try stateMachine.receive(message: receivedBytes, endStream: false)

    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, originalMessage)

    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testNextInboundMessageWhenClientOpenAndServerClosed() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    let receivedBytes = ByteBuffer(bytes: [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)

    // Close server
    XCTAssertNoThrow(
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: [],
        trailersOnly: false
      )
    )

    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])

    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testNextInboundMessageWhenClientClosedAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testNextInboundMessageWhenClientClosedAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    let receivedBytes = ByteBuffer(bytes: [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
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
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    let receivedBytes = ByteBuffer(bytes: [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)

    // Close server
    XCTAssertNoThrow(
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: [],
        trailersOnly: false
      )
    )

    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))

    // Even though the client and server are closed, because the server received
    // a message while the client was still open, we must get the message now.
    let receivedMessage = try XCTUnwrap(stateMachine.nextInboundMessage())
    XCTAssertEqual(receivedMessage, [42, 42])

    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  // - MARK: Common paths

  func testNormalFlow() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    // Client sends metadata
    let receiveMetadataAction = try stateMachine.receive(
      metadata: .clientInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      receiveMetadataAction,
      .receivedMetadata(Metadata(headers: .clientInitialMetadata))
    )

    // Server sends initial metadata
    let sentInitialHeaders = try stateMachine.send(metadata: Metadata(headers: ["custom": "value"]))
    XCTAssertEqual(
      sentInitialHeaders,
      [
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-accept-encoding": "deflate",
        "custom": "value",
      ]
    )

    // Client sends messages
    let deframedMessage = [UInt8]([1, 2, 3, 4])
    let completeMessage = try self.frameMessage(deframedMessage, compress: false)
    // Split message into two parts to make sure the stitching together of the frames works well
    let firstMessage = completeMessage.getSlice(at: 0, length: 4)!
    let secondMessage = completeMessage.getSlice(at: 4, length: completeMessage.readableBytes - 4)!

    try stateMachine.receive(message: firstMessage, endStream: false)
    XCTAssertNil(stateMachine.nextInboundMessage())
    try stateMachine.receive(message: secondMessage, endStream: false)
    XCTAssertEqual(stateMachine.nextInboundMessage(), deframedMessage)

    // Server sends response
    let firstResponse = [UInt8]([5, 6, 7])
    let secondResponse = [UInt8]([8, 9, 10])
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)
    try stateMachine.send(message: firstResponse, endStream: false)
    try stateMachine.send(message: secondResponse, endStream: false)

    // Make sure messages are outbound
    let framedMessages = try self.frameMessages([firstResponse, secondResponse], compress: false)
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .sendMessage(framedMessages))

    // Client sends end
    try stateMachine.receive(message: ByteBuffer(), endStream: true)

    // Server ends
    let response = try stateMachine.send(
      status: .init(code: .ok, message: ""),
      metadata: [],
      trailersOnly: false
    )
    XCTAssertEqual(response, ["grpc-status": "0"])

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testClientClosesBeforeServerOpens() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    // Client sends metadata
    let receiveMetadataAction = try stateMachine.receive(
      metadata: .clientInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      receiveMetadataAction,
      .receivedMetadata(Metadata(headers: .clientInitialMetadata))
    )

    // Client sends messages
    let deframedMessage = [UInt8]([1, 2, 3, 4])
    let completeMessage = try self.frameMessage(deframedMessage, compress: false)
    // Split message into two parts to make sure the stitching together of the frames works well
    let firstMessage = completeMessage.getSlice(at: 0, length: 4)!
    let secondMessage = completeMessage.getSlice(at: 4, length: completeMessage.readableBytes - 4)!

    try stateMachine.receive(message: firstMessage, endStream: false)
    XCTAssertNil(stateMachine.nextInboundMessage())
    try stateMachine.receive(message: secondMessage, endStream: false)
    XCTAssertEqual(stateMachine.nextInboundMessage(), deframedMessage)

    // Client sends end
    try stateMachine.receive(message: ByteBuffer(), endStream: true)

    // Server sends initial metadata
    let sentInitialHeaders = try stateMachine.send(metadata: Metadata(headers: ["custom": "value"]))
    XCTAssertEqual(
      sentInitialHeaders,
      [
        "custom": "value",
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-accept-encoding": "deflate",
      ]
    )

    // Server sends response
    let firstResponse = [UInt8]([5, 6, 7])
    let secondResponse = [UInt8]([8, 9, 10])
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)
    try stateMachine.send(message: firstResponse, endStream: false)
    try stateMachine.send(message: secondResponse, endStream: false)

    // Make sure messages are outbound
    let framedMessages = try self.frameMessages([firstResponse, secondResponse], compress: false)
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .sendMessage(framedMessages))

    // Server ends
    let response = try stateMachine.send(
      status: .init(code: .ok, message: ""),
      metadata: [],
      trailersOnly: false
    )
    XCTAssertEqual(response, ["grpc-status": "0"])

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertNil(stateMachine.nextInboundMessage())
  }

  func testClientClosesBeforeServerResponds() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    // Client sends metadata
    let receiveMetadataAction = try stateMachine.receive(
      metadata: .clientInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      receiveMetadataAction,
      .receivedMetadata(Metadata(headers: .clientInitialMetadata))
    )

    // Client sends messages
    let deframedMessage = [UInt8]([1, 2, 3, 4])
    let completeMessage = try self.frameMessage(deframedMessage, compress: false)
    // Split message into two parts to make sure the stitching together of the frames works well
    let firstMessage = completeMessage.getSlice(at: 0, length: 4)!
    let secondMessage = completeMessage.getSlice(at: 4, length: completeMessage.readableBytes - 4)!

    try stateMachine.receive(message: firstMessage, endStream: false)
    XCTAssertNil(stateMachine.nextInboundMessage())
    try stateMachine.receive(message: secondMessage, endStream: false)
    XCTAssertEqual(stateMachine.nextInboundMessage(), deframedMessage)

    // Server sends initial metadata
    let sentInitialHeaders = try stateMachine.send(metadata: Metadata(headers: ["custom": "value"]))
    XCTAssertEqual(
      sentInitialHeaders,
      [
        "custom": "value",
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-accept-encoding": "deflate",
      ]
    )

    // Client sends end
    try stateMachine.receive(message: ByteBuffer(), endStream: true)

    // Server sends response
    let firstResponse = [UInt8]([5, 6, 7])
    let secondResponse = [UInt8]([8, 9, 10])
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .awaitMoreMessages)
    try stateMachine.send(message: firstResponse, endStream: false)
    try stateMachine.send(message: secondResponse, endStream: false)

    // Make sure messages are outbound
    let framedMessages = try self.frameMessages([firstResponse, secondResponse], compress: false)
    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .sendMessage(framedMessages))

    // Server ends
    let response = try stateMachine.send(
      status: .init(code: .ok, message: ""),
      metadata: [],
      trailersOnly: false
    )
    XCTAssertEqual(response, ["grpc-status": "0"])

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertNil(stateMachine.nextInboundMessage())
  }
}

extension XCTestCase {
  func assertRejectedRPC(
    _ action: GRPCStreamStateMachine.OnMetadataReceived,
    expression: (Status?, HPACKHeaders?) throws -> Void
  ) rethrows {
    guard case .rejectRPC(let status, let trailers) = action else {
      XCTFail("RPC should have been rejected.")
      return
    }
    try expression(status, trailers)
  }

  func frameMessage(_ message: [UInt8], compress: Bool) throws -> ByteBuffer {
    try frameMessages([message], compress: compress)
  }

  func frameMessages(_ messages: any Sequence<[UInt8]>, compress: Bool) throws -> ByteBuffer {
    var framer = GRPCMessageFramer()
    let compressor: Zlib.Compressor? = {
      if compress {
        return Zlib.Compressor(method: .deflate)
      } else {
        return nil
      }
    }()
    defer { compressor?.end() }
    for message in messages {
      framer.append(message)
    }
    return try XCTUnwrap(framer.next(compressor: compressor))
  }
}
