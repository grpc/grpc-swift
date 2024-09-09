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
import GRPCHTTP2Core
import GRPCHTTP2TransportNIOPosix
import GRPCHTTP2TransportNIOTransportServices
import GRPCProtobuf
import XCTest

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class HTTP2TransportTests: XCTestCase {
  // A combination of client and server transport kinds.
  struct Transport: Sendable, CustomStringConvertible {
    var server: Kind
    var client: Kind

    enum Kind: Sendable, CustomStringConvertible {
      case posix
      case niots

      var description: String {
        switch self {
        case .posix:
          return "NIOPosix"
        case .niots:
          return "NIOTS"
        }
      }
    }

    var description: String {
      "server=\(self.server) client=\(self.client)"
    }
  }

  func forEachTransportPair(
    _ transport: [Transport] = .supported,
    enableControlService: Bool = true,
    clientCompression: CompressionAlgorithm = .none,
    clientEnabledCompression: CompressionAlgorithmSet = .none,
    serverCompression: CompressionAlgorithmSet = .none,
    _ execute: (ControlClient, Transport) async throws -> Void
  ) async throws {
    for pair in transport {
      try await withThrowingTaskGroup(of: Void.self) { group in
        let (server, address) = try await self.runServer(
          in: &group,
          kind: pair.server,
          enableControlService: enableControlService,
          compression: serverCompression
        )

        let target: any ResolvableTarget
        if let ipv4 = address.ipv4 {
          target = .ipv4(host: ipv4.host, port: ipv4.port)
        } else if let ipv6 = address.ipv6 {
          target = .ipv6(host: ipv6.host, port: ipv6.port)
        } else if let uds = address.unixDomainSocket {
          target = .unixDomainSocket(path: uds.path)
        } else {
          XCTFail("Unexpected address to connect to")
          return
        }

        let client = try self.makeClient(
          kind: pair.client,
          target: target,
          compression: clientCompression,
          enabledCompression: clientEnabledCompression
        )

        group.addTask {
          try await client.run()
        }

        do {
          let control = ControlClient(wrapping: client)
          try await execute(control, pair)
        } catch {
          XCTFail("Unexpected error: '\(error)' (\(pair))")
        }

        server.beginGracefulShutdown()
        client.beginGracefulShutdown()
      }
    }
  }

  func forEachClientAndHTTPStatusCodeServer(
    _ kind: [Transport.Kind] = [.posix],
    _ execute: (ControlClient, Transport.Kind) async throws -> Void
  ) async throws {
    for clientKind in kind {
      try await withThrowingTaskGroup(of: Void.self) { group in
        let server = HTTP2StatusCodeServer()
        group.addTask {
          try await server.run()
        }

        let address = try await server.listeningAddress
        let client = try self.makeClient(
          kind: clientKind,
          target: .ipv4(host: address.host, port: address.port),
          compression: .none,
          enabledCompression: .none
        )
        group.addTask {
          try await client.run()
        }

        do {
          let control = ControlClient(wrapping: client)
          try await execute(control, clientKind)
        } catch {
          XCTFail("Unexpected error: '\(error)' (\(clientKind))")
        }

        group.cancelAll()
      }
    }
  }

  private func runServer(
    in group: inout ThrowingTaskGroup<Void, any Error>,
    kind: Transport.Kind,
    enableControlService: Bool,
    compression: CompressionAlgorithmSet
  ) async throws -> (GRPCServer, GRPCHTTP2Core.SocketAddress) {
    let services = enableControlService ? [ControlService()] : []

    switch kind {
    case .posix:
      let server = GRPCServer(
        transport: .http2NIOPosix(
          address: .ipv4(host: "127.0.0.1", port: 0),
          config: .defaults(transportSecurity: .plaintext) {
            $0.compression.enabledAlgorithms = compression
          }
        ),
        services: services
      )

      group.addTask {
        try await server.serve()
      }

      let address = try await server.listeningAddress!
      return (server, address)

    case .niots:
      #if canImport(Network)
      let server = GRPCServer(
        transport: .http2NIOTS(
          address: .ipv4(host: "127.0.0.1", port: 0),
          config: .defaults {
            $0.compression.enabledAlgorithms = compression
          }
        ),
        services: services
      )

      group.addTask {
        try await server.serve()
      }

      let address = try await server.listeningAddress!
      return (server, address)
      #else
      throw XCTSkip("Transport not supported on this platform")
      #endif
    }
  }

  private func makeClient(
    kind: Transport.Kind,
    target: any ResolvableTarget,
    compression: CompressionAlgorithm,
    enabledCompression: CompressionAlgorithmSet
  ) throws -> GRPCClient {
    let transport: any ClientTransport

    switch kind {
    case .posix:
      var serviceConfig = ServiceConfig()
      serviceConfig.loadBalancingConfig = [.roundRobin]
      transport = try HTTP2ClientTransport.Posix(
        target: target,
        config: .defaults {
          $0.compression.algorithm = compression
          $0.compression.enabledAlgorithms = enabledCompression
        },
        serviceConfig: serviceConfig
      )

    case .niots:
      fatalError("NIOTS isn't supported yet")
    }

    return GRPCClient(transport: transport)
  }

  func testUnaryOK() async throws {
    // Client sends one message, server sends back metadata, a single message, and an ok status with
    // trailing metadata.
    try await self.forEachTransportPair { control, pair in
      let input = ControlInput.with {
        $0.echoMetadataInHeaders = true
        $0.echoMetadataInTrailers = true
        $0.numberOfMessages = 1
        $0.messageParams = .with {
          $0.content = 0
          $0.size = 1024
        }
      }

      let metadata: Metadata = ["test-key": "test-value"]
      let request = ClientRequest.Single(message: input, metadata: metadata)

      try await control.unary(request: request) { response in
        let message = try response.message
        XCTAssertEqual(message.payload, Data(repeating: 0, count: 1024), "\(pair)")

        let initial = response.metadata
        XCTAssertEqual(Array(initial["echo-test-key"]), ["test-value"], "\(pair)")

        let trailing = response.trailingMetadata
        XCTAssertEqual(Array(trailing["echo-test-key"]), ["test-value"], "\(pair)")
      }
    }
  }

  func testUnaryNotOK() async throws {
    // Client sends one message, server sends back metadata, a single message, and a non-ok status
    // with trailing metadata.
    try await self.forEachTransportPair { control, pair in
      let input = ControlInput.with {
        $0.echoMetadataInTrailers = true
        $0.numberOfMessages = 1
        $0.messageParams = .with {
          $0.content = 0
          $0.size = 1024
        }
        $0.status = .with {
          $0.code = .aborted
          $0.message = "\(#function)"
        }
      }

      let metadata: Metadata = ["test-key": "test-value"]
      let request = ClientRequest.Single(message: input, metadata: metadata)

      try await control.unary(request: request) { response in
        XCTAssertThrowsError(ofType: RPCError.self, try response.message) { error in
          XCTAssertEqual(error.code, .aborted)
          XCTAssertEqual(error.message, "\(#function)")

          let trailing = error.metadata
          XCTAssertEqual(Array(trailing["echo-test-key"]), ["test-value"], "\(pair)")
        }

        let trailing = response.trailingMetadata
        XCTAssertEqual(Array(trailing["echo-test-key"]), ["test-value"], "\(pair)")
      }
    }
  }

  func testUnaryRejected() async throws {
    // Client sends one message, server sends non-ok status with trailing metadata.
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      let request = ClientRequest.Single<ControlInput>(
        message: .trailersOnly(code: .aborted, message: "\(#function)", echoMetadata: true),
        metadata: metadata
      )

      try await control.unary(request: request) { response in
        XCTAssertThrowsError(ofType: RPCError.self, try response.message) { error in
          XCTAssertEqual(error.code, .aborted, "\(pair)")
          XCTAssertEqual(error.message, "\(#function)", "\(pair)")

          let trailing = error.metadata
          XCTAssertEqual(Array(trailing["echo-test-key"]), ["test-value"], "\(pair)")
        }

        // No initial metadata for trailers-only.
        XCTAssertEqual(response.metadata, [:])

        let trailing = response.trailingMetadata
        XCTAssertEqual(Array(trailing["echo-test-key"]), ["test-value"], "\(pair)")
      }
    }
  }

  func testClientStreamingOK() async throws {
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      let request = ClientRequest.Stream(
        of: ControlInput.self,
        metadata: metadata
      ) { writer in
        try await writer.write(.echoMetadata)
        // Send a few messages which are ignored.
        try await writer.write(.noOp)
        try await writer.write(.noOp)
        try await writer.write(.noOp)
        // Send a message.
        try await writer.write(.messages(1, repeating: 42, count: 1024))
        // ... and the final status.
        try await writer.write(.status(code: .ok, message: "", echoMetadata: true))
      }

      try await control.clientStream(request: request) { response in
        let message = try response.message
        XCTAssertEqual(message.payload, Data(repeating: 42, count: 1024), "\(pair)")

        let initial = response.metadata
        XCTAssertEqual(Array(initial["echo-test-key"]), ["test-value"], "\(pair)")

        let trailing = response.trailingMetadata
        XCTAssertEqual(Array(trailing["echo-test-key"]), ["test-value"], "\(pair)")
      }
    }
  }

  func testClientStreamingNotOK() async throws {
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      let request = ClientRequest.Stream(
        of: ControlInput.self,
        metadata: metadata
      ) { writer in
        try await writer.write(.echoMetadata)
        // Send a few messages which are ignored.
        try await writer.write(.noOp)
        try await writer.write(.noOp)
        try await writer.write(.noOp)
        // Send a message.
        try await writer.write(.messages(1, repeating: 42, count: 1024))
        // Send the final status.
        try await writer.write(.status(code: .aborted, message: "\(#function)", echoMetadata: true))
      }

      try await control.clientStream(request: request) { response in
        XCTAssertThrowsError(ofType: RPCError.self, try response.message) { error in
          XCTAssertEqual(error.code, .aborted, "\(pair)")
          XCTAssertEqual(error.message, "\(#function)", "\(pair)")

          let trailing = error.metadata
          XCTAssertEqual(Array(trailing["echo-test-key"]), ["test-value"], "\(pair)")
        }

        let initial = response.metadata
        XCTAssertEqual(Array(initial["echo-test-key"]), ["test-value"], "\(pair)")

        let trailing = response.trailingMetadata
        XCTAssertEqual(Array(trailing["echo-test-key"]), ["test-value"], "\(pair)")
      }
    }
  }

  func testClientStreamingRejected() async throws {
    // Client sends one message, server sends non-ok status with trailing metadata.
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      let request = ClientRequest.Stream(
        of: ControlInput.self,
        metadata: metadata
      ) { writer in
        let message: ControlInput = .trailersOnly(
          code: .aborted,
          message: "\(#function)",
          echoMetadata: true
        )

        try await writer.write(message)
      }

      try await control.clientStream(request: request) { response in
        XCTAssertThrowsError(ofType: RPCError.self, try response.message) { error in
          XCTAssertEqual(error.code, .aborted, "\(pair)")
          XCTAssertEqual(error.message, "\(#function)", "\(pair)")

          let trailing = error.metadata
          XCTAssertEqual(Array(trailing["echo-test-key"]), ["test-value"], "\(pair)")
        }

        // No initial metadata for trailers-only.
        XCTAssertEqual(response.metadata, [:])

        let trailing = response.trailingMetadata
        XCTAssertEqual(Array(trailing["echo-test-key"]), ["test-value"], "\(pair)")
      }
    }
  }

  func testServerStreamingOK() async throws {
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      let input = ControlInput.with {
        $0.echoMetadataInHeaders = true
        $0.echoMetadataInTrailers = true
        $0.numberOfMessages = 5
        $0.messageParams = .with {
          $0.content = 42
          $0.size = 1024
        }
      }

      let request = ClientRequest.Single(message: input, metadata: metadata)
      try await control.serverStream(request: request) { response in
        switch response.accepted {
        case .success(let contents):
          XCTAssertEqual(Array(contents.metadata["echo-test-key"]), ["test-value"], "\(pair)")

          var messagesReceived = 0
          for try await part in contents.bodyParts {
            switch part {
            case .message(let message):
              messagesReceived += 1
              XCTAssertEqual(message.payload, Data(repeating: 42, count: 1024))
            case .trailingMetadata(let metadata):
              XCTAssertEqual(Array(metadata["echo-test-key"]), ["test-value"], "\(pair)")
            }
          }

          XCTAssertEqual(messagesReceived, 5)

        case .failure(let error):
          throw error
        }
      }
    }
  }

  func testServerStreamingEmptyOK() async throws {
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      // Echo back metadata, but don't send any messages.
      let input = ControlInput.with {
        $0.echoMetadataInHeaders = true
        $0.echoMetadataInTrailers = true
      }

      let request = ClientRequest.Single(message: input, metadata: metadata)
      try await control.serverStream(request: request) { response in
        switch response.accepted {
        case .success(let contents):
          XCTAssertEqual(Array(contents.metadata["echo-test-key"]), ["test-value"], "\(pair)")

          for try await part in contents.bodyParts {
            switch part {
            case .message:
              XCTFail("Unexpected message")
            case .trailingMetadata(let metadata):
              XCTAssertEqual(Array(metadata["echo-test-key"]), ["test-value"], "\(pair)")
            }
          }

        case .failure(let error):
          throw error
        }
      }
    }
  }

  func testServerStreamingNotOK() async throws {
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      let input = ControlInput.with {
        $0.echoMetadataInHeaders = true
        $0.echoMetadataInTrailers = true
        $0.numberOfMessages = 5
        $0.messageParams = .with {
          $0.content = 42
          $0.size = 1024
        }
        $0.status = .with {
          $0.code = .aborted
          $0.message = "\(#function)"
        }
      }

      let request = ClientRequest.Single(message: input, metadata: metadata)
      try await control.serverStream(request: request) { response in
        switch response.accepted {
        case .success(let contents):
          XCTAssertEqual(Array(contents.metadata["echo-test-key"]), ["test-value"], "\(pair)")

          var messagesReceived = 0
          do {
            for try await part in contents.bodyParts {
              switch part {
              case .message(let message):
                messagesReceived += 1
                XCTAssertEqual(message.payload, Data(repeating: 42, count: 1024))
              case .trailingMetadata:
                XCTFail("Unexpected trailing metadata, should be provided in RPCError")
              }
            }
            XCTFail("Expected error to be thrown")
          } catch let error as RPCError {
            XCTAssertEqual(error.code, .aborted)
            XCTAssertEqual(error.message, "\(#function)")
            XCTAssertEqual(Array(error.metadata["echo-test-key"]), ["test-value"], "\(pair)")
          }

          XCTAssertEqual(messagesReceived, 5)

        case .failure(let error):
          throw error
        }
      }
    }
  }

  func testServerStreamingEmptyNotOK() async throws {
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      let input = ControlInput.with {
        $0.echoMetadataInHeaders = true
        $0.echoMetadataInTrailers = true
        $0.status = .with {
          $0.code = .aborted
          $0.message = "\(#function)"
        }
      }

      let request = ClientRequest.Single(message: input, metadata: metadata)
      try await control.serverStream(request: request) { response in
        switch response.accepted {
        case .success(let contents):
          XCTAssertEqual(Array(contents.metadata["echo-test-key"]), ["test-value"], "\(pair)")

          do {
            for try await _ in contents.bodyParts {
              XCTFail("Unexpected message, \(pair)")
            }
            XCTFail("Expected error to be thrown")
          } catch let error as RPCError {
            XCTAssertEqual(error.code, .aborted)
            XCTAssertEqual(error.message, "\(#function)")
            XCTAssertEqual(Array(error.metadata["echo-test-key"]), ["test-value"], "\(pair)")
          }

        case .failure(let error):
          throw error
        }
      }
    }
  }

  func testServerStreamingRejected() async throws {
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      let request = ClientRequest.Single<ControlInput>(
        message: .trailersOnly(code: .aborted, message: "\(#function)", echoMetadata: true),
        metadata: metadata
      )

      try await control.serverStream(request: request) { response in
        switch response.accepted {
        case .success:
          XCTFail("Expected RPC to be rejected \(pair)")
        case .failure(let error):
          XCTAssertEqual(error.code, .aborted, "\(pair)")
          XCTAssertEqual(error.message, "\(#function)", "\(pair)")
          XCTAssertEqual(Array(error.metadata["echo-test-key"]), ["test-value"], "\(pair)")
        }
      }
    }
  }

  func testBidiStreamingOK() async throws {
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      let request = ClientRequest.Stream(
        of: ControlInput.self,
        metadata: metadata
      ) { writer in
        try await writer.write(.echoMetadata)
        // Send a few messages, each is echo'd back.
        try await writer.write(.messages(1, repeating: 42, count: 1024))
        try await writer.write(.messages(1, repeating: 42, count: 1024))
        try await writer.write(.messages(1, repeating: 42, count: 1024))
        // Send the final status.
        try await writer.write(.status(code: .ok, message: "", echoMetadata: true))
      }

      try await control.bidiStream(request: request) { response in
        switch response.accepted {
        case .success(let contents):
          XCTAssertEqual(Array(contents.metadata["echo-test-key"]), ["test-value"], "\(pair)")

          var messagesReceived = 0
          for try await part in contents.bodyParts {
            switch part {
            case .message(let message):
              messagesReceived += 1
              XCTAssertEqual(message.payload, Data(repeating: 42, count: 1024))
            case .trailingMetadata(let metadata):
              XCTAssertEqual(Array(metadata["echo-test-key"]), ["test-value"], "\(pair)")
            }
          }
          XCTAssertEqual(messagesReceived, 3)

        case .failure(let error):
          throw error
        }
      }
    }
  }

  func testBidiStreamingEmptyOK() async throws {
    try await self.forEachTransportPair { control, pair in
      let request = ClientRequest.Stream(of: ControlInput.self) { _ in }
      try await control.bidiStream(request: request) { response in
        switch response.accepted {
        case .success(let contents):
          var receivedTrailingMetadata = false
          for try await part in contents.bodyParts {
            switch part {
            case .message:
              XCTFail("Unexpected message \(pair)")
            case .trailingMetadata:
              XCTAssertFalse(receivedTrailingMetadata, "\(pair)")
              receivedTrailingMetadata = true
            }
          }
        case .failure(let error):
          throw error
        }
      }
    }
  }

  func testBidiStreamingNotOK() async throws {
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      let request = ClientRequest.Stream(
        of: ControlInput.self,
        metadata: metadata
      ) { writer in
        try await writer.write(.echoMetadata)
        // Send a few messages, each is echo'd back.
        try await writer.write(.messages(1, repeating: 42, count: 1024))
        try await writer.write(.messages(1, repeating: 42, count: 1024))
        try await writer.write(.messages(1, repeating: 42, count: 1024))
        // Send the final status.
        try await writer.write(.status(code: .aborted, message: "\(#function)", echoMetadata: true))
      }

      try await control.bidiStream(request: request) { response in
        switch response.accepted {
        case .success(let contents):
          XCTAssertEqual(Array(contents.metadata["echo-test-key"]), ["test-value"], "\(pair)")

          var messagesReceived = 0
          do {
            for try await part in contents.bodyParts {
              switch part {
              case .message(let message):
                messagesReceived += 1
                XCTAssertEqual(message.payload, Data(repeating: 42, count: 1024))
              case .trailingMetadata:
                XCTFail("Trailing metadata should be provided by error")
              }
            }
            XCTFail("Should've thrown error \(pair)")
          } catch let error as RPCError {
            XCTAssertEqual(error.code, .aborted)
            XCTAssertEqual(error.message, "\(#function)")
            XCTAssertEqual(Array(error.metadata["echo-test-key"]), ["test-value"], "\(pair)")
          }

          XCTAssertEqual(messagesReceived, 3)

        case .failure(let error):
          throw error
        }
      }
    }
  }

  func testBidiStreamingRejected() async throws {
    try await self.forEachTransportPair { control, pair in
      let metadata: Metadata = ["test-key": "test-value"]
      let request = ClientRequest.Stream(
        of: ControlInput.self,
        metadata: metadata
      ) { writer in
        try await writer.write(
          .trailersOnly(
            code: .aborted,
            message: "\(#function)",
            echoMetadata: true
          )
        )
      }

      try await control.bidiStream(request: request) { response in
        switch response.accepted {
        case .success:
          XCTFail("Expected RPC to fail \(pair)")
        case .failure(let error):
          XCTAssertEqual(error.code, .aborted)
          XCTAssertEqual(error.message, "\(#function)")
          XCTAssertEqual(Array(error.metadata["echo-test-key"]), ["test-value"])
        }
      }
    }
  }

  // MARK: - Not Implemented

  func testUnaryNotImplemented() async throws {
    try await self.forEachTransportPair(enableControlService: false) { control, pair in
      let request = ClientRequest.Single(message: ControlInput())
      try await control.unary(request: request) { response in
        XCTAssertThrowsError(ofType: RPCError.self, try response.message) { error in
          XCTAssertEqual(error.code, .unimplemented)
        }
      }
    }
  }

  func testClientStreamingNotImplemented() async throws {
    try await self.forEachTransportPair(enableControlService: false) { control, pair in
      let request = ClientRequest.Stream(of: ControlInput.self) { _ in }
      try await control.clientStream(request: request) { response in
        XCTAssertThrowsError(ofType: RPCError.self, try response.message) { error in
          XCTAssertEqual(error.code, .unimplemented)
        }
      }
    }
  }

  func testServerStreamingNotImplemented() async throws {
    try await self.forEachTransportPair(enableControlService: false) { control, pair in
      let request = ClientRequest.Single(message: ControlInput())
      try await control.serverStream(request: request) { response in
        XCTAssertThrowsError(ofType: RPCError.self, try response.accepted.get()) { error in
          XCTAssertEqual(error.code, .unimplemented)
        }
      }
    }
  }

  func testBidiStreamingNotImplemented() async throws {
    try await self.forEachTransportPair(enableControlService: false) { control, pair in
      let request = ClientRequest.Stream(of: ControlInput.self) { _ in }
      try await control.bidiStream(request: request) { response in
        XCTAssertThrowsError(ofType: RPCError.self, try response.accepted.get()) { error in
          XCTAssertEqual(error.code, .unimplemented)
        }
      }
    }
  }

  // MARK: - Compression tests

  private func testUnaryCompression(
    client: CompressionAlgorithm,
    server: CompressionAlgorithm,
    control: ControlClient,
    pair: Transport
  ) async throws {
    let message = ControlInput.with {
      $0.echoMetadataInHeaders = true
      $0.numberOfMessages = 1
      $0.messageParams = .with {
        $0.content = 42
        $0.size = 1024
      }
    }

    var options = CallOptions.defaults
    options.compression = client

    try await control.unary(
      request: ClientRequest.Single(message: message),
      options: options
    ) { response in
      // Check the client algorithm.
      switch client {
      case .deflate, .gzip:
        // "echo-grpc-encoding" is the value of "grpc-encoding" sent from the client to the server.
        let encoding = Array(response.metadata["echo-grpc-encoding"])
        XCTAssertEqual(encoding, ["\(client.name)"], "\(pair)")
      case .none:
        ()
      default:
        XCTFail("Unhandled compression '\(client)'")
      }

      // Check the server algorithm.
      switch server {
      case .deflate, .gzip:
        let encoding = Array(response.metadata["grpc-encoding"])
        XCTAssertEqual(encoding, ["\(server.name)"], "\(pair)")
      case .none:
        ()
      default:
        XCTFail("Unhandled compression '\(client)'")
      }

      let message = try response.message
      XCTAssertEqual(message.payload, Data(repeating: 42, count: 1024), "\(pair)")
    }
  }

  private func testClientStreamingCompression(
    client: CompressionAlgorithm,
    server: CompressionAlgorithm,
    control: ControlClient,
    pair: Transport
  ) async throws {
    let request = ClientRequest.Stream(of: ControlInput.self) { writer in
      try await writer.write(.echoMetadata)
      try await writer.write(.noOp)
      try await writer.write(.noOp)
      try await writer.write(.messages(1, repeating: 42, count: 1024))
    }

    var options = CallOptions.defaults
    options.compression = client

    try await control.clientStream(request: request, options: options) { response in
      // Check the client algorithm.
      switch client {
      case .deflate, .gzip:
        // "echo-grpc-encoding" is the value of "grpc-encoding" sent from the client to the server.
        let encoding = Array(response.metadata["echo-grpc-encoding"])
        XCTAssertEqual(encoding, ["\(client.name)"], "\(pair)")
      case .none:
        ()
      default:
        XCTFail("Unhandled compression '\(client)'")
      }

      // Check the server algorithm.
      switch server {
      case .deflate, .gzip:
        let encoding = Array(response.metadata["grpc-encoding"])
        XCTAssertEqual(encoding, ["\(server.name)"], "\(pair)")
      case .none:
        ()
      default:
        XCTFail("Unhandled compression '\(client)'")
      }

      let message = try response.message
      XCTAssertEqual(message.payload, Data(repeating: 42, count: 1024), "\(pair)")
    }
  }

  private func testServerStreamingCompression(
    client: CompressionAlgorithm,
    server: CompressionAlgorithm,
    control: ControlClient,
    pair: Transport
  ) async throws {
    let message = ControlInput.with {
      $0.echoMetadataInHeaders = true
      $0.numberOfMessages = 5
      $0.messageParams = .with {
        $0.content = 42
        $0.size = 1024
      }
    }

    var options = CallOptions.defaults
    options.compression = client

    try await control.serverStream(
      request: ClientRequest.Single(message: message),
      options: options
    ) { response in
      // Check the client algorithm.
      switch client {
      case .deflate, .gzip:
        // "echo-grpc-encoding" is the value of "grpc-encoding" sent from the client to the server.
        let encoding = Array(response.metadata["echo-grpc-encoding"])
        XCTAssertEqual(encoding, ["\(client.name)"], "\(pair)")
      case .none:
        ()
      default:
        XCTFail("Unhandled compression '\(client)'")
      }

      // Check the server algorithm.
      switch server {
      case .deflate, .gzip:
        let encoding = Array(response.metadata["grpc-encoding"])
        XCTAssertEqual(encoding, ["\(server.name)"], "\(pair)")
      case .none:
        ()
      default:
        XCTFail("Unhandled compression '\(client)'")
      }

      for try await message in response.messages {
        XCTAssertEqual(message.payload, Data(repeating: 42, count: 1024), "\(pair)")
      }
    }
  }

  private func testBidiStreamingCompression(
    client: CompressionAlgorithm,
    server: CompressionAlgorithm,
    control: ControlClient,
    pair: Transport
  ) async throws {
    let request = ClientRequest.Stream(of: ControlInput.self) { writer in
      try await writer.write(.echoMetadata)
      try await writer.write(.messages(1, repeating: 42, count: 1024))
      try await writer.write(.messages(1, repeating: 42, count: 1024))
      try await writer.write(.messages(1, repeating: 42, count: 1024))
    }

    var options = CallOptions.defaults
    options.compression = client

    try await control.bidiStream(request: request, options: options) { response in
      // Check the client algorithm.
      switch client {
      case .deflate, .gzip:
        // "echo-grpc-encoding" is the value of "grpc-encoding" sent from the client to the server.
        let encoding = Array(response.metadata["echo-grpc-encoding"])
        XCTAssertEqual(encoding, ["\(client.name)"], "\(pair)")
      case .none:
        ()
      default:
        XCTFail("Unhandled compression '\(client)'")
      }

      // Check the server algorithm.
      switch server {
      case .deflate, .gzip:
        let encoding = Array(response.metadata["grpc-encoding"])
        XCTAssertEqual(encoding, ["\(server.name)"], "\(pair)")
      case .none:
        ()
      default:
        XCTFail("Unhandled compression '\(client)'")
      }

      for try await message in response.messages {
        XCTAssertEqual(message.payload, Data(repeating: 42, count: 1024), "\(pair)")
      }
    }
  }

  func testUnaryDeflateCompression() async throws {
    try await self.forEachTransportPair(
      clientCompression: .deflate,
      clientEnabledCompression: .deflate,
      serverCompression: .deflate
    ) { control, pair in
      try await self.testUnaryCompression(
        client: .deflate,
        server: .deflate,
        control: control,
        pair: pair
      )
    }
  }

  func testUnaryGzipCompression() async throws {
    try await self.forEachTransportPair(
      clientCompression: .gzip,
      clientEnabledCompression: .gzip,
      serverCompression: .gzip
    ) { control, pair in
      try await self.testUnaryCompression(
        client: .gzip,
        server: .gzip,
        control: control,
        pair: pair
      )
    }
  }

  func testClientStreamingDeflateCompression() async throws {
    try await self.forEachTransportPair(
      clientCompression: .deflate,
      clientEnabledCompression: .deflate,
      serverCompression: .deflate
    ) { control, pair in
      try await self.testClientStreamingCompression(
        client: .deflate,
        server: .deflate,
        control: control,
        pair: pair
      )
    }
  }

  func testClientStreamingGzipCompression() async throws {
    try await self.forEachTransportPair(
      clientCompression: .gzip,
      clientEnabledCompression: .gzip,
      serverCompression: .gzip
    ) { control, pair in
      try await self.testClientStreamingCompression(
        client: .gzip,
        server: .gzip,
        control: control,
        pair: pair
      )
    }
  }

  func testServerStreamingDeflateCompression() async throws {
    try await self.forEachTransportPair(
      clientCompression: .deflate,
      clientEnabledCompression: .deflate,
      serverCompression: .deflate
    ) { control, pair in
      try await self.testServerStreamingCompression(
        client: .deflate,
        server: .deflate,
        control: control,
        pair: pair
      )
    }
  }

  func testServerStreamingGzipCompression() async throws {
    try await self.forEachTransportPair(
      clientCompression: .gzip,
      clientEnabledCompression: .gzip,
      serverCompression: .gzip
    ) { control, pair in
      try await self.testServerStreamingCompression(
        client: .gzip,
        server: .gzip,
        control: control,
        pair: pair
      )
    }
  }

  func testBidiStreamingDeflateCompression() async throws {
    try await self.forEachTransportPair(
      clientCompression: .deflate,
      clientEnabledCompression: .deflate,
      serverCompression: .deflate
    ) { control, pair in
      try await self.testBidiStreamingCompression(
        client: .deflate,
        server: .deflate,
        control: control,
        pair: pair
      )
    }
  }

  func testBidiStreamingGzipCompression() async throws {
    try await self.forEachTransportPair(
      clientCompression: .gzip,
      clientEnabledCompression: .gzip,
      serverCompression: .gzip
    ) { control, pair in
      try await self.testBidiStreamingCompression(
        client: .gzip,
        server: .gzip,
        control: control,
        pair: pair
      )
    }
  }

  func testUnaryUnsupportedCompression() async throws {
    try await self.forEachTransportPair(
      clientEnabledCompression: .all,
      serverCompression: .gzip
    ) { control, pair in
      let message = ControlInput.with {
        $0.numberOfMessages = 1
        $0.messageParams = .with {
          $0.content = 42
          $0.size = 1024
        }
      }
      let request = ClientRequest.Single(message: message)

      var options = CallOptions.defaults
      options.compression = .deflate
      try await control.unary(request: request, options: options) { response in
        switch response.accepted {
        case .success:
          XCTFail("RPC should've been rejected")
        case .failure(let error):
          let acceptEncoding = Array(error.metadata["grpc-accept-encoding"])
          // "identity" may or may not be included, so only test for values which must be present.
          XCTAssertTrue(acceptEncoding.contains("gzip"))
          XCTAssertFalse(acceptEncoding.contains("deflate"))
        }
      }
    }
  }

  func testClientStreamingUnsupportedCompression() async throws {
    try await self.forEachTransportPair(
      clientEnabledCompression: .all,
      serverCompression: .gzip
    ) { control, pair in
      let request = ClientRequest.Stream(of: ControlInput.self) { writer in
        try await writer.write(.noOp)
      }

      var options = CallOptions.defaults
      options.compression = .deflate
      try await control.clientStream(request: request, options: options) { response in
        switch response.accepted {
        case .success:
          XCTFail("RPC should've been rejected")
        case .failure(let error):
          let acceptEncoding = Array(error.metadata["grpc-accept-encoding"])
          // "identity" may or may not be included, so only test for values which must be present.
          XCTAssertTrue(acceptEncoding.contains("gzip"))
          XCTAssertFalse(acceptEncoding.contains("deflate"))
        }
      }
    }
  }

  func testServerStreamingUnsupportedCompression() async throws {
    try await self.forEachTransportPair(
      clientEnabledCompression: .all,
      serverCompression: .gzip
    ) { control, pair in
      let message = ControlInput.with {
        $0.numberOfMessages = 1
        $0.messageParams = .with {
          $0.content = 42
          $0.size = 1024
        }
      }
      let request = ClientRequest.Single(message: message)

      var options = CallOptions.defaults
      options.compression = .deflate
      try await control.serverStream(request: request, options: options) { response in
        switch response.accepted {
        case .success:
          XCTFail("RPC should've been rejected")
        case .failure(let error):
          let acceptEncoding = Array(error.metadata["grpc-accept-encoding"])
          // "identity" may or may not be included, so only test for values which must be present.
          XCTAssertTrue(acceptEncoding.contains("gzip"))
          XCTAssertFalse(acceptEncoding.contains("deflate"))
        }
      }
    }
  }

  func testBidiStreamingUnsupportedCompression() async throws {
    try await self.forEachTransportPair(
      clientEnabledCompression: .all,
      serverCompression: .gzip
    ) { control, pair in
      let request = ClientRequest.Stream(of: ControlInput.self) { writer in
        try await writer.write(.noOp)
      }

      var options = CallOptions.defaults
      options.compression = .deflate
      try await control.bidiStream(request: request, options: options) { response in
        switch response.accepted {
        case .success:
          XCTFail("RPC should've been rejected")
        case .failure(let error):
          let acceptEncoding = Array(error.metadata["grpc-accept-encoding"])
          // "identity" may or may not be included, so only test for values which must be present.
          XCTAssertTrue(acceptEncoding.contains("gzip"))
          XCTAssertFalse(acceptEncoding.contains("deflate"))
        }
      }
    }
  }

  func testUnaryTimeoutPropagatedToServer() async throws {
    try await self.forEachTransportPair { control, pair in
      let message = ControlInput.with {
        $0.echoMetadataInHeaders = true
        $0.numberOfMessages = 1
      }

      let request = ClientRequest.Single(message: message)
      var options = CallOptions.defaults
      options.timeout = .seconds(10)
      try await control.unary(request: request, options: options) { response in
        let timeout = Array(response.metadata["echo-grpc-timeout"])
        XCTAssertEqual(timeout.count, 1)
      }
    }
  }

  func testClientStreamingTimeoutPropagatedToServer() async throws {
    try await self.forEachTransportPair { control, pair in
      let request = ClientRequest.Stream(of: ControlInput.self) { writer in
        let message = ControlInput.with {
          $0.echoMetadataInHeaders = true
          $0.numberOfMessages = 1
        }
        try await writer.write(message)
      }

      var options = CallOptions.defaults
      options.timeout = .seconds(10)
      try await control.clientStream(request: request, options: options) { response in
        let timeout = Array(response.metadata["echo-grpc-timeout"])
        XCTAssertEqual(timeout.count, 1)
      }
    }
  }

  func testServerStreamingTimeoutPropagatedToServer() async throws {
    try await self.forEachTransportPair { control, pair in
      let message = ControlInput.with {
        $0.echoMetadataInHeaders = true
        $0.numberOfMessages = 1
      }

      let request = ClientRequest.Single(message: message)
      var options = CallOptions.defaults
      options.timeout = .seconds(10)
      try await control.serverStream(request: request, options: options) { response in
        let timeout = Array(response.metadata["echo-grpc-timeout"])
        XCTAssertEqual(timeout.count, 1)
      }
    }
  }

  func testBidiStreamingTimeoutPropagatedToServer() async throws {
    try await self.forEachTransportPair { control, pair in
      let request = ClientRequest.Stream(of: ControlInput.self) { writer in
        try await writer.write(.echoMetadata)
      }

      var options = CallOptions.defaults
      options.timeout = .seconds(10)
      try await control.bidiStream(request: request, options: options) { response in
        let timeout = Array(response.metadata["echo-grpc-timeout"])
        XCTAssertEqual(timeout.count, 1)
      }
    }
  }

  private static let httpToStatusCodePairs: [(Int, RPCError.Code)] = [
    // See https://github.com/grpc/grpc/blob/master/doc/http-grpc-status-mapping.md
    (400, .internalError),
    (401, .unauthenticated),
    (403, .permissionDenied),
    (404, .unimplemented),
    (418, .unknown),
    (429, .unavailable),
    (502, .unavailable),
    (503, .unavailable),
    (504, .unavailable),
    (504, .unavailable),
  ]

  func testUnaryAgainstNonGRPCServer() async throws {
    try await self.forEachClientAndHTTPStatusCodeServer { control, kind in
      for (httpCode, expectedStatus) in Self.httpToStatusCodePairs {
        // Tell the server what to respond with.
        let metadata: Metadata = ["response-status": "\(httpCode)"]

        try await control.unary(
          request: ClientRequest.Single(message: .noOp, metadata: metadata)
        ) { response in
          switch response.accepted {
          case .success:
            XCTFail("RPC should have failed with '\(expectedStatus)'")
          case .failure(let error):
            XCTAssertEqual(error.code, expectedStatus)
          }
        }
      }
    }
  }

  func testClientStreamingAgainstNonGRPCServer() async throws {
    try await self.forEachClientAndHTTPStatusCodeServer { control, kind in
      for (httpCode, expectedStatus) in Self.httpToStatusCodePairs {
        // Tell the server what to respond with.
        let request = ClientRequest.Stream(
          of: ControlInput.self,
          metadata: ["response-status": "\(httpCode)"]
        ) { _ in
        }

        try await control.clientStream(request: request) { response in
          switch response.accepted {
          case .success:
            XCTFail("RPC should have failed with '\(expectedStatus)'")
          case .failure(let error):
            XCTAssertEqual(error.code, expectedStatus)
          }
        }
      }
    }
  }

  func testServerStreamingAgainstNonGRPCServer() async throws {
    try await self.forEachClientAndHTTPStatusCodeServer { control, kind in
      for (httpCode, expectedStatus) in Self.httpToStatusCodePairs {
        // Tell the server what to respond with.
        let metadata: Metadata = ["response-status": "\(httpCode)"]

        try await control.serverStream(
          request: ClientRequest.Single(message: .noOp, metadata: metadata)
        ) { response in
          switch response.accepted {
          case .success:
            XCTFail("RPC should have failed with '\(expectedStatus)'")
          case .failure(let error):
            XCTAssertEqual(error.code, expectedStatus)
          }
        }
      }
    }
  }

  func testBidiStreamingAgainstNonGRPCServer() async throws {
    try await self.forEachClientAndHTTPStatusCodeServer { control, kind in
      for (httpCode, expectedStatus) in Self.httpToStatusCodePairs {
        // Tell the server what to respond with.
        let request = ClientRequest.Stream(
          of: ControlInput.self,
          metadata: ["response-status": "\(httpCode)"]
        ) { _ in
        }

        try await control.bidiStream(request: request) { response in
          switch response.accepted {
          case .success:
            XCTFail("RPC should have failed with '\(expectedStatus)'")
          case .failure(let error):
            XCTAssertEqual(error.code, expectedStatus)
          }
        }
      }
    }
  }

  func testUnaryScheme() async throws {
    try await self.forEachTransportPair { control, pair in
      let input = ControlInput.with {
        $0.echoMetadataInHeaders = true
        $0.numberOfMessages = 1
      }
      let request = ClientRequest.Single(message: input)
      try await control.unary(request: request) { response in
        XCTAssertEqual(Array(response.metadata["echo-scheme"]), ["http"])
      }
    }
  }

  func testServerStreamingScheme() async throws {
    try await self.forEachTransportPair { control, pair in
      let input = ControlInput.with {
        $0.echoMetadataInHeaders = true
        $0.numberOfMessages = 1
      }
      let request = ClientRequest.Single(message: input)
      try await control.serverStream(request: request) { response in
        XCTAssertEqual(Array(response.metadata["echo-scheme"]), ["http"])
      }
    }
  }

  func testClientStreamingScheme() async throws {
    try await self.forEachTransportPair { control, pair in
      let request = ClientRequest.Stream(of: ControlInput.self) { writer in
        let input = ControlInput.with {
          $0.echoMetadataInHeaders = true
          $0.numberOfMessages = 1
        }
        try await writer.write(input)
      }
      try await control.clientStream(request: request) { response in
        XCTAssertEqual(Array(response.metadata["echo-scheme"]), ["http"])
      }
    }
  }

  func testBidiStreamingScheme() async throws {
    try await self.forEachTransportPair { control, pair in
      let request = ClientRequest.Stream(of: ControlInput.self) { writer in
        let input = ControlInput.with {
          $0.echoMetadataInHeaders = true
          $0.numberOfMessages = 1
        }
        try await writer.write(input)
      }
      try await control.bidiStream(request: request) { response in
        XCTAssertEqual(Array(response.metadata["echo-scheme"]), ["http"])
      }
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension [HTTP2TransportTests.Transport] {
  static let supported = [
    HTTP2TransportTests.Transport(server: .posix, client: .posix),
    HTTP2TransportTests.Transport(server: .niots, client: .posix),
  ]
}

extension ControlInput {
  fileprivate static let echoMetadata = Self.with {
    $0.echoMetadataInHeaders = true
  }

  fileprivate static let noOp = Self()

  fileprivate static func messages(
    _ numberOfMessages: Int,
    repeating: UInt8,
    count: Int
  ) -> Self {
    return Self.with {
      $0.numberOfMessages = Int32(numberOfMessages)
      $0.messageParams = .with {
        $0.content = UInt32(repeating)
        $0.size = Int32(count)
      }
    }
  }

  fileprivate static func status(
    code: Status.Code,
    message: String,
    echoMetadata: Bool
  ) -> Self {
    return Self.with {
      $0.echoMetadataInTrailers = echoMetadata
      $0.status = .with {
        $0.code = StatusCode(rawValue: code.rawValue)!
        $0.message = message
      }
    }
  }

  fileprivate static func trailersOnly(
    code: Status.Code,
    message: String,
    echoMetadata: Bool
  ) -> Self {
    return Self.with {
      $0.echoMetadataInTrailers = echoMetadata
      $0.isTrailersOnly = true
      $0.status = .with {
        $0.code = StatusCode(rawValue: code.rawValue)!
        $0.message = message
      }
    }
  }
}

extension CompressionAlgorithm {
  var name: String {
    switch self {
    case .deflate:
      return "deflate"
    case .gzip:
      return "gzip"
    case .none:
      return "identity"
    default:
      return ""
    }
  }
}
