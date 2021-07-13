/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
@testable import GRPC
import NIO
import NIOHTTP2
import NIOTLS
import XCTest

class GRPCServerPipelineConfiguratorTests: GRPCTestCase {
  private var channel: EmbeddedChannel!

  private func assertConfigurator(isPresent: Bool) {
    assertThat(
      try self.channel.pipeline.handler(type: GRPCServerPipelineConfigurator.self).wait(),
      isPresent ? .doesNotThrow() : .throws()
    )
  }

  private func assertHTTP2Handler(isPresent: Bool) {
    assertThat(
      try self.channel.pipeline.handler(type: NIOHTTP2Handler.self).wait(),
      isPresent ? .doesNotThrow() : .throws()
    )
  }

  private func assertGRPCWebToHTTP2Handler(isPresent: Bool) {
    assertThat(
      try self.channel.pipeline.handler(type: GRPCWebToHTTP2ServerCodec.self).wait(),
      isPresent ? .doesNotThrow() : .throws()
    )
  }

  private func setUp(tls: Bool, requireALPN: Bool = true) {
    self.channel = EmbeddedChannel()

    var configuration = Server.Configuration.default(
      target: .unixDomainSocket("/ignored"),
      eventLoopGroup: self.channel.eventLoop,
      serviceProviders: []
    )

    configuration.logger = self.serverLogger

    if tls {
      configuration.tlsConfiguration = .makeServerConfigurationBackedByNIOSSL(
        certificateChain: [],
        privateKey: .file("not used"),
        requireALPN: requireALPN
      )
    }

    let handler = GRPCServerPipelineConfigurator(configuration: configuration)
    assertThat(try self.channel.pipeline.addHandler(handler).wait(), .doesNotThrow())
  }

  func testHTTP2SetupViaALPN() {
    self.setUp(tls: true, requireALPN: true)
    let event = TLSUserEvent.handshakeCompleted(negotiatedProtocol: "h2")
    self.channel.pipeline.fireUserInboundEventTriggered(event)
    self.assertConfigurator(isPresent: false)
    self.assertHTTP2Handler(isPresent: true)
  }

  func testGRPCExpSetupViaALPN() {
    self.setUp(tls: true, requireALPN: true)
    let event = TLSUserEvent.handshakeCompleted(negotiatedProtocol: "grpc-exp")
    self.channel.pipeline.fireUserInboundEventTriggered(event)
    self.assertConfigurator(isPresent: false)
    self.assertHTTP2Handler(isPresent: true)
  }

  func testHTTP1Dot1SetupViaALPN() {
    self.setUp(tls: true, requireALPN: true)
    let event = TLSUserEvent.handshakeCompleted(negotiatedProtocol: "http/1.1")
    self.channel.pipeline.fireUserInboundEventTriggered(event)
    self.assertConfigurator(isPresent: false)
    self.assertGRPCWebToHTTP2Handler(isPresent: true)
  }

  func testUnrecognisedALPNCloses() {
    self.setUp(tls: true, requireALPN: true)
    let event = TLSUserEvent.handshakeCompleted(negotiatedProtocol: "unsupported")
    self.channel.pipeline.fireUserInboundEventTriggered(event)
    self.channel.embeddedEventLoop.run()
    assertThat(try self.channel.closeFuture.wait(), .doesNotThrow())
  }

  func testNoNegotiatedProtocolCloses() {
    self.setUp(tls: true, requireALPN: true)
    let event = TLSUserEvent.handshakeCompleted(negotiatedProtocol: nil)
    self.channel.pipeline.fireUserInboundEventTriggered(event)
    self.channel.embeddedEventLoop.run()
    assertThat(try self.channel.closeFuture.wait(), .doesNotThrow())
  }

  func testNoNegotiatedProtocolFallbackToBytesWhenALPNNotRequired() throws {
    self.setUp(tls: true, requireALPN: false)

    // Require ALPN is disabled, so this is a no-op.
    let event = TLSUserEvent.handshakeCompleted(negotiatedProtocol: nil)
    self.channel.pipeline.fireUserInboundEventTriggered(event)

    // Configure via bytes.
    let bytes = ByteBuffer(staticString: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
    assertThat(try self.channel.writeInbound(bytes), .doesNotThrow())
    self.assertConfigurator(isPresent: false)
    self.assertHTTP2Handler(isPresent: true)
  }

  func testHTTP2SetupViaBytes() {
    self.setUp(tls: false)
    let bytes = ByteBuffer(staticString: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
    assertThat(try self.channel.writeInbound(bytes), .doesNotThrow())
    self.assertConfigurator(isPresent: false)
    self.assertHTTP2Handler(isPresent: true)
  }

  func testHTTP1Dot1SetupViaBytes() {
    self.setUp(tls: false)
    let bytes = ByteBuffer(staticString: "GET http://www.foo.bar HTTP/1.1\r\n")
    assertThat(try self.channel.writeInbound(bytes), .doesNotThrow())
    self.assertConfigurator(isPresent: false)
    self.assertGRPCWebToHTTP2Handler(isPresent: true)
  }

  func testReadsAreUnbufferedAfterConfiguration() throws {
    self.setUp(tls: false)

    var bytes = ByteBuffer(staticString: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
    // A SETTINGS frame MUST follow the connection preface. Append one so that the HTTP/2 handler
    // responds with its initial settings (and we validate that we forward frames once configuring).
    let emptySettingsFrameBytes: [UInt8] = [
      0x00, 0x00, 0x00, // 3-byte payload length (0 bytes)
      0x04, // 1-byte frame type (SETTINGS)
      0x00, // 1-byte flags (none)
      0x00, 0x00, 0x00, 0x00, // 4-byte stream identifier
    ]
    bytes.writeBytes(emptySettingsFrameBytes)

    // Do the setup.
    assertThat(try self.channel.writeInbound(bytes), .doesNotThrow())
    self.assertConfigurator(isPresent: false)
    self.assertHTTP2Handler(isPresent: true)

    // We expect the server to respond with a SETTINGS frame now.
    let ioData = try channel.readOutbound(as: IOData.self)
    switch ioData {
    case var .some(.byteBuffer(buffer)):
      if let frame = buffer.readBytes(length: 9) {
        // Just check it's a SETTINGS frame.
        assertThat(frame[3], .is(0x04))
      } else {
        XCTFail("Expected more bytes")
      }

    default:
      XCTFail("Expected ByteBuffer but got \(String(describing: ioData))")
    }
  }

  func testALPNIsPreferredOverBytes() throws {
    self.setUp(tls: true, requireALPN: true)

    // Write in an HTTP/1 request line. This should just be buffered.
    let bytes = ByteBuffer(staticString: "GET http://www.foo.bar HTTP/1.1\r\n")
    assertThat(try self.channel.writeInbound(bytes), .doesNotThrow())

    self.assertConfigurator(isPresent: true)
    self.assertHTTP2Handler(isPresent: false)
    self.assertGRPCWebToHTTP2Handler(isPresent: false)

    // Now configure HTTP/2 with ALPN. This should be used to configure the pipeline.
    let event = TLSUserEvent.handshakeCompleted(negotiatedProtocol: "h2")
    self.channel.pipeline.fireUserInboundEventTriggered(event)

    self.assertConfigurator(isPresent: false)
    self.assertGRPCWebToHTTP2Handler(isPresent: false)
    self.assertHTTP2Handler(isPresent: true)
  }

  func testALPNFallbackToAlreadyBufferedBytes() throws {
    self.setUp(tls: true, requireALPN: false)

    // Write in an HTTP/2 connection preface. This should just be buffered.
    let bytes = ByteBuffer(staticString: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
    assertThat(try self.channel.writeInbound(bytes), .doesNotThrow())

    self.assertConfigurator(isPresent: true)
    self.assertHTTP2Handler(isPresent: false)

    // Complete the handshake with no protocol negotiated, we should fallback to the buffered bytes.
    let event = TLSUserEvent.handshakeCompleted(negotiatedProtocol: nil)
    self.channel.pipeline.fireUserInboundEventTriggered(event)

    self.assertConfigurator(isPresent: false)
    self.assertHTTP2Handler(isPresent: true)
  }
}
