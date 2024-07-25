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

#if canImport(NIOSSL)
import GRPCCore
import XCTest
import NIOCore
import NIOEmbedded
import NIOTLS
import NIOHTTP2

@testable import GRPCHTTP2Core
@testable import GRPCHTTP2TransportNIOPosix

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class GRPCServerStreamHandlerTests: XCTestCase {
  func testALPNRequired_NegotiationSuccessfulH2() async throws {
    let channel = try self.setUpChannel(requireALPN: true)

    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    try channel.writeInbound(ByteBuffer(bytes: [
      UInt8(ascii: "P"),
      UInt8(ascii: "R"),
      UInt8(ascii: "I"),
    ]))
    XCTAssertNil(try channel.readInbound(as: ByteBuffer.self))
    channel.embeddedEventLoop.run()

    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    channel.pipeline.fireUserInboundEventTriggered(
      TLSUserEvent.handshakeCompleted(negotiatedProtocol: GRPCApplicationProtocolIdentifier.h2)
    )
    channel.embeddedEventLoop.run()

    await self.assertHandlersArePresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])
    await self.assertHandlersAreNotPresent(in: channel, [HTTP2PipelineConfigurator.self])
  }

  func testALPNRequired_NegotiationSuccessfulGRPC() async throws {
    let channel = try self.setUpChannel(requireALPN: true)

    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    try channel.writeInbound(ByteBuffer(bytes: [
      UInt8(ascii: "P"),
      UInt8(ascii: "R"),
      UInt8(ascii: "I"),
    ]))
    XCTAssertNil(try channel.readInbound(as: ByteBuffer.self))
    channel.embeddedEventLoop.run()

    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    channel.pipeline.fireUserInboundEventTriggered(TLSUserEvent.handshakeCompleted(negotiatedProtocol: GRPCApplicationProtocolIdentifier.gRPC))
    channel.embeddedEventLoop.run()

    await self.assertHandlersArePresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])
    await self.assertHandlersAreNotPresent(in: channel, [HTTP2PipelineConfigurator.self])
  }

  func testALPNRequired_NegotiationSuccessful_WithUnknownProtocol() async throws {
    let channel = try self.setUpChannel(requireALPN: true)

    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    try channel.writeInbound(ByteBuffer(bytes: [
      UInt8(ascii: "P"),
      UInt8(ascii: "R"),
      UInt8(ascii: "I"),
    ]))
    XCTAssertNil(try channel.readInbound(as: ByteBuffer.self))
    channel.embeddedEventLoop.run()

    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    channel.pipeline.fireUserInboundEventTriggered(TLSUserEvent.handshakeCompleted(negotiatedProtocol: "unknown protocol"))
    channel.embeddedEventLoop.run()

    // The channel should be closed now.
    XCTAssertThrowsError(ofType: ChannelError.self, try channel.throwIfErrorCaught()) { error in
      XCTAssertEqual(error, .badInterfaceAddressFamily)
    }
    try await channel.closeFuture.assertSuccess().get()
  }

  func testALPNRequired_NegotiationUnsuccessful() async throws {
    let channel = try self.setUpChannel(requireALPN: true)

    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    try channel.writeInbound(ByteBuffer(bytes: [
      UInt8(ascii: "P"),
      UInt8(ascii: "R"),
      UInt8(ascii: "I"),
    ]))
    XCTAssertNil(try channel.readInbound(as: ByteBuffer.self))
    channel.embeddedEventLoop.run()

    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    channel.pipeline.fireUserInboundEventTriggered(TLSUserEvent.handshakeCompleted(negotiatedProtocol: nil))
    channel.embeddedEventLoop.run()

    // The channel should be closed now.
    XCTAssertThrowsError(ofType: ChannelError.self, try channel.throwIfErrorCaught()) { error in
      XCTAssertEqual(error, .badInterfaceAddressFamily)
    }
    try await channel.closeFuture.assertSuccess().get()
  }

  func testALPNNotRequired_DoesNotHappen_AndH2PrefaceReceived() async throws {
    let channel = try self.setUpChannel(requireALPN: false)

    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    try channel.writeInbound(ByteBuffer(bytes: [
      UInt8(ascii: "P"),
      UInt8(ascii: "R"),
      UInt8(ascii: "I")
    ]))
    XCTAssertNil(try channel.readInbound(as: ByteBuffer.self))
    channel.embeddedEventLoop.run()

    // Assert we still have the configurator in the pipeline (and not the other handlers) as we haven't received enough
    // bytes yet to assert that we're on HTTP2.
    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    // Finish sending the rest of the H2 preface
    try channel.writeInbound(ByteBuffer(bytes: [
      UInt8(ascii: " "),
      UInt8(ascii: "*"),
      UInt8(ascii: " "),
      UInt8(ascii: "H"),
      UInt8(ascii: "T"),
      UInt8(ascii: "T"),
      UInt8(ascii: "P"),
      UInt8(ascii: "/"),
      UInt8(ascii: "2"),
      UInt8(ascii: "."),
      UInt8(ascii: "0"),
      UInt8(ascii: "\r"),
      UInt8(ascii: "\n"),
      UInt8(ascii: "\r"),
      UInt8(ascii: "\n"),
      UInt8(ascii: "S"),
      UInt8(ascii: "M"),
      UInt8(ascii: "\r"),
      UInt8(ascii: "\n"),
      UInt8(ascii: "\r"),
      UInt8(ascii: "\n")
    ]))
    XCTAssertNil(try channel.readInbound(as: ByteBuffer.self))
    channel.embeddedEventLoop.run()

    // Now the configurator must have done its job: assert the configurator handler
    // is gone and the other H2 handlers are present.
    await self.assertHandlersArePresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])
    await self.assertHandlersAreNotPresent(in: channel, [HTTP2PipelineConfigurator.self])
  }

  func testALPNNotRequired_DoesNotHappen_AndUnknownPrefaceReceived() async throws {
    let channel = try self.setUpChannel(requireALPN: false)

    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    try channel.writeInbound(ByteBuffer(bytes: [
      UInt8(ascii: "P"),
      UInt8(ascii: "R"),
      UInt8(ascii: "I")
    ]))
    XCTAssertNil(try channel.readInbound(as: ByteBuffer.self))
    channel.embeddedEventLoop.run()

    // Assert we still have the configurator in the pipeline (and not the other handlers) as we haven't received enough
    // bytes yet to assert that we're on HTTP2.
    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    // Send a set of bytes that's the same length as the H2 preface but is not it.
    // The channel should close now.
    XCTAssertThrowsError(
      ofType: ChannelError.self,
      try channel.writeInbound(ByteBuffer(bytes: [
        UInt8(ascii: " "),
        UInt8(ascii: "*"),
        UInt8(ascii: " "),
        UInt8(ascii: "J"),
        UInt8(ascii: "K"),
        UInt8(ascii: "K"),
        UInt8(ascii: "A"),
        UInt8(ascii: "/"),
        UInt8(ascii: "5"),
        UInt8(ascii: "."),
        UInt8(ascii: "0"),
        UInt8(ascii: "\r"),
        UInt8(ascii: "\n"),
        UInt8(ascii: "\r"),
        UInt8(ascii: "\n"),
        UInt8(ascii: "S"),
        UInt8(ascii: "M"),
        UInt8(ascii: "\r"),
        UInt8(ascii: "\n"),
        UInt8(ascii: "\r"),
        UInt8(ascii: "\n")
      ]))
    ) { error in
      XCTAssertEqual(error, .badInterfaceAddressFamily)
    }
    XCTAssertNil(try channel.readInbound(as: ByteBuffer.self))
    channel.embeddedEventLoop.run()
    try await channel.closeFuture.assertSuccess().get()
  }

  func testALPNNotRequired_IgnoresIfItDoesHappen() async throws {
    let channel = try self.setUpChannel(requireALPN: false)

    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    try channel.writeInbound(ByteBuffer(bytes: [
      UInt8(ascii: "P"),
      UInt8(ascii: "R"),
      UInt8(ascii: "I")
    ]))
    XCTAssertNil(try channel.readInbound(as: ByteBuffer.self))
    channel.embeddedEventLoop.run()

    // Assert we still have the configurator in the pipeline (and not the other handlers) as we haven't received enough
    // bytes yet to assert that we're on HTTP2.
    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    channel.pipeline.fireUserInboundEventTriggered(TLSUserEvent.handshakeCompleted(negotiatedProtocol: GRPCApplicationProtocolIdentifier.h2))
    channel.embeddedEventLoop.run()

    // Assert nothing has changed.
    await self.assertHandlersArePresent(in: channel, [HTTP2PipelineConfigurator.self])
    await self.assertHandlersAreNotPresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])

    // Receive the H2 preface...
    try channel.writeInbound(ByteBuffer(bytes: [
      UInt8(ascii: " "),
      UInt8(ascii: "*"),
      UInt8(ascii: " "),
      UInt8(ascii: "H"),
      UInt8(ascii: "T"),
      UInt8(ascii: "T"),
      UInt8(ascii: "P"),
      UInt8(ascii: "/"),
      UInt8(ascii: "2"),
      UInt8(ascii: "."),
      UInt8(ascii: "0"),
      UInt8(ascii: "\r"),
      UInt8(ascii: "\n"),
      UInt8(ascii: "\r"),
      UInt8(ascii: "\n"),
      UInt8(ascii: "S"),
      UInt8(ascii: "M"),
      UInt8(ascii: "\r"),
      UInt8(ascii: "\n"),
      UInt8(ascii: "\r"),
      UInt8(ascii: "\n")
    ]))
    XCTAssertNil(try channel.readInbound(as: ByteBuffer.self))
    channel.embeddedEventLoop.run()

    // Now the configurator must have done its job: assert the configurator handler
    // is gone and the other H2 handlers are present.
    await self.assertHandlersArePresent(in: channel, [
      GRPCServerFlushNotificationHandler.self,
      NIOHTTP2Handler.self,
      ServerConnectionManagementHandler.self
    ])
    await self.assertHandlersAreNotPresent(in: channel, [HTTP2PipelineConfigurator.self])
  }

  private func setUpChannel(requireALPN: Bool) throws -> EmbeddedChannel {
    let channel = EmbeddedChannel()
    let promise = channel.eventLoop.makePromise(of: HTTP2PipelineConfigurator.HTTP2ConfiguratorResult.self)
    let handler = HTTP2PipelineConfigurator(
      requireALPN: requireALPN,
      configurationCompletePromise: promise,
      compressionConfig: HTTP2ServerTransport.Config.Compression.defaults,
      connectionConfig: HTTP2ServerTransport.Config.Connection.defaults,
      http2Config: HTTP2ServerTransport.Config.HTTP2.defaults,
      rpcConfig: HTTP2ServerTransport.Config.RPC.defaults
    )
    try channel.pipeline.syncOperations.addHandler(handler)
    return channel
  }

  private func assertHandlersArePresent(in channel: EmbeddedChannel, _ handlers: [any ChannelHandler.Type]) async {
    for handler in handlers {
      await XCTAssertNoThrowAsync(try await channel.pipeline.containsHandler(type: handler).get())
    }
  }

  private func assertHandlersAreNotPresent(in channel: EmbeddedChannel, _ handlers: [any ChannelHandler.Type]) async {
    for handler in handlers {
      await XCTAssertThrowsError(try await channel.pipeline.containsHandler(type: handler).get()) { error in
        XCTAssertEqual(error as? ChannelPipelineError, .notFound)
      }
    }
  }
}

fileprivate func XCTAssertThrowsError<T>(
  _ expression: @autoclosure () async throws -> T,
  verify: (any Error) -> Void = { _ in },
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expression did not throw error", file: file, line: line)
  } catch {
    verify(error)
  }
}

fileprivate func XCTAssertNoThrowAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
  } catch {
    XCTFail("Expression throw error '\(error)'", file: file, line: line)
  }
}
#endif
