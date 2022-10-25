/*
 * Copyright 2022, gRPC Authors All rights reserved.
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
import EchoModel
import GRPC
import NIOCore
import NIOPosix
import XCTest
import Tracing
import Logging

// ==== ----------------------------------------------------------------------------------------------------------------

enum TestXTraceID: BaggageKey {
  typealias Value = String
  static var nameOverride: String? { "x-trace-id" }
}

extension Baggage {
  public internal(set) var testXTraceID: String? {
    get {
      self[TestXTraceID.self]
    }
    set {
      self[TestXTraceID.self] = newValue
    }
  }
}


// ==== ----------------------------------------------------------------------------------------------------------------

internal final class ServerLogExtractionTests: GRPCTestCase {
  private let traceIDHeader = TestXTraceID.nameOverride!
  private let loggerKey = "uuid"

  private var group: EventLoopGroup?
  private var server: Server?
  private var channel: GRPCChannel?

  override func tearDown() {
    try? self.channel?.close().wait()
    try? self.server?.close().wait()
    try? self.group?.syncShutdownGracefully()
    super.tearDown()
  }

  private func setUp(logMessage: String, asyncServer: Bool) throws {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    let provider: CallHandlerProvider
    if asyncServer {
      #if swift(>=5.6)
      if #available(macOS 12, *) {
        provider = AsyncLoggingEchoProvider(expectedMessage: logMessage)
      } else {
        fatalError()
      }
      #else
      fatalError()
      #endif // swift(>=5.6)
    } else {
      provider = LoggingEchoProvider(expectedMessage: logMessage)
    }

    var serverConfig = Server.Configuration.default(
      target: .hostAndPort("127.0.0.1", 0),
      eventLoopGroup: self.group!,
      serviceProviders: [provider]
    )

    serverConfig.logger = self.serverLogger
    // serverConfig.traceIDExtractor = .fixedHeaderName(self.traceIDHeader, loggerKey: self.loggerKey)
    serverConfig.tracer = _GRPCSimpleFixedTraceIDTracer(fixedHeaderName: TestXTraceID.nameOverride!)
    serverConfig.logger.metadataProvider = .init { baggage in
      print("provide metadata: \(baggage)")
      if let simpleID = baggage?.grpcSimpleFixedTraceID {
        print("provide metadata ->>>> \(simpleID)")
        return [self.loggerKey : .string(simpleID)] // NOTE: We explicitly log the value under a "loggerKey" as the test expects
      } else {
        return [:]
      }
    }

    self.server = try Server.start(configuration: serverConfig).wait()

    self.channel = try! GRPCChannelPool.with(
      target: .host("127.0.0.1", port: self.server!.channel.localAddress!.port!),
      transportSecurity: .plaintext,
      eventLoopGroup: self.group!
    )
  }

  private func setUpAndAssertExtractedID(
    function: String = #function,
    asyncServer: Bool,
    _ body: (Echo_EchoNIOClient) throws -> Void
  ) throws {
    // Setup the ELG, server and client. The server emits a log with the 'function' as a message on
    // each of the Echo RPCs.
    try self.setUp(logMessage: function, asyncServer: asyncServer)

    // Configure the echo client to propagate a trace ID.
    var echo = Echo_EchoNIOClient(channel: self.channel!)
    echo.defaultCallOptions.requestIDHeader = self.traceIDHeader
    let uuid = UUID().uuidString
    echo.defaultCallOptions.requestIDProvider = .userDefined(uuid)

    // Run the body, i.e. the RPC.
    XCTAssertNoThrow(try body(echo))

    // Check the captured logs for the expected message and metadata.
    let logs = self.capturedLogs()

    for l in logs {
      print("    Captured log: \(l.message) :: \(l.metadata)")
    }
    print("Check where: message == \(function)")
    if let log = logs.first(where: { $0.message == "\(function)" }) {
      XCTAssertEqual(log.metadata[self.loggerKey], "\(uuid)")
    } else {
      XCTFail("No log found containing the message '\(function)'")
    }
  }

  func testUnaryNIO() throws {
    try self.setUpAndAssertExtractedID(asyncServer: false) { echo in
      let rpc = echo.get(.with { $0.text = "foo" })
      XCTAssertNoThrow(try rpc.response.wait())
    }
  }

  func testUnaryAsync() throws {
    #if swift(>=5.6)
    if #available(macOS 12, *) {
      try self.setUpAndAssertExtractedID(asyncServer: true) { echo in
        let rpc = echo.get(.with { $0.text = "foo" })
        XCTAssertNoThrow(try rpc.response.wait())
      }
    }
    #endif
  }

  func testClientStreamingNIO() throws {
    try self.setUpAndAssertExtractedID(asyncServer: false) { echo in
      let rpc = echo.collect()
      rpc.sendMessage(.with { $0.text = "1" }, promise: nil)
      rpc.sendMessage(.with { $0.text = "2" }, promise: nil)
      rpc.sendMessage(.with { $0.text = "3" }, promise: nil)
      rpc.sendEnd(promise: nil)
      XCTAssertNoThrow(try rpc.response.wait())
    }
  }

  func testClientStreamingAsync() throws {
    #if swift(>=5.6)
    if #available(macOS 12, *) {
      try self.setUpAndAssertExtractedID(asyncServer: true) { echo in
        let rpc = echo.collect()
        rpc.sendMessage(.with { $0.text = "1" }, promise: nil)
        rpc.sendMessage(.with { $0.text = "2" }, promise: nil)
        rpc.sendMessage(.with { $0.text = "3" }, promise: nil)
        rpc.sendEnd(promise: nil)
        XCTAssertNoThrow(try rpc.response.wait())
      }
    }
    #endif
  }

  func testServerStreamingNIO() throws {
    try self.setUpAndAssertExtractedID(asyncServer: false) { echo in
      let rpc = echo.expand(.with { $0.text = "foo bar baz" }) { _ in }
      XCTAssertNoThrow(try rpc.status.wait())
    }
  }

  func testServerStreamingAsync() throws {
    #if swift(>=5.6)
    if #available(macOS 12, *) {
      try self.setUpAndAssertExtractedID(asyncServer: true) { echo in
        let rpc = echo.expand(.with { $0.text = "foo bar baz" }) { _ in }
        XCTAssertNoThrow(try rpc.status.wait())
      }
    }
    #endif
  }

  func testBidiStreamingNIO() throws {
    try self.setUpAndAssertExtractedID(asyncServer: false) { echo in
      let rpc = echo.update { _ in }
      rpc.sendMessage(.with { $0.text = "1" }, promise: nil)
      rpc.sendMessage(.with { $0.text = "2" }, promise: nil)
      rpc.sendMessage(.with { $0.text = "3" }, promise: nil)
      rpc.sendEnd(promise: nil)
      XCTAssertNoThrow(try rpc.status.wait())
    }
  }

  func testBidiStreamingAsync() throws {
    #if swift(>=5.6)
    if #available(macOS 12, *) {
      try self.setUpAndAssertExtractedID(asyncServer: true) { echo in
        let rpc = echo.update { _ in }
        rpc.sendMessage(.with { $0.text = "1" }, promise: nil)
        rpc.sendMessage(.with { $0.text = "2" }, promise: nil)
        rpc.sendMessage(.with { $0.text = "3" }, promise: nil)
        rpc.sendEnd(promise: nil)
        XCTAssertNoThrow(try rpc.status.wait())
      }
    }
    #endif
  }
}

final class LoggingEchoProvider: Echo_EchoProvider {
  let interceptors: Echo_EchoServerInterceptorFactoryProtocol? = nil

  private let expectedMessage: String

  init(expectedMessage: String) {
    self.expectedMessage = expectedMessage
  }

  func get(
    request: Echo_EchoRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Echo_EchoResponse> {
    context.logger.info("\(self.expectedMessage)")
    return context.eventLoop.makeSucceededFuture(.with { $0.text = request.text })
  }

  func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    context.logger.info("\(self.expectedMessage)")

    for component in request.text.components(separatedBy: " ") {
      context.sendResponse(.with { $0.text = component }, promise: nil)
    }

    return context.eventLoop.makeSucceededFuture(.ok)
  }

  func collect(
    context: UnaryResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    context.logger.info("\(self.expectedMessage)")

    return context.eventLoop.makeSucceededFuture({ event in
      var response = ""

      switch event {
      case let .message(request):
        if !response.isEmpty {
          response += " "
        }
        response += request.text

      case .end:
        context.responsePromise.succeed(.with { $0.text = response })
      }
    })
  }

  func update(
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    context.logger.info("\(self.expectedMessage)")

    return context.eventLoop.makeSucceededFuture({ event in
      switch event {
      case let .message(request):
        context.sendResponse(.with { $0.text = request.text }, promise: nil)
      case .end:
        context.statusPromise.succeed(.ok)
      }
    })
  }
}

#if swift(>=5.6)
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
final class AsyncLoggingEchoProvider: Echo_EchoAsyncProvider {
  private let expectedMessage: String

  init(expectedMessage: String) {
    self.expectedMessage = expectedMessage
  }

  func get(
    request: Echo_EchoRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Echo_EchoResponse {
    context.request.logger.info("\(self.expectedMessage)")
    return .with { $0.text = request.text }
  }

  func expand(
    request: Echo_EchoRequest,
    responseStream: GRPCAsyncResponseStreamWriter<Echo_EchoResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    context.request.logger.info("\(self.expectedMessage)")
    for part in request.text.components(separatedBy: " ") {
      try await responseStream.send(.with { $0.text = part })
    }
  }

  func collect(
    requestStream: GRPCAsyncRequestStream<Echo_EchoRequest>,
    context: GRPCAsyncServerCallContext
  ) async throws -> Echo_EchoResponse {
    context.request.logger.info("\(self.expectedMessage)")
    let requests = try await requestStream.map { $0.text }.collect()
    return .with { $0.text = requests.joined(separator: " ") }
  }

  func update(
    requestStream: GRPCAsyncRequestStream<Echo_EchoRequest>,
    responseStream: GRPCAsyncResponseStreamWriter<Echo_EchoResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    context.request.logger.info("\(self.expectedMessage)")
    for try await request in requestStream {
      try await responseStream.send(.with { $0.text = request.text })
    }
  }
}
#endif // swift(>=5.6)
