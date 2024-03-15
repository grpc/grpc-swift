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

private enum TargetStateMachineState: CaseIterable {
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
  fileprivate static let clientInitialMetadata: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.scheme.rawValue: "http",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "trailers",
  ]
  fileprivate static let clientInitialMetadataWithDeflateCompression: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.scheme.rawValue: "https",
    GRPCHTTP2Keys.te.rawValue: "trailers",
    GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
    GRPCHTTP2Keys.encoding.rawValue: "deflate",
  ]
  fileprivate static let clientInitialMetadataWithGzipCompression: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.scheme.rawValue: "https",
    GRPCHTTP2Keys.te.rawValue: "trailers",
    GRPCHTTP2Keys.acceptEncoding.rawValue: "gzip",
    GRPCHTTP2Keys.encoding.rawValue: "gzip",
  ]
  fileprivate static let receivedWithoutContentType: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test"
  ]
  fileprivate static let receivedWithInvalidContentType: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.contentType.rawValue: "invalid/invalid",
  ]
  fileprivate static let receivedWithoutEndpoint: Self = [
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc"
  ]
  fileprivate static let receivedWithoutTE: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.scheme.rawValue: "http",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
  ]
  fileprivate static let receivedWithInvalidTE: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.scheme.rawValue: "http",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "invalidte",
  ]
  fileprivate static let receivedWithoutMethod: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.scheme.rawValue: "http",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "trailers",
  ]
  fileprivate static let receivedWithInvalidMethod: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.scheme.rawValue: "http",
    GRPCHTTP2Keys.method.rawValue: "GET",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "trailers",
  ]
  fileprivate static let receivedWithoutScheme: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "trailers",
  ]
  fileprivate static let receivedWithInvalidScheme: Self = [
    GRPCHTTP2Keys.path.rawValue: "test/test",
    GRPCHTTP2Keys.scheme.rawValue: "invalidscheme",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "trailers",
  ]

  // Server
  fileprivate static let serverInitialMetadata: Self = [
    GRPCHTTP2Keys.status.rawValue: "200",
    GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
    GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
  ]
  fileprivate static let serverInitialMetadataWithDeflateCompression: Self = [
    GRPCHTTP2Keys.status.rawValue: "200",
    GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
    GRPCHTTP2Keys.encoding.rawValue: "deflate",
    GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
  ]
  fileprivate static let serverTrailers: Self = [
    GRPCHTTP2Keys.status.rawValue: "200",
    GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
    GRPCHTTP2Keys.grpcStatus.rawValue: "0",
  ]
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
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
          outboundEncoding: compressionEnabled ? .deflate : .identity,
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
      XCTAssertNoThrow(try stateMachine.receive(metadata: .serverTrailers, endStream: true))
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
      XCTAssertNoThrow(try stateMachine.receive(metadata: .serverTrailers, endStream: true))
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
          metadata: .init()
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

  func testReceiveInvalidInitialMetadataWhenServerIdle() throws {
    for targetState in [
      TargetStateMachineState.clientOpenServerIdle, .clientClosedServerIdle,
    ] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Receive metadata with unexpected non-200 status code
      let action = try stateMachine.receive(
        metadata: [GRPCHTTP2Keys.status.rawValue: "300"],
        endStream: false
      )

      XCTAssertEqual(
        action,
        .receivedStatusAndMetadata(
          status: .init(code: .unknown, message: "Unexpected non-200 HTTP Status Code."),
          metadata: [":status": "300"]
        )
      )
    }
  }

  func testReceiveInitialMetadataWhenServerIdle() throws {
    for targetState in [
      TargetStateMachineState.clientOpenServerIdle, .clientClosedServerIdle,
    ] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Receive metadata = open server
      let action = try stateMachine.receive(
        metadata: [
          GRPCHTTP2Keys.status.rawValue: "200",
          GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
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

  func testReceiveInitialMetadataWhenServerOpen() throws {
    for targetState in [
      TargetStateMachineState.clientOpenServerOpen, .clientClosedServerOpen,
    ] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Receiving initial metadata again should throw if grpc-status is not present.
      XCTAssertThrowsError(
        ofType: RPCError.self,
        try stateMachine.receive(
          metadata: [
            GRPCHTTP2Keys.status.rawValue: "200",
            GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
            GRPCHTTP2Keys.encoding.rawValue: "deflate",
            "custom": "123",
            "custom-bin": String(base64Encoding: [42, 43, 44]),
          ],
          endStream: false
        )
      ) { error in
        XCTAssertEqual(error.code, .unknown)
        XCTAssertEqual(
          error.message,
          "Non-initial metadata must be a trailer containing a valid grpc-status"
        )
      }

      // Now make sure everything works well if we include grpc-status
      let action = try stateMachine.receive(
        metadata: [
          GRPCHTTP2Keys.status.rawValue: "200",
          GRPCHTTP2Keys.grpcStatus.rawValue: String(Status.Code.ok.rawValue),
          GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
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
      expectedMetadata.removeAllValues(forKey: GRPCHTTP2Keys.grpcStatus.rawValue)
      expectedMetadata.addBinary([42, 43, 44], forKey: "custom-bin")
      XCTAssertEqual(
        action,
        .receivedStatusAndMetadata(
          status: Status(code: .ok, message: ""),
          metadata: expectedMetadata
        )
      )
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

  func testReceiveEndTrailerWhenClientOpenAndServerIdle() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerIdle)

    // Receive a trailers-only response
    let trailersOnlyResponse: HPACKHeaders = [
      GRPCHTTP2Keys.status.rawValue: "200",
      GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
      GRPCHTTP2Keys.grpcStatus.rawValue: String(Status.Code.internalError.rawValue),
      GRPCHTTP2Keys.grpcStatusMessage.rawValue: GRPCStatusMessageMarshaller.marshall(
        "Some status message"
      )!,
      "custom-key": "custom-value",
    ]
    let trailers = try stateMachine.receive(metadata: trailersOnlyResponse, endStream: true)
    switch trailers {
    case .receivedStatusAndMetadata(let status, let metadata):
      XCTAssertEqual(status, Status(code: .internalError, message: "Some status message"))
      XCTAssertEqual(
        metadata,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "custom-key": "custom-value",
        ]
      )
    case .receivedMetadata, .doNothing, .rejectRPC:
      XCTFail("Expected .receivedStatusAndMetadata")
    }
  }

  func testReceiveEndTrailerWhenServerOpen() throws {
    for targetState in [TargetStateMachineState.clientOpenServerOpen, .clientClosedServerOpen] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Receive an end trailer
      let action = try stateMachine.receive(
        metadata: [
          GRPCHTTP2Keys.status.rawValue: "200",
          GRPCHTTP2Keys.grpcStatus.rawValue: String(Status.Code.ok.rawValue),
          GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
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
      XCTAssertEqual(
        action,
        .receivedStatusAndMetadata(
          status: .init(code: .ok, message: ""),
          metadata: expectedMetadata
        )
      )
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

  func testReceiveEndTrailerWhenClientClosedAndServerIdle() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientClosedServerIdle)

    // Server sends a trailers-only response
    let trailersOnlyResponse: HPACKHeaders = [
      GRPCHTTP2Keys.status.rawValue: "200",
      GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
      GRPCHTTP2Keys.grpcStatus.rawValue: String(Status.Code.internalError.rawValue),
      GRPCHTTP2Keys.grpcStatusMessage.rawValue: GRPCStatusMessageMarshaller.marshall(
        "Some status message"
      )!,
      "custom-key": "custom-value",
    ]
    let trailers = try stateMachine.receive(metadata: trailersOnlyResponse, endStream: true)
    switch trailers {
    case .receivedStatusAndMetadata(let status, let metadata):
      XCTAssertEqual(status, Status(code: .internalError, message: "Some status message"))
      XCTAssertEqual(
        metadata,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "custom-key": "custom-value",
        ]
      )
    case .receivedMetadata, .doNothing, .rejectRPC:
      XCTFail("Expected .receivedStatusAndMetadata")
    }
  }

  func testReceiveEndTrailerWhenClientClosedAndServerClosed() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientClosedServerClosed)

    // Close server again (endStream = true) and assert we don't throw.
    // This can happen if the previous close was caused by a grpc-status header
    // and then the server sends an empty frame with EOS set.
    XCTAssertEqual(try stateMachine.receive(metadata: .init(), endStream: true), .doNothing)
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
    XCTAssertNoThrow(try stateMachine.receive(metadata: .serverTrailers, endStream: true))

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
      XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
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

    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage([42, 42]))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
  }

  func testNextInboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = self.makeClientStateMachine(
      targetState: .clientOpenServerOpen,
      compressionEnabled: true
    )

    let originalMessage = [UInt8]([42, 42, 43, 43])
    let receivedBytes = try self.frameMessage(originalMessage, compress: true)
    try stateMachine.receive(message: receivedBytes, endStream: false)

    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(originalMessage))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
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
    XCTAssertNoThrow(try stateMachine.receive(metadata: .serverTrailers, endStream: true))

    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage([42, 42]))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
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
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage([42, 42]))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
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
    XCTAssertNoThrow(try stateMachine.receive(metadata: .serverTrailers, endStream: true))

    // Close client
    XCTAssertNoThrow(try stateMachine.send(message: [], endStream: true))

    // Even though the client is closed, because it received a message while open,
    // we must get the message now.
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage([42, 42]))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
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
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    let firstResponseBytes = [UInt8]([5, 6, 7])
    let firstResponse = try self.frameMessage(firstResponseBytes, compress: false)
    let secondResponseBytes = [UInt8]([8, 9, 10])
    let secondResponse = try self.frameMessage(secondResponseBytes, compress: false)
    try stateMachine.receive(message: firstResponse, endStream: false)
    try stateMachine.receive(message: secondResponse, endStream: false)

    // Make sure messages have arrived
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(firstResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(secondResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    // Client sends end
    try stateMachine.send(message: [], endStream: true)

    // Server ends
    let metadataReceivedAction = try stateMachine.receive(
      metadata: .serverTrailers,
      endStream: true
    )
    let receivedMetadata = {
      var m = Metadata(headers: .serverTrailers)
      m.removeAllValues(forKey: GRPCHTTP2Keys.grpcStatus.rawValue)
      m.removeAllValues(forKey: GRPCHTTP2Keys.grpcStatusMessage.rawValue)
      return m
    }()
    XCTAssertEqual(
      metadataReceivedAction,
      .receivedStatusAndMetadata(status: .init(code: .ok, message: ""), metadata: receivedMetadata)
    )

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
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
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    let firstResponseBytes = [UInt8]([5, 6, 7])
    let firstResponse = try self.frameMessage(firstResponseBytes, compress: false)
    let secondResponseBytes = [UInt8]([8, 9, 10])
    let secondResponse = try self.frameMessage(secondResponseBytes, compress: false)
    try stateMachine.receive(message: firstResponse, endStream: false)
    try stateMachine.receive(message: secondResponse, endStream: false)

    // Make sure messages have arrived
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(firstResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(secondResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    // Server ends
    let metadataReceivedAction = try stateMachine.receive(
      metadata: .serverTrailers,
      endStream: true
    )
    let receivedMetadata = {
      var m = Metadata(headers: .serverTrailers)
      m.removeAllValues(forKey: GRPCHTTP2Keys.grpcStatus.rawValue)
      m.removeAllValues(forKey: GRPCHTTP2Keys.grpcStatusMessage.rawValue)
      return m
    }()
    XCTAssertEqual(
      metadataReceivedAction,
      .receivedStatusAndMetadata(status: .init(code: .ok, message: ""), metadata: receivedMetadata)
    )

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
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
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    let firstResponseBytes = [UInt8]([5, 6, 7])
    let firstResponse = try self.frameMessage(firstResponseBytes, compress: false)
    let secondResponseBytes = [UInt8]([8, 9, 10])
    let secondResponse = try self.frameMessage(secondResponseBytes, compress: false)
    try stateMachine.receive(message: firstResponse, endStream: false)
    try stateMachine.receive(message: secondResponse, endStream: false)

    // Make sure messages have arrived
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(firstResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(secondResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    // Server ends
    let metadataReceivedAction = try stateMachine.receive(
      metadata: .serverTrailers,
      endStream: true
    )
    let receivedMetadata = {
      var m = Metadata(headers: .serverTrailers)
      m.removeAllValues(forKey: GRPCHTTP2Keys.grpcStatus.rawValue)
      m.removeAllValues(forKey: GRPCHTTP2Keys.grpcStatusMessage.rawValue)
      return m
    }()
    XCTAssertEqual(
      metadataReceivedAction,
      .receivedStatusAndMetadata(status: .init(code: .ok, message: ""), metadata: receivedMetadata)
    )

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
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
          metadata: []
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
          metadata: []
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

  func testSendStatusAndTrailersWhenClientIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: .init()
      )
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send status if client is idle.")
    }
  }

  func testSendStatusAndTrailersWhenClientOpenAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    let trailers = try stateMachine.send(
      status: .init(code: .unknown, message: "RPC unknown"),
      metadata: .init()
    )

    // Make sure it's a trailers-only response: it must have :status header and content-type
    XCTAssertEqual(
      trailers,
      [
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-status": "2",
        "grpc-status-message": "RPC unknown",
      ]
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

  func testSendStatusAndTrailersWhenClientOpenAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    let trailers = try stateMachine.send(
      status: .init(code: .ok, message: ""),
      metadata: .init()
    )

    // Make sure it's NOT a trailers-only response, because the server was
    // already open (so it sent initial metadata): it shouldn't have :status or content-type headers
    XCTAssertEqual(trailers, ["grpc-status": "0"])

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
        metadata: .init()
      )
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send anything if closed.")
    }
  }

  func testSendStatusAndTrailersWhenClientClosedAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    let trailers = try stateMachine.send(
      status: .init(code: .unknown, message: "RPC unknown"),
      metadata: .init()
    )

    // Make sure it's a trailers-only response: it must have :status header and content-type
    XCTAssertEqual(
      trailers,
      [
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-status": "2",
        "grpc-status-message": "RPC unknown",
      ]
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

  func testSendStatusAndTrailersWhenClientClosedAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerOpen)

    let trailers = try stateMachine.send(
      status: .init(code: .ok, message: ""),
      metadata: .init()
    )

    // Make sure it's NOT a trailers-only response, because the server was
    // already open (so it sent initial metadata): it shouldn't have :status or content-type headers
    XCTAssertEqual(trailers, ["grpc-status": "0"])

    // Try sending another message: it should fail because server is now closed.
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send a message if it's closed.")
    }
  }

  func testSendStatusAndTrailersWhenClientClosedAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerClosed)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: .init()
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

  func testReceiveMetadataWhenClientIdleAndServerIdle_WithEndStream() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(metadata: .clientInitialMetadata, endStream: true)
    XCTAssertEqual(
      action,
      .receivedMetadata(Metadata(headers: .clientInitialMetadata))
    )
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingContentType() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedWithoutContentType,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(trailers.count, 1)
      XCTAssertEqual(trailers.firstString(forKey: .status), "415")
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_InvalidContentType() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedWithInvalidContentType,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(trailers.count, 1)
      XCTAssertEqual(trailers.firstString(forKey: .status), "415")
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingPath() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedWithoutEndpoint,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "12",
          "grpc-status-message": "No :path header has been set.",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingTE() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedWithoutTE,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-status-message":
            "\"te\" header is expected to be present and have a value of \"trailers\".",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_InvalidTE() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedWithInvalidTE,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-status-message":
            "\"te\" header is expected to be present and have a value of \"trailers\".",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingMethod() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedWithoutMethod,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-status-message":
            ":method header is expected to be present and have a value of \"POST\".",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_InvalidMethod() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedWithInvalidMethod,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-status-message":
            ":method header is expected to be present and have a value of \"POST\".",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingScheme() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedWithoutScheme,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-status-message": ":scheme header must be present and one of \"http\" or \"https\".",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_InvalidScheme() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      metadata: .receivedWithInvalidScheme,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-status-message": ":scheme header must be present and one of \"http\" or \"https\".",
        ]
      )
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

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-accept-encoding": "deflate",
          "grpc-status": "12",
          "grpc-status-message":
            "gzip compression is not supported; supported algorithms are listed in grpc-accept-encoding",
        ]
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
        metadata: []
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
        metadata: []
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
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
  }

  func testNextInboundMessageWhenClientOpenAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
  }

  func testNextInboundMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    let receivedBytes = ByteBuffer(bytes: [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ])
    try stateMachine.receive(message: receivedBytes, endStream: false)

    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage([42, 42]))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
  }

  func testNextInboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = self.makeServerStateMachine(
      targetState: .clientOpenServerOpen,
      compressionEnabled: true
    )

    let originalMessage = [UInt8]([42, 42, 43, 43])
    let receivedBytes = try self.frameMessage(originalMessage, compress: true)

    try stateMachine.receive(message: receivedBytes, endStream: false)

    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(originalMessage))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
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
        metadata: []
      )
    )

    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage([42, 42]))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
  }

  func testNextInboundMessageWhenClientClosedAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
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
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage([42, 42]))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
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
        metadata: []
      )
    )

    // Close client
    XCTAssertNoThrow(try stateMachine.receive(message: .init(), endStream: true))

    // Even though the client and server are closed, because the server received
    // a message while the client was still open, we must get the message now.
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage([42, 42]))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
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
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
    try stateMachine.receive(message: secondMessage, endStream: false)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(deframedMessage))

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
      metadata: []
    )
    XCTAssertEqual(response, ["grpc-status": "0"])

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
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
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
    try stateMachine.receive(message: secondMessage, endStream: false)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(deframedMessage))

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
      metadata: []
    )
    XCTAssertEqual(response, ["grpc-status": "0"])

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
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
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
    try stateMachine.receive(message: secondMessage, endStream: false)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(deframedMessage))

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
      metadata: []
    )
    XCTAssertEqual(response, ["grpc-status": "0"])

    XCTAssertEqual(try stateMachine.nextOutboundMessage(), .noMoreMessages)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
  }
}

extension XCTestCase {
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  func assertRejectedRPC(
    _ action: GRPCStreamStateMachine.OnMetadataReceived,
    expression: (HPACKHeaders) throws -> Void
  ) rethrows {
    guard case .rejectRPC(let trailers) = action else {
      XCTFail("RPC should have been rejected.")
      return
    }
    try expression(trailers)
  }

  func frameMessage(_ message: [UInt8], compress: Bool) throws -> ByteBuffer {
    try frameMessages([message], compress: compress)
  }

  func frameMessages(_ messages: [[UInt8]], compress: Bool) throws -> ByteBuffer {
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
