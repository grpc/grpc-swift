/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation
import NIO
import NIOHTTP1
@testable import GRPC
import EchoModel
import EchoImplementation
import XCTest
import Logging

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

class GRPCChannelHandlerResponseCapturingTestCase: GRPCTestCase {
  static let echoProvider: [String: CallHandlerProvider] = ["echo.Echo": EchoProvider()]
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
    try configureChannel(withHandlers: [collector, GRPCChannelHandler(servicesByName: servicesByName, errorDelegate: errorCollector, logger: Logger(label: "io.grpc.testing"))])
      .flatMapThrowing(callback)
      .wait()

    XCTAssertEqual(count, collector.responses.count)
    return collector.responses
  }
}
