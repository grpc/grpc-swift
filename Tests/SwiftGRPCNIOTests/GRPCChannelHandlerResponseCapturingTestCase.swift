import Foundation
import NIO
import NIOHTTP1
@testable import SwiftGRPCNIO
import XCTest

class CollectingChannelHandler<OutboundIn>: ChannelOutboundHandler {
  var responses: [OutboundIn] = []

  func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    responses.append(unwrapOutboundIn(data))
  }
}

class CollectingServerErrorDelegate: ServerErrorDelegate {
  var errors: [Error] = []

  func observe(_ error: Error) {
    self.errors.append(error)
  }
}

class GRPCChannelHandlerResponseCapturingTestCase: XCTestCase {
  static let echoProvider: [String: CallHandlerProvider] = ["echo.Echo": EchoProvider_NIO()]
  class var defaultServiceProvider: [String: CallHandlerProvider] {
    return echoProvider
  }

  func configureChannel(withHandlers handlers: [ChannelHandler]) -> EventLoopFuture<EmbeddedChannel> {
    let channel = EmbeddedChannel()
    return channel.pipeline.addHandlers(handlers, first: true)
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
      .thenThrowing(callback)
      .wait()

    XCTAssertEqual(count, collector.responses.count)
    return collector.responses
  }
}
