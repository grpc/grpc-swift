import Foundation
import NIO
import NIOHTTP1
@testable import SwiftGRPCNIO
import XCTest

internal struct CaseExtractError: Error {
  let message: String
}

@discardableResult
func extractHeaders(_ response: RawGRPCServerResponsePart) throws -> HTTPHeaders {
  guard case .headers(let headers) = response else {
    throw CaseExtractError(message: "\(response) did not match .headers")
  }
  return headers
}

@discardableResult
func extractMessage(_ response: RawGRPCServerResponsePart) throws -> ByteBuffer {
  guard case .message(let message) = response else {
    throw CaseExtractError(message: "\(response) did not match .message")
  }
  return message
}

@discardableResult
func extractStatus(_ response: RawGRPCServerResponsePart) throws -> GRPCStatus {
  guard case .status(let status) = response else {
    throw CaseExtractError(message: "\(response) did not match .status")
  }
  return status
}

class CollectingChannelHandler<OutboundIn>: ChannelOutboundHandler {
  var responses: [OutboundIn] = []
  var responseExpectation: XCTestExpectation?

  init(responseExpectation: XCTestExpectation? = nil) {
    self.responseExpectation = responseExpectation
  }

  func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    responses.append(unwrapOutboundIn(data))
    responseExpectation?.fulfill()
  }
}

class GRPCChannelHandlerResponseCapturingTestCase: XCTestCase {
  static let defaultTimeout: TimeInterval = 0.2
  static let echoProvider: [String: CallHandlerProvider] = ["echo.Echo": EchoProvider_NIO()]

  func configureChannel(withHandlers handlers: [ChannelHandler]) -> EventLoopFuture<EmbeddedChannel> {
    let channel = EmbeddedChannel()
    return channel.pipeline.addHandlers(handlers, first: true)
      .map { _ in channel }
  }

  /// Waits for `count` responses to be collected and then returns them. The test fails if too many
  /// responses are collected or not enough are collected before the timeout.
  func waitForGRPCChannelHandlerResponses(
    count: Int,
    servicesByName: [String: CallHandlerProvider] = echoProvider,
    timeout: TimeInterval = defaultTimeout,
    callback: @escaping (EmbeddedChannel) throws -> Void
  ) -> [RawGRPCServerResponsePart] {
    let responseExpectation = expectation(description: "expecting \(count) responses")
    responseExpectation.expectedFulfillmentCount = count
    responseExpectation.assertForOverFulfill = true

    let collector = CollectingChannelHandler<RawGRPCServerResponsePart>(responseExpectation: responseExpectation)
    _ = configureChannel(withHandlers: [collector, GRPCChannelHandler(servicesByName: servicesByName)])
      .thenThrowing(callback)

    waitForExpectations(timeout: timeout)
    return collector.responses
  }
}
