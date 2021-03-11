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
import EchoImplementation
@testable import GRPC
import NIO
import NIOHPACK
import NIOHTTP2
import XCTest

class HTTP2ToRawGRPCStateMachineTests: GRPCTestCase {
  typealias StateMachine = HTTP2ToRawGRPCStateMachine
  typealias State = StateMachine.State

  // An event loop gets passed to any service handler that's created, we don't actually use it here.
  private var eventLoop: EventLoop {
    return EmbeddedEventLoop()
  }

  /// An allocator, just here for convenience.
  private let allocator = ByteBufferAllocator()

  private func makeHeaders(
    path: String = "/echo.Echo/Get",
    contentType: String?,
    encoding: String? = nil,
    acceptEncoding: [String]? = nil
  ) -> HPACKHeaders {
    var headers = HPACKHeaders()
    headers.add(name: ":path", value: path)
    if let contentType = contentType {
      headers.add(name: GRPCHeaderName.contentType, value: contentType)
    }
    if let encoding = encoding {
      headers.add(name: GRPCHeaderName.encoding, value: encoding)
    }
    if let acceptEncoding = acceptEncoding {
      headers.add(name: GRPCHeaderName.acceptEncoding, value: acceptEncoding.joined(separator: ","))
    }
    return headers
  }

  private func makeHeaders(
    path: String = "/echo.Echo/Get",
    contentType: ContentType? = .protobuf,
    encoding: CompressionAlgorithm? = nil,
    acceptEncoding: [CompressionAlgorithm]? = nil
  ) -> HPACKHeaders {
    return self.makeHeaders(
      path: path,
      contentType: contentType?.canonicalValue,
      encoding: encoding?.name,
      acceptEncoding: acceptEncoding?.map { $0.name }
    )
  }

  /// A minimum set of viable request headers for the service providers we register by default.
  private var viableHeaders: HPACKHeaders {
    return self.makeHeaders(
      path: "/echo.Echo/Get",
      contentType: "application/grpc"
    )
  }

  /// Just the echo service.
  private var services: [Substring: CallHandlerProvider] {
    let provider = EchoProvider()
    return [provider.serviceName: provider]
  }

  private enum DesiredState {
    case requestOpenResponseIdle(pipelineConfigured: Bool)
    case requestOpenResponseOpen
    case requestClosedResponseIdle(pipelineConfigured: Bool)
    case requestClosedResponseOpen
  }

  /// Makes a state machine in the desired state.
  private func makeStateMachine(
    services: [Substring: CallHandlerProvider]? = nil,
    encoding: ServerMessageEncoding = .disabled,
    state: DesiredState = .requestOpenResponseIdle(pipelineConfigured: true)
  ) -> StateMachine {
    var machine = StateMachine(services: services ?? self.services, encoding: encoding)

    let receiveHeadersAction = machine.receive(
      headers: self.viableHeaders,
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )

    assertThat(receiveHeadersAction, .is(.configure()))

    switch state {
    case .requestOpenResponseIdle(pipelineConfigured: false):
      ()

    case .requestOpenResponseIdle(pipelineConfigured: true):
      let configuredAction = machine.pipelineConfigured()
      assertThat(configuredAction, .is(.forwardHeaders()))

    case .requestOpenResponseOpen:
      let configuredAction = machine.pipelineConfigured()
      assertThat(configuredAction, .is(.forwardHeaders()))

      let sendHeadersAction = machine.send(headers: [:])
      assertThat(sendHeadersAction, .is(.success()))

    case .requestClosedResponseIdle(pipelineConfigured: false):
      var emptyBuffer = ByteBuffer()
      let receiveEnd = machine.receive(buffer: &emptyBuffer, endStream: true)
      assertThat(receiveEnd, .is(false))

    case .requestClosedResponseIdle(pipelineConfigured: true):
      let configuredAction = machine.pipelineConfigured()
      assertThat(configuredAction, .is(.forwardHeaders()))

      var emptyBuffer = ByteBuffer()
      let receiveEnd = machine.receive(buffer: &emptyBuffer, endStream: true)
      assertThat(receiveEnd, .is(true))

    case .requestClosedResponseOpen:
      let configuredAction = machine.pipelineConfigured()
      assertThat(configuredAction, .is(.forwardHeaders()))

      var emptyBuffer = ByteBuffer()
      let receiveEndAction = machine.receive(buffer: &emptyBuffer, endStream: true)
      assertThat(receiveEndAction, .is(true))
      let readAction = machine.readNextRequest()
      assertThat(readAction, .is(.forwardEnd()))

      let sendHeadersAction = machine.send(headers: [:])
      assertThat(sendHeadersAction, .is(.success()))
    }

    return machine
  }

  /// Makes a gRPC framed message; i.e. a compression flag (UInt8), the message length (UIn32), the
  /// message bytes (UInt8 ⨉ message length).
  private func makeLengthPrefixedBytes(_ count: Int, setCompressFlag: Bool = false) -> ByteBuffer {
    var buffer = ByteBuffer()
    buffer.reserveCapacity(count + 5)
    buffer.writeInteger(UInt8(setCompressFlag ? 1 : 0))
    buffer.writeInteger(UInt32(count))
    buffer.writeRepeatingByte(0, count: count)
    return buffer
  }

  // MARK: Receive Headers Tests

  func testReceiveValidHeaders() {
    var machine = StateMachine(services: self.services, encoding: .disabled)
    let action = machine.receive(
      headers: self.viableHeaders,
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )
    assertThat(action, .is(.configure()))
  }

  func testReceiveInvalidContentType() {
    var machine = StateMachine(services: self.services, encoding: .disabled)
    let action = machine.receive(
      headers: self.makeHeaders(contentType: "application/json"),
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )
    assertThat(action, .is(.rejectRPC(.contains(":status", ["415"]))))
  }

  func testReceiveValidHeadersForUnknownService() {
    var machine = StateMachine(services: self.services, encoding: .disabled)
    let action = machine.receive(
      headers: self.makeHeaders(path: "/foo.Foo/Get"),
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )
    assertThat(action, .is(.rejectRPC(.trailersOnly(code: .unimplemented))))
  }

  func testReceiveValidHeadersForUnknownMethod() {
    var machine = StateMachine(services: self.services, encoding: .disabled)
    let action = machine.receive(
      headers: self.makeHeaders(path: "/echo.Echo/Foo"),
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )
    assertThat(action, .is(.rejectRPC(.trailersOnly(code: .unimplemented))))
  }

  func testReceiveValidHeadersForInvalidPath() {
    var machine = StateMachine(services: self.services, encoding: .disabled)
    let action = machine.receive(
      headers: self.makeHeaders(path: "nope"),
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )
    assertThat(action, .is(.rejectRPC(.trailersOnly(code: .unimplemented))))
  }

  func testReceiveHeadersWithUnsupportedEncodingWhenCompressionIsDisabled() {
    var machine = StateMachine(services: self.services, encoding: .disabled)
    let action = machine.receive(
      headers: self.makeHeaders(encoding: .gzip),
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )
    assertThat(action, .is(.rejectRPC(.trailersOnly(code: .unimplemented))))
  }

  func testReceiveHeadersWithMultipleEncodings() {
    var machine = StateMachine(services: self.services, encoding: .disabled)
    // We can't have multiple encodings.
    let action = machine.receive(
      headers: self.makeHeaders(contentType: "application/grpc", encoding: "gzip,identity"),
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )
    assertThat(action, .is(.rejectRPC(.trailersOnly(code: .invalidArgument))))
  }

  func testReceiveHeadersWithUnsupportedEncodingWhenCompressionIsEnabled() {
    var machine = StateMachine(services: self.services, encoding: .enabled(.deflate, .identity))

    let action = machine.receive(
      headers: self.makeHeaders(contentType: "application/grpc", encoding: "foozip"),
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )

    assertThat(action, .is(.rejectRPC(.trailersOnly(code: .unimplemented))))
    assertThat(
      action,
      .is(.rejectRPC(.contains("grpc-accept-encoding", ["deflate", "identity"])))
    )
  }

  func testReceiveHeadersWithSupportedButNotAdvertisedEncoding() {
    var machine = StateMachine(services: self.services, encoding: .enabled(.deflate, .identity))

    // We didn't advertise gzip, but we do support it.
    let action = machine.receive(
      headers: self.makeHeaders(encoding: .gzip),
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )

    // This is expected: however, we also expect 'grpc-accept-encoding' to be in the response
    // metadata. Send back headers to test this.
    assertThat(action, .is(.configure()))
    let sendAction = machine.send(headers: [:])
    assertThat(sendAction, .success(.contains(
      "grpc-accept-encoding",
      ["deflate", "identity", "gzip"]
    )))
  }

  func testReceiveHeadersWithIdentityCompressionWhenCompressionIsDisabled() {
    var machine = StateMachine(services: self.services, encoding: .disabled)

    // Identity is always supported, even if compression is disabled.
    let action = machine.receive(
      headers: self.makeHeaders(encoding: .identity),
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )

    assertThat(action, .is(.configure()))
  }

  func testReceiveHeadersNegotiatesResponseEncoding() {
    var machine = StateMachine(services: self.services, encoding: .enabled(.gzip, .deflate))

    let action = machine.receive(
      headers: self.makeHeaders(acceptEncoding: [.deflate]),
      eventLoop: self.eventLoop,
      errorDelegate: nil,
      remoteAddress: nil,
      logger: self.logger,
      allocator: ByteBufferAllocator(),
      responseWriter: NoOpResponseWriter(),
      closeFuture: self.eventLoop.makeSucceededVoidFuture()
    )

    // This is expected, but we need to check the value of 'grpc-encoding' in the response headers.
    assertThat(action, .is(.configure()))
    let sendAction = machine.send(headers: [:])
    assertThat(sendAction, .success(.contains("grpc-encoding", ["deflate"])))
  }

  // MARK: Receive Data Tests

  func testReceiveDataBeforePipelineIsConfigured() {
    var machine = self.makeStateMachine(state: .requestOpenResponseIdle(pipelineConfigured: false))
    let buffer = self.makeLengthPrefixedBytes(1024)

    // Receive a request. The pipeline isn't configured so no action.
    var buffer1 = buffer
    let action1 = machine.receive(buffer: &buffer1, endStream: false)
    assertThat(action1, .is(false))

    // Receive another request, still not configured so no action.
    var buffer2 = buffer
    let action2 = machine.receive(buffer: &buffer2, endStream: false)
    assertThat(action2, .is(false))

    // Configure the pipeline. We'll have headers to forward and messages to read.
    let action3 = machine.pipelineConfigured()
    assertThat(action3, .is(.forwardHeadersThenRead()))

    // Do the first read.
    let action4 = machine.readNextRequest()
    assertThat(action4, .is(.forwardMessageThenRead()))

    // Do the second and final read.
    let action5 = machine.readNextRequest()
    assertThat(action5, .is(.forwardMessage()))

    // Receive an empty buffer with end stream. Since we're configured we'll always try to read
    // after receiving.
    var emptyBuffer = ByteBuffer()
    let action6 = machine.receive(buffer: &emptyBuffer, endStream: true)
    assertThat(action6, .is(true))

    // There's nothing in the reader to consume, but since we saw end stream we'll have to close.
    let action7 = machine.readNextRequest()
    assertThat(action7, .is(.forwardEnd()))
  }

  func testReceiveDataWhenPipelineIsConfigured() {
    var machine = self.makeStateMachine(state: .requestOpenResponseIdle(pipelineConfigured: true))
    let buffer = self.makeLengthPrefixedBytes(1024)

    // Receive a request. The pipeline is configured, so we should try reading.
    var buffer1 = buffer
    let action1 = machine.receive(buffer: &buffer1, endStream: false)
    assertThat(action1, .is(true))

    // Read the message, consuming all bytes.
    let action2 = machine.readNextRequest()
    assertThat(action2, .is(.forwardMessage()))

    // Receive another request, we'll split buffer into two parts.
    var buffer3 = buffer
    var buffer2 = buffer3.readSlice(length: 20)!

    // Not enough bytes to form a message, so read won't result in anything.
    let action4 = machine.receive(buffer: &buffer2, endStream: false)
    assertThat(action4, .is(true))
    let action5 = machine.readNextRequest()
    assertThat(action5, .is(.none()))

    // Now the rest of the message.
    let action6 = machine.receive(buffer: &buffer3, endStream: false)
    assertThat(action6, .is(true))
    let action7 = machine.readNextRequest()
    assertThat(action7, .is(.forwardMessage()))

    // Receive an empty buffer with end stream. Since we're configured we'll always try to read
    // after receiving.
    var emptyBuffer = ByteBuffer()
    let action8 = machine.receive(buffer: &emptyBuffer, endStream: true)
    assertThat(action8, .is(true))

    // There's nothing in the reader to consume, but since we saw end stream we'll have to close.
    let action9 = machine.readNextRequest()
    assertThat(action9, .is(.forwardEnd()))
  }

  func testReceiveDataAndEndStreamBeforePipelineIsConfigured() {
    var machine = self.makeStateMachine(state: .requestOpenResponseIdle(pipelineConfigured: false))
    let buffer = self.makeLengthPrefixedBytes(1024)

    // No action: the pipeline isn't configured.
    var buffer1 = buffer
    let action1 = machine.receive(buffer: &buffer1, endStream: false)
    assertThat(action1, .is(false))

    // Still no action.
    var buffer2 = buffer
    let action2 = machine.receive(buffer: &buffer2, endStream: true)
    assertThat(action2, .is(false))

    // Configure the pipeline. We have headers to forward and messages to read.
    let action3 = machine.pipelineConfigured()
    assertThat(action3, .is(.forwardHeadersThenRead()))

    // Read the first message.
    let action4 = machine.readNextRequest()
    assertThat(action4, .is(.forwardMessageThenRead()))

    // Read the second and final message.
    let action5 = machine.readNextRequest()
    assertThat(action5, .is(.forwardMessageAndEnd()))
  }

  func testReceiveDataAfterPipelineIsConfigured() {
    var machine = self.makeStateMachine(state: .requestOpenResponseIdle(pipelineConfigured: true))
    let buffer = self.makeLengthPrefixedBytes(1024)

    // Pipeline is configured, we should be able to read then forward the message.
    var buffer1 = buffer
    let action1 = machine.receive(buffer: &buffer1, endStream: false)
    assertThat(action1, .is(true))
    let action2 = machine.readNextRequest()
    assertThat(action2, .is(.forwardMessage()))

    // Receive another message with end stream set.
    // Still no action.
    var buffer2 = buffer
    let action3 = machine.receive(buffer: &buffer2, endStream: true)
    assertThat(action3, .is(true))
    let action4 = machine.readNextRequest()
    assertThat(action4, .is(.forwardMessageAndEnd()))
  }

  func testReceiveDataWhenResponseStreamIsOpen() {
    var machine = self.makeStateMachine(state: .requestOpenResponseOpen)
    let buffer = self.makeLengthPrefixedBytes(1024)

    // Receive a message. We should read and forward it.
    var buffer1 = buffer
    let action1 = machine.receive(buffer: &buffer1, endStream: false)
    assertThat(action1, .is(true))
    let action2 = machine.readNextRequest()
    assertThat(action2, .is(.forwardMessage()))

    // Receive a message and end stream. We should read it then forward message and end.
    var buffer2 = buffer
    let action3 = machine.receive(buffer: &buffer2, endStream: true)
    assertThat(action3, .is(true))
    let action4 = machine.readNextRequest()
    assertThat(action4, .is(.forwardMessageAndEnd()))
  }

  func testReceiveCompressedMessageWhenCompressionIsDisabled() {
    var machine = self.makeStateMachine(state: .requestOpenResponseOpen)
    var buffer = self.makeLengthPrefixedBytes(1024, setCompressFlag: true)

    let action1 = machine.receive(buffer: &buffer, endStream: false)
    assertThat(action1, .is(true))
    let action2 = machine.readNextRequest()
    assertThat(action2, .is(.errorCaught()))
  }

  func testReceiveDataWhenClosed() {
    var machine = self.makeStateMachine(state: .requestOpenResponseOpen)
    // Close while the request stream is still open.
    let action1 = machine.send(
      status: GRPCStatus(code: .ok, message: "ok"),
      trailers: [:]
    )
    assertThat(action1, .is(.success(.trailers(code: .ok, message: "ok"))))

    // Now receive end of request stream: no action, we're closed.
    var emptyBuffer = ByteBuffer()
    let action2 = machine.receive(buffer: &emptyBuffer, endStream: true)
    assertThat(action2, .is(false))
  }

  // MARK: Send Metadata Tests

  func testSendMetadataRequestStreamOpen() {
    var machine = self.makeStateMachine(state: .requestOpenResponseIdle(pipelineConfigured: true))

    // We tested most of the weird (request encoding, negotiating response encoding etc.) above.
    // We'll just validate more 'normal' things here.
    let action1 = machine.send(headers: [:])
    assertThat(action1, .is(.success(.contains(":status", ["200"]))))

    let action2 = machine.send(headers: [:])
    assertThat(action2, .is(.failure()))
  }

  func testSendMetadataRequestStreamClosed() {
    var machine = self.makeStateMachine(state: .requestOpenResponseIdle(pipelineConfigured: true))

    var buffer = ByteBuffer()
    let action1 = machine.receive(buffer: &buffer, endStream: true)
    assertThat(action1, .is(true))
    let action2 = machine.readNextRequest()
    assertThat(action2, .is(.forwardEnd()))

    // Write some headers back.
    let action3 = machine.send(headers: [:])
    assertThat(action3, .is(.success(.contains(":status", ["200"]))))
  }

  func testSendMetadataWhenOpen() {
    var machine = self.makeStateMachine(state: .requestOpenResponseOpen)

    // Response stream is already open.
    let action = machine.send(headers: [:])
    assertThat(action, .is(.failure()))
  }

  func testSendMetadataNormalizesUserProvidedMetadata() {
    var machine = self.makeStateMachine(state: .requestOpenResponseIdle(pipelineConfigured: true))
    let action = machine.send(headers: ["FOO": "bar"])
    assertThat(action, .success(.contains(caseSensitive: "foo")))
  }

  // MARK: Send Data Tests

  func testSendData() {
    for startingState in [DesiredState.requestOpenResponseOpen, .requestClosedResponseOpen] {
      let machine = self.makeStateMachine(state: startingState)
      let buffer = ByteBuffer(repeating: 0, count: 1024)

      // We should be able to do this multiple times.
      for _ in 0 ..< 5 {
        let action = machine.send(
          buffer: buffer,
          allocator: self.allocator,
          compress: false
        )
        assertThat(action, .is(.success()))
      }

      // Set the compress flag, we're not setup to compress so the flag will just be ignored, we'll
      // write as normal.
      let action = machine.send(
        buffer: buffer,
        allocator: self.allocator,
        compress: true
      )
      assertThat(action, .is(.success()))
    }
  }

  func testSendDataAfterClose() {
    var machine = self.makeStateMachine(state: .requestClosedResponseOpen)
    let action1 = machine.send(status: .ok, trailers: [:])
    assertThat(action1, .is(.success(.contains("grpc-status", ["0"]))))

    // We're already closed, this should fail.
    let buffer = ByteBuffer(repeating: 0, count: 1024)
    let action2 = machine.send(
      buffer: buffer,
      allocator: self.allocator,
      compress: false
    )
    assertThat(action2, .is(.failure()))
  }

  func testSendDataBeforeMetadata() {
    let machine = self.makeStateMachine(state: .requestClosedResponseIdle(pipelineConfigured: true))

    // Response stream is still idle, so this should fail.
    let buffer = ByteBuffer(repeating: 0, count: 1024)
    let action2 = machine.send(
      buffer: buffer,
      allocator: self.allocator,
      compress: false
    )
    assertThat(action2, .is(.failure()))
  }

  // MARK: Send End

  func testSendEndWhenResponseStreamIsIdle() {
    for state in [
      DesiredState.requestOpenResponseIdle(pipelineConfigured: true),
      DesiredState.requestClosedResponseIdle(pipelineConfigured: true),
    ] {
      var machine = self.makeStateMachine(state: state)
      let action1 = machine.send(status: .ok, trailers: [:])
      // This'll be a trailers-only response.
      assertThat(action1, .is(.success(.trailersOnly(code: .ok))))

      // Already closed.
      let action2 = machine.send(status: .ok, trailers: [:])
      assertThat(action2, .is(.failure()))
    }
  }

  func testSendEndWhenResponseStreamIsOpen() {
    for state in [
      DesiredState.requestOpenResponseOpen,
      DesiredState.requestClosedResponseOpen,
    ] {
      var machine = self.makeStateMachine(state: state)
      let action = machine.send(
        status: GRPCStatus(code: .ok, message: "ok"),
        trailers: [:]
      )
      assertThat(action, .is(.success(.trailers(code: .ok, message: "ok"))))

      // Already closed.
      let action2 = machine.send(status: .ok, trailers: [:])
      assertThat(action2, .is(.failure()))
    }
  }
}

extension ServerMessageEncoding {
  fileprivate static func enabled(_ algorithms: CompressionAlgorithm...) -> ServerMessageEncoding {
    return .enabled(.init(enabledAlgorithms: algorithms, decompressionLimit: .absolute(.max)))
  }
}

class NoOpResponseWriter: GRPCServerResponseWriter {
  func sendMetadata(_ metadata: HPACKHeaders, flush: Bool, promise: EventLoopPromise<Void>?) {
    promise?.succeed(())
  }

  func sendMessage(
    _ bytes: ByteBuffer,
    metadata: MessageMetadata,
    promise: EventLoopPromise<Void>?
  ) {
    promise?.succeed(())
  }

  func sendEnd(status: GRPCStatus, trailers: HPACKHeaders, promise: EventLoopPromise<Void>?) {
    promise?.succeed(())
  }
}
