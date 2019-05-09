import Foundation
import NIO
import NIOHTTP1
@testable import SwiftGRPCNIO
import XCTest

class CollectingChannelHandler<OutboundIn>: ChannelOutboundHandler {
  var responses: [OutboundIn] = []

  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    promise?.succeed(())
    responses.append(unwrapOutboundIn(data))
  }
}

class CollectingServerErrorDelegate: ServerErrorDelegate {
  var errors: [Error] = []

  var asGRPCErrors: [GRPCError]? {
    return self.errors as? [GRPCError]
  }

  var asGRPCServerErrors: [GRPCServerError]? {
    return (self.asGRPCErrors?.map { $0.wrappedError }) as? [GRPCServerError]
  }

  var asGRPCCommonErrors: [GRPCCommonError]? {
    return (self.asGRPCErrors?.map { $0.wrappedError }) as? [GRPCCommonError]
  }

  func observeLibraryError(_ error: Error) {
    self.errors.append(error)
  }
}

class GRPCChannelHandlerResponseCapturingTestCase: XCTestCase {
  static let echoProvider: [String: CallHandlerProvider] = ["echo.Echo": EchoProviderNIO()]
  class var defaultServiceProvider: [String: CallHandlerProvider] {
    return echoProvider
  }

  func configureChannel(withHandlers handlers: [ChannelHandler]) -> EventLoopFuture<EmbeddedChannel> {
    let channel = EmbeddedChannel()
    return channel.pipeline.addHandlers(handlers, position: .first)
      .map { _ in channel }
  }

  var errorCollector: CollectingServerErrorDelegate = CollectingServerErrorDelegate()

  /// Waits for `count` responses to be collected and then returns them. The test fails if the number
  /// of collected responses does not match the expected.
  ///
  /// - Parameters:
  ///   - count: expected number of responses.
  ///   - servicesByName: service providers keyed by their service name.
  ///   - callback: a callback called after the channel has been setup, intended to "fill" the channel
  ///     with messages. The callback is called before this function returns.
  /// - Returns: The responses collected from the pipeline.
  func waitForGRPCChannelHandlerResponses(
    count: Int,
    servicesByName: [String: CallHandlerProvider] = defaultServiceProvider,
    callback: @escaping (EmbeddedChannel) throws -> Void
  ) throws -> [RawGRPCServerResponsePart] {
    let collector = CollectingChannelHandler<RawGRPCServerResponsePart>()
    try configureChannel(withHandlers: [collector, GRPCChannelHandler(servicesByName: servicesByName, errorDelegate: errorCollector)])
      .flatMapThrowing(callback)
      .wait()

    XCTAssertEqual(count, collector.responses.count)
    return collector.responses
  }
}
