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
import NIOEmbedded
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
    GRPCHTTP2Keys.path.rawValue: "/test/test",
    GRPCHTTP2Keys.scheme.rawValue: "http",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "trailers",
  ]
  fileprivate static let clientInitialMetadataWithDeflateCompression: Self = [
    GRPCHTTP2Keys.path.rawValue: "/test/test",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.scheme.rawValue: "https",
    GRPCHTTP2Keys.te.rawValue: "trailers",
    GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
    GRPCHTTP2Keys.encoding.rawValue: "deflate",
  ]
  fileprivate static let clientInitialMetadataWithGzipCompression: Self = [
    GRPCHTTP2Keys.path.rawValue: "/test/test",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.scheme.rawValue: "https",
    GRPCHTTP2Keys.te.rawValue: "trailers",
    GRPCHTTP2Keys.acceptEncoding.rawValue: "gzip",
    GRPCHTTP2Keys.encoding.rawValue: "gzip",
  ]
  fileprivate static let receivedWithoutContentType: Self = [
    GRPCHTTP2Keys.path.rawValue: "/test/test"
  ]
  fileprivate static let receivedWithInvalidContentType: Self = [
    GRPCHTTP2Keys.path.rawValue: "/test/test",
    GRPCHTTP2Keys.contentType.rawValue: "invalid/invalid",
  ]
  fileprivate static let receivedWithInvalidPath: Self = [
    GRPCHTTP2Keys.path.rawValue: "someinvalidpath",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
  ]
  fileprivate static let receivedWithoutEndpoint: Self = [
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc"
  ]
  fileprivate static let receivedWithoutTE: Self = [
    GRPCHTTP2Keys.path.rawValue: "/test/test",
    GRPCHTTP2Keys.scheme.rawValue: "http",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
  ]
  fileprivate static let receivedWithInvalidTE: Self = [
    GRPCHTTP2Keys.path.rawValue: "/test/test",
    GRPCHTTP2Keys.scheme.rawValue: "http",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "invalidte",
  ]
  fileprivate static let receivedWithoutMethod: Self = [
    GRPCHTTP2Keys.path.rawValue: "/test/test",
    GRPCHTTP2Keys.scheme.rawValue: "http",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "trailers",
  ]
  fileprivate static let receivedWithInvalidMethod: Self = [
    GRPCHTTP2Keys.path.rawValue: "/test/test",
    GRPCHTTP2Keys.scheme.rawValue: "http",
    GRPCHTTP2Keys.method.rawValue: "GET",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "trailers",
  ]
  fileprivate static let receivedWithoutScheme: Self = [
    GRPCHTTP2Keys.path.rawValue: "/test/test",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "trailers",
  ]
  fileprivate static let receivedWithInvalidScheme: Self = [
    GRPCHTTP2Keys.path.rawValue: "/test/test",
    GRPCHTTP2Keys.scheme.rawValue: "invalidscheme",
    GRPCHTTP2Keys.method.rawValue: "POST",
    GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
    GRPCHTTP2Keys.te.rawValue: "trailers",
  ]

  // Server
  fileprivate static let serverInitialMetadata: Self = [
    GRPCHTTP2Keys.status.rawValue: "200",
    GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
  ]
  fileprivate static let serverInitialMetadataWithDeflateCompression: Self = [
    GRPCHTTP2Keys.status.rawValue: "200",
    GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
    GRPCHTTP2Keys.encoding.rawValue: "deflate",
  ]
  fileprivate static let serverInitialMetadataWithGZIPCompression: Self = [
    GRPCHTTP2Keys.status.rawValue: "200",
    GRPCHTTP2Keys.contentType.rawValue: ContentType.grpc.canonicalValue,
    GRPCHTTP2Keys.encoding.rawValue: "gzip",
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
          outboundEncoding: compressionEnabled ? .deflate : .none,
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
      XCTAssertNoThrow(try stateMachine.receive(headers: serverMetadata, endStream: false))
    case .clientOpenServerClosed:
      // Open client
      XCTAssertNoThrow(try stateMachine.send(metadata: []))
      // Open server
      XCTAssertNoThrow(try stateMachine.receive(headers: serverMetadata, endStream: false))
      // Close server
      XCTAssertNoThrow(try stateMachine.receive(headers: .serverTrailers, endStream: true))
    case .clientClosedServerIdle:
      // Open client
      XCTAssertNoThrow(try stateMachine.send(metadata: []))
      // Close client
      XCTAssertNoThrow(try stateMachine.closeOutbound())
    case .clientClosedServerOpen:
      // Open client
      XCTAssertNoThrow(try stateMachine.send(metadata: []))
      // Open server
      XCTAssertNoThrow(try stateMachine.receive(headers: serverMetadata, endStream: false))
      // Close client
      XCTAssertNoThrow(try stateMachine.closeOutbound())
    case .clientClosedServerClosed:
      // Open client
      XCTAssertNoThrow(try stateMachine.send(metadata: []))
      // Open server
      XCTAssertNoThrow(try stateMachine.receive(headers: serverMetadata, endStream: false))
      // Close client
      XCTAssertNoThrow(try stateMachine.closeOutbound())
      // Close server
      XCTAssertNoThrow(try stateMachine.receive(headers: .serverTrailers, endStream: true))
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
      try stateMachine.send(message: [], promise: nil)
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
      XCTAssertNoThrow(try stateMachine.send(message: [], promise: nil))
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
        try stateMachine.send(message: [], promise: nil)
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
      try stateMachine.receive(headers: .init(), endStream: false)
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
        headers: [GRPCHTTP2Keys.status.rawValue: "300"],
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

  func testReceiveInitialMetadataWhenServerIdle_ClientUnsupportedEncoding() throws {
    // Create client with deflate compression enabled
    var stateMachine = self.makeClientStateMachine(
      targetState: .clientOpenServerIdle,
      compressionEnabled: true
    )

    // Try opening server with gzip compression, which client does not support.
    let action = try stateMachine.receive(
      headers: .serverInitialMetadataWithGZIPCompression,
      endStream: false
    )

    XCTAssertEqual(
      action,
      .receivedStatusAndMetadata(
        status: Status(
          code: .internalError,
          message:
            "The server picked a compression algorithm ('gzip') the client does not know about."
        ),
        metadata: [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-encoding": "gzip",
        ]
      )
    )
  }

  func testReceiveMessage_ClientCompressionEnabled() throws {
    // Enable deflate compression on client
    var stateMachine = self.makeClientStateMachine(
      targetState: .clientOpenServerOpen,
      compressionEnabled: true
    )

    let originalMessage = [UInt8]([42, 42, 43, 43])

    // Receiving uncompressed message should still work.
    let receivedUncompressedBytes = try self.frameMessage(originalMessage, compression: .none)
    XCTAssertNoThrow(try stateMachine.receive(buffer: receivedUncompressedBytes, endStream: false))
    var receivedAction = stateMachine.nextInboundMessage()
    switch receivedAction {
    case .noMoreMessages, .awaitMoreMessages:
      XCTFail("Should have received message")
    case .receiveMessage(let receivedMessaged):
      XCTAssertEqual(originalMessage, receivedMessaged)
    }

    // Receiving compressed message with deflate should work
    let receivedDeflateCompressedBytes = try self.frameMessage(
      originalMessage,
      compression: .deflate
    )
    XCTAssertNoThrow(
      try stateMachine.receive(buffer: receivedDeflateCompressedBytes, endStream: false)
    )
    receivedAction = stateMachine.nextInboundMessage()
    switch receivedAction {
    case .noMoreMessages, .awaitMoreMessages:
      XCTFail("Should have received message")
    case .receiveMessage(let receivedMessaged):
      XCTAssertEqual(originalMessage, receivedMessaged)
    }

    // Receiving compressed message with gzip (unsupported) should throw error
    let receivedGZIPCompressedBytes = try self.frameMessage(originalMessage, compression: .gzip)
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(buffer: receivedGZIPCompressedBytes, endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Decompression error")
    }
    receivedAction = stateMachine.nextInboundMessage()
    switch receivedAction {
    case .awaitMoreMessages:
      ()
    case .noMoreMessages:
      XCTFail("Should be awaiting for more messages")
    case .receiveMessage:
      XCTFail("Should not have received message")
    }
  }

  func testReceiveInitialMetadataWhenServerIdle() throws {
    for targetState in [
      TargetStateMachineState.clientOpenServerIdle, .clientClosedServerIdle,
    ] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Receive metadata = open server
      let action = try stateMachine.receive(
        headers: [
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
      XCTAssertEqual(action, .receivedMetadata(expectedMetadata, nil))
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
          headers: [
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
        headers: [
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
        try stateMachine.receive(headers: .init(), endStream: false)
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
      try stateMachine.receive(headers: .init(), endStream: true)
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
        "Some, status, message"
      )!,
      "custom-key": "custom-value",
    ]
    let trailers = try stateMachine.receive(headers: trailersOnlyResponse, endStream: true)
    switch trailers {
    case .receivedStatusAndMetadata(let status, let metadata):
      XCTAssertEqual(status, Status(code: .internalError, message: "Some, status, message"))
      XCTAssertEqual(
        metadata,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "custom-key": "custom-value",
        ]
      )
    case .receivedMetadata, .doNothing, .rejectRPC, .protocolViolation:
      XCTFail("Expected .receivedStatusAndMetadata")
    }
  }

  func testReceiveEndTrailerWhenServerOpen() throws {
    for targetState in [TargetStateMachineState.clientOpenServerOpen, .clientClosedServerOpen] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      // Receive an end trailer
      let action = try stateMachine.receive(
        headers: [
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
      try stateMachine.receive(headers: .init(), endStream: true)
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
    let trailers = try stateMachine.receive(headers: trailersOnlyResponse, endStream: true)
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
    case .receivedMetadata, .doNothing, .rejectRPC, .protocolViolation:
      XCTFail("Expected .receivedStatusAndMetadata")
    }
  }

  func testReceiveEndTrailerWhenClientClosedAndServerClosed() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientClosedServerClosed)

    // Close server again (endStream = true) and assert we don't throw.
    // This can happen if the previous close was caused by a grpc-status header
    // and then the server sends an empty frame with EOS set.
    XCTAssertEqual(try stateMachine.receive(headers: .init(), endStream: true), .doNothing)
  }

  // - MARK: Receive message

  func testReceiveMessageWhenClientIdleAndServerIdle() {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(buffer: .init(), endStream: false)
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
        try stateMachine.receive(buffer: .init(), endStream: false)
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

      XCTAssertEqual(
        try stateMachine.receive(buffer: .init(), endStream: false),
        .readInbound
      )
      XCTAssertEqual(
        try stateMachine.receive(buffer: .init(), endStream: true),
        .endRPCAndForwardErrorStatus(
          Status(
            code: .internalError,
            message: """
              Server sent EOS alongside a data frame, but server is only allowed \
              to close by sending status and trailers.
              """
          )
        )
      )
    }
  }

  func testReceiveMessageWhenServerClosed() {
    for targetState in [TargetStateMachineState.clientOpenServerClosed, .clientClosedServerClosed] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      XCTAssertThrowsError(
        ofType: RPCError.self,
        try stateMachine.receive(buffer: .init(), endStream: false)
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
      try stateMachine.nextOutboundFrame()
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client is not open yet.")
    }
  }

  func testNextOutboundMessageWhenClientOpenAndServerOpenOrIdle() throws {
    for targetState in [TargetStateMachineState.clientOpenServerIdle, .clientOpenServerOpen] {
      var stateMachine = self.makeClientStateMachine(targetState: targetState)

      XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)

      XCTAssertNoThrow(try stateMachine.send(message: [42, 42], promise: nil))

      let expectedBytes: [UInt8] = [
        0,  // compression flag: unset
        0, 0, 0, 2,  // message length: 2 bytes
        42, 42,  // original message
      ]
      XCTAssertEqual(
        try stateMachine.nextOutboundFrame(),
        .sendFrame(frame: ByteBuffer(bytes: expectedBytes), promise: nil)
      )

      // And then make sure that nothing else is returned anymore
      XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)
    }
  }

  func testNextOutboundMessageWhenClientOpenAndServerIdle_WithCompression() throws {
    var stateMachine = self.makeClientStateMachine(
      targetState: .clientOpenServerIdle,
      compressionEnabled: true
    )

    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)

    let originalMessage = [UInt8]([42, 42, 43, 43])
    XCTAssertNoThrow(try stateMachine.send(message: originalMessage, promise: nil))

    let request = try stateMachine.nextOutboundFrame()
    let framedMessage = try self.frameMessage(originalMessage, compression: .deflate)
    XCTAssertEqual(request, .sendFrame(frame: framedMessage, promise: nil))
  }

  func testNextOutboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = self.makeClientStateMachine(
      targetState: .clientOpenServerOpen,
      compressionEnabled: true
    )

    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)

    let originalMessage = [UInt8]([42, 42, 43, 43])
    XCTAssertNoThrow(try stateMachine.send(message: originalMessage, promise: nil))

    let request = try stateMachine.nextOutboundFrame()
    let framedMessage = try self.frameMessage(originalMessage, compression: .deflate)
    XCTAssertEqual(request, .sendFrame(frame: framedMessage, promise: nil))
  }

  func testNextOutboundMessageWhenClientOpenAndServerClosed() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerClosed)

    // No more messages to send
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)

    // Queue a message, but assert the action is .noMoreMessages nevertheless,
    // because the server is closed.
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], promise: nil))
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
  }

  func testNextOutboundMessageWhenClientClosedAndServerIdle() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerIdle)

    // Send a message and close client
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], promise: nil))
    XCTAssertNoThrow(try stateMachine.closeOutbound())

    // Make sure that getting the next outbound message _does_ return the message
    // we have enqueued.
    let request = try stateMachine.nextOutboundFrame()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ]
    XCTAssertEqual(request, .sendFrame(frame: ByteBuffer(bytes: expectedBytes), promise: nil))

    // And then make sure that nothing else is returned anymore
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
  }

  func testNextOutboundMessageWhenClientClosedAndServerOpen() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerOpen)

    // Send a message and close client
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], promise: nil))
    XCTAssertNoThrow(try stateMachine.closeOutbound())

    // Make sure that getting the next outbound message _does_ return the message
    // we have enqueued.
    let request = try stateMachine.nextOutboundFrame()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ]
    XCTAssertEqual(request, .sendFrame(frame: ByteBuffer(bytes: expectedBytes), promise: nil))

    // And then make sure that nothing else is returned anymore
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
  }

  func testNextOutboundMessageWhenClientClosedAndServerClosed() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientOpenServerOpen)
    // Send a message
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], promise: nil))

    // Close server
    XCTAssertNoThrow(try stateMachine.receive(headers: .serverTrailers, endStream: true))

    // Close client
    XCTAssertNoThrow(try stateMachine.closeOutbound())

    // Even though we have enqueued a message, don't send it, because the server
    // is closed.
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
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
    XCTAssertEqual(
      try stateMachine.receive(buffer: receivedBytes, endStream: false),
      .readInbound
    )

    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage([42, 42]))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
  }

  func testNextInboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = self.makeClientStateMachine(
      targetState: .clientOpenServerOpen,
      compressionEnabled: true
    )

    let originalMessage = [UInt8]([42, 42, 43, 43])
    let receivedBytes = try self.frameMessage(originalMessage, compression: .deflate)
    XCTAssertEqual(
      try stateMachine.receive(buffer: receivedBytes, endStream: false),
      .readInbound
    )

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
    XCTAssertEqual(
      try stateMachine.receive(buffer: receivedBytes, endStream: false),
      .readInbound
    )

    // Close server
    XCTAssertNoThrow(try stateMachine.receive(headers: .serverTrailers, endStream: true))

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
    XCTAssertEqual(
      try stateMachine.receive(buffer: receivedBytes, endStream: false),
      .readInbound
    )

    // Close client
    XCTAssertNoThrow(try stateMachine.closeOutbound())

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
    XCTAssertEqual(
      try stateMachine.receive(buffer: receivedBytes, endStream: false),
      .readInbound
    )

    // Close server
    XCTAssertNoThrow(try stateMachine.receive(headers: .serverTrailers, endStream: true))

    // Close client
    XCTAssertNoThrow(try stateMachine.closeOutbound())

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
        GRPCHTTP2Keys.path.rawValue: "/test/test",
        GRPCHTTP2Keys.scheme.rawValue: "http",
        GRPCHTTP2Keys.method.rawValue: "POST",
        GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
        GRPCHTTP2Keys.te.rawValue: "trailers",
        GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
      ]
    )

    // Server sends initial metadata
    let serverInitialHeadersAction = try stateMachine.receive(
      headers: .serverInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      serverInitialHeadersAction,
      .receivedMetadata(
        [
          ":status": "200",
          "content-type": "application/grpc",
        ],
        nil
      )
    )

    // Client sends messages
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)

    let message = [UInt8]([1, 2, 3, 4])
    let framedMessage = try self.frameMessage(message, compression: .none)
    try stateMachine.send(message: message, promise: nil)
    XCTAssertEqual(
      try stateMachine.nextOutboundFrame(),
      .sendFrame(frame: framedMessage, promise: nil)
    )
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)

    // Server sends response
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    let firstResponseBytes = [UInt8]([5, 6, 7])
    let firstResponse = try self.frameMessage(firstResponseBytes, compression: .none)
    let secondResponseBytes = [UInt8]([8, 9, 10])
    let secondResponse = try self.frameMessage(secondResponseBytes, compression: .none)
    XCTAssertEqual(
      try stateMachine.receive(buffer: firstResponse, endStream: false),
      .readInbound
    )
    XCTAssertEqual(
      try stateMachine.receive(buffer: secondResponse, endStream: false),
      .readInbound
    )

    // Make sure messages have arrived
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(firstResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(secondResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    // Client sends end
    XCTAssertNoThrow(try stateMachine.closeOutbound())

    // Server ends
    let metadataReceivedAction = try stateMachine.receive(
      headers: .serverTrailers,
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

    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
  }

  func testClientClosesBeforeItCanOpen() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)
    XCTAssertNoThrow(try stateMachine.closeOutbound())
  }

  func testClientClosesBeforeServerOpens() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)

    // Client sends metadata
    let clientInitialMetadata = try stateMachine.send(metadata: .init())
    XCTAssertEqual(
      clientInitialMetadata,
      [
        GRPCHTTP2Keys.path.rawValue: "/test/test",
        GRPCHTTP2Keys.scheme.rawValue: "http",
        GRPCHTTP2Keys.method.rawValue: "POST",
        GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
        GRPCHTTP2Keys.te.rawValue: "trailers",
        GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
      ]
    )

    // Client sends messages and ends
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)

    let message = [UInt8]([1, 2, 3, 4])
    let framedMessage = try self.frameMessage(message, compression: .none)
    XCTAssertNoThrow(try stateMachine.send(message: message, promise: nil))
    XCTAssertNoThrow(try stateMachine.closeOutbound())
    XCTAssertEqual(
      try stateMachine.nextOutboundFrame(),
      .sendFrame(frame: framedMessage, promise: nil)
    )
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)

    // Server sends initial metadata
    let serverInitialHeadersAction = try stateMachine.receive(
      headers: .serverInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      serverInitialHeadersAction,
      .receivedMetadata(
        [
          ":status": "200",
          "content-type": "application/grpc",
        ],
        nil
      )
    )

    // Server sends response
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    let firstResponseBytes = [UInt8]([5, 6, 7])
    let firstResponse = try self.frameMessage(firstResponseBytes, compression: .none)
    let secondResponseBytes = [UInt8]([8, 9, 10])
    let secondResponse = try self.frameMessage(secondResponseBytes, compression: .none)
    XCTAssertEqual(
      try stateMachine.receive(buffer: firstResponse, endStream: false),
      .readInbound
    )
    XCTAssertEqual(
      try stateMachine.receive(buffer: secondResponse, endStream: false),
      .readInbound
    )

    // Make sure messages have arrived
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(firstResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(secondResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    // Server ends
    let metadataReceivedAction = try stateMachine.receive(
      headers: .serverTrailers,
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

    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
  }

  func testClientClosesBeforeServerResponds() throws {
    var stateMachine = self.makeClientStateMachine(targetState: .clientIdleServerIdle)

    // Client sends metadata
    let clientInitialMetadata = try stateMachine.send(metadata: .init())
    XCTAssertEqual(
      clientInitialMetadata,
      [
        GRPCHTTP2Keys.path.rawValue: "/test/test",
        GRPCHTTP2Keys.scheme.rawValue: "http",
        GRPCHTTP2Keys.method.rawValue: "POST",
        GRPCHTTP2Keys.contentType.rawValue: "application/grpc",
        GRPCHTTP2Keys.te.rawValue: "trailers",
        GRPCHTTP2Keys.acceptEncoding.rawValue: "deflate",
      ]
    )

    // Client sends messages
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)

    let message = [UInt8]([1, 2, 3, 4])
    let framedMessage = try self.frameMessage(message, compression: .none)
    try stateMachine.send(message: message, promise: nil)
    XCTAssertEqual(
      try stateMachine.nextOutboundFrame(),
      .sendFrame(frame: framedMessage, promise: nil)
    )
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)

    // Server sends initial metadata
    let serverInitialHeadersAction = try stateMachine.receive(
      headers: .serverInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      serverInitialHeadersAction,
      .receivedMetadata(
        [
          ":status": "200",
          "content-type": "application/grpc",
        ],
        nil
      )
    )

    // Client closes
    XCTAssertNoThrow(try stateMachine.closeOutbound())

    // Server sends response
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    let firstResponseBytes = [UInt8]([5, 6, 7])
    let firstResponse = try self.frameMessage(firstResponseBytes, compression: .none)
    let secondResponseBytes = [UInt8]([8, 9, 10])
    let secondResponse = try self.frameMessage(secondResponseBytes, compression: .none)
    XCTAssertEqual(
      try stateMachine.receive(buffer: firstResponse, endStream: false),
      .readInbound
    )
    XCTAssertEqual(
      try stateMachine.receive(buffer: secondResponse, endStream: false),
      .readInbound
    )

    // Make sure messages have arrived
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(firstResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(secondResponseBytes))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)

    // Server ends
    let metadataReceivedAction = try stateMachine.receive(
      headers: .serverTrailers,
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

    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class GRPCStreamServerStateMachineTests: XCTestCase {
  private func makeServerStateMachine(
    targetState: TargetStateMachineState,
    deflateCompressionEnabled: Bool = false
  ) -> GRPCStreamStateMachine {

    var stateMachine = GRPCStreamStateMachine(
      configuration: .server(
        .init(
          scheme: .http,
          acceptedEncodings: deflateCompressionEnabled ? [.deflate] : []
        )
      ),
      maximumPayloadSize: 100,
      skipAssertions: true
    )

    let clientMetadata: HPACKHeaders =
      deflateCompressionEnabled
      ? .clientInitialMetadataWithDeflateCompression : .clientInitialMetadata
    switch targetState {
    case .clientIdleServerIdle:
      break
    case .clientOpenServerIdle:
      // Open client
      XCTAssertNoThrow(try stateMachine.receive(headers: clientMetadata, endStream: false))
    case .clientOpenServerOpen:
      // Open client
      XCTAssertNoThrow(try stateMachine.receive(headers: clientMetadata, endStream: false))
      // Open server
      XCTAssertNoThrow(try stateMachine.send(metadata: Metadata(headers: .serverInitialMetadata)))
    case .clientOpenServerClosed:
      // Open client
      XCTAssertNoThrow(try stateMachine.receive(headers: clientMetadata, endStream: false))
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
      XCTAssertNoThrow(try stateMachine.receive(headers: clientMetadata, endStream: false))
      // Close client
      XCTAssertNoThrow(try stateMachine.receive(buffer: .init(), endStream: true))
    case .clientClosedServerOpen:
      // Open client
      XCTAssertNoThrow(try stateMachine.receive(headers: clientMetadata, endStream: false))
      // Open server
      XCTAssertNoThrow(try stateMachine.send(metadata: Metadata(headers: .serverInitialMetadata)))
      // Close client
      XCTAssertNoThrow(try stateMachine.receive(buffer: .init(), endStream: true))
    case .clientClosedServerClosed:
      // Open client
      XCTAssertNoThrow(try stateMachine.receive(headers: clientMetadata, endStream: false))
      // Open server
      XCTAssertNoThrow(try stateMachine.send(metadata: Metadata(headers: .serverInitialMetadata)))
      // Close client
      XCTAssertNoThrow(try stateMachine.receive(buffer: .init(), endStream: true))
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
    var stateMachine = self.makeServerStateMachine(
      targetState: .clientOpenServerIdle,
      deflateCompressionEnabled: false
    )
    XCTAssertEqual(
      try stateMachine.send(metadata: .init()),
      [
        ":status": "200",
        "content-type": "application/grpc",
      ]
    )
  }

  func testSendMetadataWhenClientOpenAndServerIdle_AndCompressionEnabled() {
    // Enable deflate compression on server
    var stateMachine = self.makeServerStateMachine(
      targetState: .clientOpenServerIdle,
      deflateCompressionEnabled: true
    )

    XCTAssertEqual(
      try stateMachine.send(metadata: .init()),
      [
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-encoding": "deflate",
      ]
    )
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
      try stateMachine.send(message: [], promise: nil)
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
      try stateMachine.send(message: [], promise: nil)
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
    XCTAssertNoThrow(try stateMachine.send(message: [], promise: nil))
  }

  func testSendMessageWhenClientOpenAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerClosed)

    // Try sending another message: it should fail
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], promise: nil)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server can't send a message if it's closed.")
    }
  }

  func testSendMessageWhenClientClosedAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], promise: nil)
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
    XCTAssertNoThrow(try stateMachine.send(message: [], promise: nil))
  }

  func testSendMessageWhenClientClosedAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerClosed)

    // Try sending another message: it should fail
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], promise: nil)
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
        "grpc-message": "RPC unknown",
      ]
    )

    // Try sending another message: it should fail because server is now closed.
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], promise: nil)
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
      try stateMachine.send(message: [], promise: nil)
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
        "grpc-message": "RPC unknown",
      ]
    )

    // Try sending another message: it should fail because server is now closed.
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.send(message: [], promise: nil)
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
      try stateMachine.send(message: [], promise: nil)
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

    let action = try stateMachine.receive(headers: .clientInitialMetadata, endStream: false)
    XCTAssertEqual(
      action,
      .receivedMetadata(
        Metadata(headers: .clientInitialMetadata),
        MethodDescriptor(path: "/test/test")
      )
    )
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_WithEndStream() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(headers: .clientInitialMetadata, endStream: true)
    XCTAssertEqual(
      action,
      .receivedMetadata(
        Metadata(headers: .clientInitialMetadata),
        MethodDescriptor(path: "/test/test")
      )
    )
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingContentType() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      headers: .receivedWithoutContentType,
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
      headers: .receivedWithInvalidContentType,
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
      headers: .receivedWithoutEndpoint,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": String(Status.Code.invalidArgument.rawValue),
          "grpc-message": "No :path header has been set.",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_InvalidPath() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      headers: .receivedWithInvalidPath,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": String(Status.Code.unimplemented.rawValue),
          "grpc-message":
            "The given :path (someinvalidpath) does not correspond to a valid method.",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingTE() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      headers: .receivedWithoutTE,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-message":
            "\"te\" header is expected to be present and have a value of \"trailers\".",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_InvalidTE() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      headers: .receivedWithInvalidTE,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-message":
            "\"te\" header is expected to be present and have a value of \"trailers\".",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingMethod() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      headers: .receivedWithoutMethod,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-message":
            ":method header is expected to be present and have a value of \"POST\".",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_InvalidMethod() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      headers: .receivedWithInvalidMethod,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-message":
            ":method header is expected to be present and have a value of \"POST\".",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_MissingScheme() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      headers: .receivedWithoutScheme,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-message": ":scheme header must be present and one of \"http\" or \"https\".",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_InvalidScheme() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    let action = try stateMachine.receive(
      headers: .receivedWithInvalidScheme,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      XCTAssertEqual(
        trailers,
        [
          ":status": "200",
          "content-type": "application/grpc",
          "grpc-status": "3",
          "grpc-message": ":scheme header must be present and one of \"http\" or \"https\".",
        ]
      )
    }
  }

  func testReceiveMetadataWhenClientIdleAndServerIdle_ServerUnsupportedEncoding() throws {
    var stateMachine = self.makeServerStateMachine(
      targetState: .clientIdleServerIdle,
      deflateCompressionEnabled: true
    )

    // Try opening client with a compression algorithm that is not accepted
    // by the server.
    let action = try stateMachine.receive(
      headers: .clientInitialMetadataWithGzipCompression,
      endStream: false
    )

    self.assertRejectedRPC(action) { trailers in
      let expected: HPACKHeaders = [
        ":status": "200",
        "content-type": "application/grpc",
        "grpc-status": "12",
        "grpc-message":
          "gzip compression is not supported; supported algorithms are listed in grpc-accept-encoding",
        "grpc-accept-encoding": "deflate",
        "grpc-accept-encoding": "identity",
      ]
      XCTAssertEqual(expected.count, trailers.count, "Expected \(expected) but got \(trailers)")
      for header in trailers {
        XCTAssertTrue(
          expected.contains { name, value, _ in
            header.name == name && header.value == header.value
          }
        )
      }
    }
  }

  func testReceiveMetadataWhenClientOpenAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    // Try receiving initial metadata again - should be a protocol violation
    let action = try stateMachine.receive(headers: .clientInitialMetadata, endStream: false)
    XCTAssertEqual(action, .protocolViolation)
  }

  func testReceiveMetadataWhenClientOpenAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    let action = try stateMachine.receive(headers: .clientInitialMetadata, endStream: false)
    XCTAssertEqual(action, .protocolViolation)
  }

  func testReceiveMetadataWhenClientOpenAndServerClosed() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerClosed)

    let action = try stateMachine.receive(headers: .clientInitialMetadata, endStream: false)
    XCTAssertEqual(action, .protocolViolation)
  }

  func testReceiveMetadataWhenClientClosedAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(headers: .clientInitialMetadata, endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't have sent metadata if closed.")
    }
  }

  func testReceiveMetadataWhenClientClosedAndServerOpen() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerOpen)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(headers: .clientInitialMetadata, endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't have sent metadata if closed.")
    }
  }

  func testReceiveMetadataWhenClientClosedAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerClosed)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(headers: .clientInitialMetadata, endStream: false)
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
      try stateMachine.receive(buffer: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Can't have received a message if client is idle.")
    }
  }

  func testReceiveMessageWhenClientOpenAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    // Receive messages successfully: the second one should close client.
    XCTAssertNoThrow(try stateMachine.receive(buffer: .init(), endStream: false))
    XCTAssertNoThrow(try stateMachine.receive(buffer: .init(), endStream: true))

    // Verify client is now closed
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(buffer: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }

  func testReceiveMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    // Receive messages successfully: the second one should close client.
    XCTAssertNoThrow(try stateMachine.receive(buffer: .init(), endStream: false))
    XCTAssertNoThrow(try stateMachine.receive(buffer: .init(), endStream: true))

    // Verify client is now closed
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(buffer: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }

  func testReceiveMessage_ServerCompressionEnabled() throws {
    // Enable deflate compression on server
    var stateMachine = self.makeServerStateMachine(
      targetState: .clientOpenServerOpen,
      deflateCompressionEnabled: true
    )

    let originalMessage = [UInt8]([42, 42, 43, 43])

    // Receiving uncompressed message should still work.
    let receivedUncompressedBytes = try self.frameMessage(originalMessage, compression: .none)
    XCTAssertNoThrow(try stateMachine.receive(buffer: receivedUncompressedBytes, endStream: false))
    var receivedAction = stateMachine.nextInboundMessage()
    switch receivedAction {
    case .noMoreMessages, .awaitMoreMessages:
      XCTFail("Should have received message")
    case .receiveMessage(let receivedMessaged):
      XCTAssertEqual(originalMessage, receivedMessaged)
    }

    // Receiving compressed message with deflate should work
    let receivedDeflateCompressedBytes = try self.frameMessage(
      originalMessage,
      compression: .deflate
    )
    XCTAssertNoThrow(
      try stateMachine.receive(buffer: receivedDeflateCompressedBytes, endStream: false)
    )
    receivedAction = stateMachine.nextInboundMessage()
    switch receivedAction {
    case .noMoreMessages, .awaitMoreMessages:
      XCTFail("Should have received message")
    case .receiveMessage(let receivedMessaged):
      XCTAssertEqual(originalMessage, receivedMessaged)
    }

    // Receiving compressed message with gzip (unsupported) should throw error
    let receivedGZIPCompressedBytes = try self.frameMessage(originalMessage, compression: .gzip)
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(buffer: receivedGZIPCompressedBytes, endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Decompression error")
    }
    receivedAction = stateMachine.nextInboundMessage()
    switch receivedAction {
    case .awaitMoreMessages:
      ()
    case .noMoreMessages:
      XCTFail("Should be awaiting for more messages")
    case .receiveMessage:
      XCTFail("Should not have received message")
    }
  }

  func testReceiveMessageWhenClientOpenAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerClosed)

    // Client is not done sending request, don't fail.
    XCTAssertEqual(try stateMachine.receive(buffer: ByteBuffer(), endStream: false), .doNothing)
  }

  func testReceiveMessageWhenClientClosedAndServerIdle() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(buffer: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }

  func testReceiveMessageWhenClientClosedAndServerOpen() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerOpen)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(buffer: .init(), endStream: false)
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Client can't send a message if closed.")
    }
  }

  func testReceiveMessageWhenClientClosedAndServerClosed() {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerClosed)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.receive(buffer: .init(), endStream: false)
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
      try stateMachine.nextOutboundFrame()
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }

  func testNextOutboundMessageWhenClientOpenAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.nextOutboundFrame()
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }

  func testNextOutboundMessageWhenClientOpenAndServerIdle_WithCompression() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.nextOutboundFrame()
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }

  func testNextOutboundMessageWhenClientOpenAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)

    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], promise: nil))

    let response = try stateMachine.nextOutboundFrame()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ]
    XCTAssertEqual(response, .sendFrame(frame: ByteBuffer(bytes: expectedBytes), promise: nil))

    // And then make sure that nothing else is returned
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)
  }

  func testNextOutboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = self.makeServerStateMachine(
      targetState: .clientOpenServerOpen,
      deflateCompressionEnabled: true
    )

    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)

    let originalMessage = [UInt8]([42, 42, 43, 43])
    XCTAssertNoThrow(try stateMachine.send(message: originalMessage, promise: nil))

    let response = try stateMachine.nextOutboundFrame()
    let framedMessage = try self.frameMessage(originalMessage, compression: .deflate)
    XCTAssertEqual(response, .sendFrame(frame: framedMessage, promise: nil))
  }

  func testNextOutboundMessageWhenClientOpenAndServerClosed() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    // Send message and close server
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], promise: nil))
    XCTAssertNoThrow(
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: []
      )
    )

    let response = try stateMachine.nextOutboundFrame()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ]
    XCTAssertEqual(response, .sendFrame(frame: ByteBuffer(bytes: expectedBytes), promise: nil))

    // And then make sure that nothing else is returned anymore
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
  }

  func testNextOutboundMessageWhenClientClosedAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerIdle)

    XCTAssertThrowsError(
      ofType: RPCError.self,
      try stateMachine.nextOutboundFrame()
    ) { error in
      XCTAssertEqual(error.code, .internalError)
      XCTAssertEqual(error.message, "Server is not open yet.")
    }
  }

  func testNextOutboundMessageWhenClientClosedAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    // Send a message
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], promise: nil))

    // Close client
    XCTAssertNoThrow(try stateMachine.receive(buffer: .init(), endStream: true))

    // Send another message
    XCTAssertNoThrow(try stateMachine.send(message: [43, 43], promise: nil))

    // Make sure that getting the next outbound message _does_ return the message
    // we have enqueued.
    let response = try stateMachine.nextOutboundFrame()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
      // End of first message - beginning of second
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      43, 43,  // original message
    ]
    XCTAssertEqual(response, .sendFrame(frame: ByteBuffer(bytes: expectedBytes), promise: nil))

    // And then make sure that nothing else is returned anymore
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)
  }

  func testNextOutboundMessageWhenClientClosedAndServerClosed() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientClosedServerOpen)

    // Send a message and close server
    XCTAssertNoThrow(try stateMachine.send(message: [42, 42], promise: nil))
    XCTAssertNoThrow(
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: []
      )
    )

    // We have enqueued a message, make sure we return it even though server is closed,
    // because we haven't yet drained all of the pending messages.
    let response = try stateMachine.nextOutboundFrame()
    let expectedBytes: [UInt8] = [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ]
    XCTAssertEqual(response, .sendFrame(frame: ByteBuffer(bytes: expectedBytes), promise: nil))

    // And then make sure that nothing else is returned anymore
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
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
    XCTAssertEqual(
      try stateMachine.receive(buffer: receivedBytes, endStream: false),
      .readInbound
    )

    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage([42, 42]))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
  }

  func testNextInboundMessageWhenClientOpenAndServerOpen_WithCompression() throws {
    var stateMachine = self.makeServerStateMachine(
      targetState: .clientOpenServerOpen,
      deflateCompressionEnabled: true
    )

    let originalMessage = [UInt8]([42, 42, 43, 43])
    let receivedBytes = try self.frameMessage(originalMessage, compression: .deflate)

    XCTAssertEqual(
      try stateMachine.receive(buffer: receivedBytes, endStream: false),
      .readInbound
    )

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
    XCTAssertEqual(
      try stateMachine.receive(buffer: receivedBytes, endStream: false),
      .readInbound
    )

    // Close server
    XCTAssertNoThrow(
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: []
      )
    )

    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
  }

  func testNextInboundMessageWhenClientClosedAndServerIdle() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerIdle)
    let action = try stateMachine.receive(
      buffer: ByteBuffer(repeating: 0, count: 5),
      endStream: true
    )
    XCTAssertEqual(action, .readInbound)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage([]))
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
  }

  func testNextInboundMessageWhenClientClosedAndServerOpen() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientOpenServerOpen)

    let receivedBytes = ByteBuffer(bytes: [
      0,  // compression flag: unset
      0, 0, 0, 2,  // message length: 2 bytes
      42, 42,  // original message
    ])
    XCTAssertEqual(
      try stateMachine.receive(buffer: receivedBytes, endStream: false),
      .readInbound
    )

    // Close client
    XCTAssertNoThrow(try stateMachine.receive(buffer: .init(), endStream: true))

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
    XCTAssertEqual(
      try stateMachine.receive(buffer: receivedBytes, endStream: false),
      .readInbound
    )

    // Close server
    XCTAssertNoThrow(
      try stateMachine.send(
        status: .init(code: .ok, message: ""),
        metadata: []
      )
    )

    // Close client
    XCTAssertNoThrow(try stateMachine.receive(buffer: .init(), endStream: true))

    // The server is closed, the message should be dropped.
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
  }

  // - MARK: Common paths

  func testNormalFlow() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    // Client sends metadata
    let receiveMetadataAction = try stateMachine.receive(
      headers: .clientInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      receiveMetadataAction,
      .receivedMetadata(
        Metadata(headers: .clientInitialMetadata),
        MethodDescriptor(path: "/test/test")
      )
    )

    // Server sends initial metadata
    let sentInitialHeaders = try stateMachine.send(metadata: Metadata(headers: ["custom": "value"]))
    XCTAssertEqual(
      sentInitialHeaders,
      [
        ":status": "200",
        "content-type": "application/grpc",
        "custom": "value",
      ]
    )

    // Client sends messages
    let deframedMessage = [UInt8]([1, 2, 3, 4])
    let completeMessage = try self.frameMessage(deframedMessage, compression: .none)
    // Split message into two parts to make sure the stitching together of the frames works well
    let firstMessage = completeMessage.getSlice(at: 0, length: 4)!
    let secondMessage = completeMessage.getSlice(at: 4, length: completeMessage.readableBytes - 4)!

    XCTAssertEqual(
      try stateMachine.receive(buffer: firstMessage, endStream: false),
      .readInbound
    )
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
    XCTAssertEqual(
      try stateMachine.receive(buffer: secondMessage, endStream: false),
      .readInbound
    )
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(deframedMessage))

    // Server sends response
    let eventLoop = EmbeddedEventLoop()
    let firstPromise = eventLoop.makePromise(of: Void.self)
    let secondPromise = eventLoop.makePromise(of: Void.self)

    let firstResponse = [UInt8]([5, 6, 7])
    let secondResponse = [UInt8]([8, 9, 10])
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)

    try stateMachine.send(message: firstResponse, promise: firstPromise)
    try stateMachine.send(message: secondResponse, promise: secondPromise)

    // Make sure messages are outbound
    let framedMessages = try self.frameMessages(
      [firstResponse, secondResponse],
      compression: .none
    )

    guard
      case .sendFrame(let nextOutboundByteBuffer, let nextOutboundPromise) =
        try stateMachine.nextOutboundFrame()
    else {
      XCTFail("Should have received .sendMessage")
      return
    }
    XCTAssertEqual(nextOutboundByteBuffer, framedMessages)
    XCTAssertTrue(firstPromise.futureResult === nextOutboundPromise?.futureResult)

    // Make sure that the promises associated with each sent message are chained
    // together: when succeeding the one returned by the state machine on
    // `nextOutboundMessage()`, the others should also be succeeded.
    firstPromise.succeed()
    try secondPromise.futureResult.assertSuccess().wait()

    // Client sends end
    XCTAssertEqual(
      try stateMachine.receive(buffer: ByteBuffer(), endStream: true),
      .readInbound
    )

    // Server ends
    let response = try stateMachine.send(
      status: .init(code: .ok, message: ""),
      metadata: []
    )
    XCTAssertEqual(response, ["grpc-status": "0"])

    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
  }

  func testClientClosesBeforeServerOpens() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    // Client sends metadata
    let receiveMetadataAction = try stateMachine.receive(
      headers: .clientInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      receiveMetadataAction,
      .receivedMetadata(
        Metadata(headers: .clientInitialMetadata),
        MethodDescriptor(path: "/test/test")
      )
    )

    // Client sends messages
    let deframedMessage = [UInt8]([1, 2, 3, 4])
    let completeMessage = try self.frameMessage(deframedMessage, compression: .none)
    // Split message into two parts to make sure the stitching together of the frames works well
    let firstMessage = completeMessage.getSlice(at: 0, length: 4)!
    let secondMessage = completeMessage.getSlice(at: 4, length: completeMessage.readableBytes - 4)!

    XCTAssertEqual(
      try stateMachine.receive(buffer: firstMessage, endStream: false),
      .readInbound
    )
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
    XCTAssertEqual(
      try stateMachine.receive(buffer: secondMessage, endStream: false),
      .readInbound
    )
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(deframedMessage))

    // Client sends end
    XCTAssertEqual(
      try stateMachine.receive(buffer: ByteBuffer(), endStream: true),
      .readInbound
    )

    // Server sends initial metadata
    let sentInitialHeaders = try stateMachine.send(metadata: Metadata(headers: ["custom": "value"]))
    XCTAssertEqual(
      sentInitialHeaders,
      [
        "custom": "value",
        ":status": "200",
        "content-type": "application/grpc",
      ]
    )

    // Server sends response
    let firstResponse = [UInt8]([5, 6, 7])
    let secondResponse = [UInt8]([8, 9, 10])
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)
    try stateMachine.send(message: firstResponse, promise: nil)
    try stateMachine.send(message: secondResponse, promise: nil)

    // Make sure messages are outbound
    let framedMessages = try self.frameMessages(
      [firstResponse, secondResponse],
      compression: .none
    )
    XCTAssertEqual(
      try stateMachine.nextOutboundFrame(),
      .sendFrame(frame: framedMessages, promise: nil)
    )

    // Server ends
    let response = try stateMachine.send(
      status: .init(code: .ok, message: ""),
      metadata: []
    )
    XCTAssertEqual(response, ["grpc-status": "0"])

    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
    XCTAssertEqual(stateMachine.nextInboundMessage(), .noMoreMessages)
  }

  func testClientClosesBeforeServerResponds() throws {
    var stateMachine = self.makeServerStateMachine(targetState: .clientIdleServerIdle)

    // Client sends metadata
    let receiveMetadataAction = try stateMachine.receive(
      headers: .clientInitialMetadata,
      endStream: false
    )
    XCTAssertEqual(
      receiveMetadataAction,
      .receivedMetadata(
        Metadata(headers: .clientInitialMetadata),
        MethodDescriptor(path: "/test/test")
      )
    )

    // Client sends messages
    let deframedMessage = [UInt8]([1, 2, 3, 4])
    let completeMessage = try self.frameMessage(deframedMessage, compression: .none)
    // Split message into two parts to make sure the stitching together of the frames works well
    let firstMessage = completeMessage.getSlice(at: 0, length: 4)!
    let secondMessage = completeMessage.getSlice(at: 4, length: completeMessage.readableBytes - 4)!

    XCTAssertEqual(
      try stateMachine.receive(buffer: firstMessage, endStream: false),
      .readInbound
    )
    XCTAssertEqual(stateMachine.nextInboundMessage(), .awaitMoreMessages)
    XCTAssertEqual(
      try stateMachine.receive(buffer: secondMessage, endStream: false),
      .readInbound
    )
    XCTAssertEqual(stateMachine.nextInboundMessage(), .receiveMessage(deframedMessage))

    // Server sends initial metadata
    let sentInitialHeaders = try stateMachine.send(metadata: Metadata(headers: ["custom": "value"]))
    XCTAssertEqual(
      sentInitialHeaders,
      [
        "custom": "value",
        ":status": "200",
        "content-type": "application/grpc",
      ]
    )

    // Client sends end
    XCTAssertEqual(
      try stateMachine.receive(buffer: ByteBuffer(), endStream: true),
      .readInbound
    )

    // Server sends response
    let firstResponse = [UInt8]([5, 6, 7])
    let secondResponse = [UInt8]([8, 9, 10])
    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .awaitMoreMessages)
    try stateMachine.send(message: firstResponse, promise: nil)
    try stateMachine.send(message: secondResponse, promise: nil)

    // Make sure messages are outbound
    let framedMessages = try self.frameMessages(
      [firstResponse, secondResponse],
      compression: .none
    )
    XCTAssertEqual(
      try stateMachine.nextOutboundFrame(),
      .sendFrame(frame: framedMessages, promise: nil)
    )

    // Server ends
    let response = try stateMachine.send(
      status: .init(code: .ok, message: ""),
      metadata: []
    )
    XCTAssertEqual(response, ["grpc-status": "0"])

    XCTAssertEqual(try stateMachine.nextOutboundFrame(), .noMoreMessages)
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

  func frameMessage(_ message: [UInt8], compression: CompressionAlgorithm) throws -> ByteBuffer {
    try frameMessages([message], compression: compression)
  }

  func frameMessages(_ messages: [[UInt8]], compression: CompressionAlgorithm) throws -> ByteBuffer
  {
    var framer = GRPCMessageFramer()
    let compressor: Zlib.Compressor? = {
      switch compression {
      case .deflate:
        return Zlib.Compressor(method: .deflate)
      case .gzip:
        return Zlib.Compressor(method: .gzip)
      default:
        return nil
      }
    }()
    defer { compressor?.end() }
    for message in messages {
      framer.append(message, promise: nil)
    }
    return try XCTUnwrap(framer.next(compressor: compressor)).bytes
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine.OnNextOutboundFrame {
  public static func == (
    lhs: GRPCStreamStateMachine.OnNextOutboundFrame,
    rhs: GRPCStreamStateMachine.OnNextOutboundFrame
  ) -> Bool {
    switch (lhs, rhs) {
    case (.noMoreMessages, .noMoreMessages):
      return true
    case (.awaitMoreMessages, .awaitMoreMessages):
      return true
    case (.sendFrame(let lhsMessage, _), .sendFrame(let rhsMessage, _)):
      // Note that we're not comparing the EventLoopPromises here, as they're
      // not Equatable. This is fine though, since we only use this in tests.
      return lhsMessage == rhsMessage
    default:
      return false
    }
  }
}

#if compiler(>=6.0)
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine.OnNextOutboundFrame: @retroactive Equatable {}
#else
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCStreamStateMachine.OnNextOutboundFrame: Equatable {}
#endif
