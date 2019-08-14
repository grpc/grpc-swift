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
import SwiftProtobuf
import NIO
import NIOHTTP1
import Logging

/// Processes individual gRPC messages and stream-close events on a HTTP2 channel.
public protocol GRPCCallHandler: ChannelHandler {
  func makeGRPCServerCodec() -> ChannelHandler
}

/// Provides `GRPCCallHandler` objects for the methods on a particular service name.
///
/// Implemented by the generated code.
public protocol CallHandlerProvider: class {
  /// The name of the service this object is providing methods for, including the package path.
  ///
  /// - Example: "io.grpc.Echo.EchoService"
  var serviceName: String { get }

  /// Determines, calls and returns the appropriate request handler (`GRPCCallHandler`), depending on the request's
  /// method. Returns nil for methods not handled by this service.
  func handleMethod(_ methodName: String, callHandlerContext: CallHandlerContext) -> GRPCCallHandler?
}

// This is public because it will be passed into generated code, all memebers are `internal` because
// the context will get passed from generated code back into gRPC library code and all members should
// be considered an implementation detail to the user.
public struct CallHandlerContext {
  internal var request: HTTPRequestHead
  internal var channel: Channel
  internal var errorDelegate: ServerErrorDelegate?
  internal var logger: Logger
}

/// Listens on a newly-opened HTTP2 subchannel and yields to the sub-handler matching a call, if available.
///
/// Once the request headers are available, asks the `CallHandlerProvider` corresponding to the request's service name
/// for an `GRPCCallHandler` object. That object is then forwarded the individual gRPC messages.
public final class GRPCChannelHandler {
  private let logger: Logger
  private let servicesByName: [String: CallHandlerProvider]
  private weak var errorDelegate: ServerErrorDelegate?

  public init(servicesByName: [String: CallHandlerProvider], errorDelegate: ServerErrorDelegate?, logger: Logger) {
    self.servicesByName = servicesByName
    self.errorDelegate = errorDelegate
    self.logger = logger.addingMetadata(key: MetadataKey.channelHandler, value: "GRPCChannelHandler")
  }
}

extension GRPCChannelHandler: ChannelInboundHandler, RemovableChannelHandler {
  public typealias InboundIn = RawGRPCServerRequestPart
  public typealias OutboundOut = RawGRPCServerResponsePart

  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    self.errorDelegate?.observeLibraryError(error)

    let status = self.errorDelegate?.transformLibraryError(error)
      ?? (error as? GRPCStatusTransformable)?.asGRPCStatus()
      ?? .processingError
    context.writeAndFlush(wrapOutboundOut(.status(status)), promise: nil)
  }

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let requestPart = self.unwrapInboundIn(data)
    switch requestPart {
    case .head(let requestHead):
      guard let callHandler = self.makeCallHandler(channel: context.channel, requestHead: requestHead) else {
        self.errorCaught(context: context, error: GRPCError.server(.unimplementedMethod(requestHead.uri)))
        return
      }

      logger.info("received request head, configuring pipeline")

      let codec = callHandler.makeGRPCServerCodec()
      let handlerRemoved: EventLoopPromise<Void> = context.eventLoop.makePromise()
      handlerRemoved.futureResult.whenSuccess {
        self.logger.info("removed GRPCChannelHandler from pipeline")
        context.pipeline.addHandler(callHandler, position: .after(codec)).whenComplete { _ in
          // Send the .headers event back to begin the headers flushing for the response.
          // At this point, which headers should be returned is not known, as the content type is
          // processed in HTTP1ToRawGRPCServerCodec. At the same time the HTTP1ToRawGRPCServerCodec
          // handler doesn't have the data to determine whether headers should be returned, as it is
          // this handler that checks whether the stub for the requested Service/Method is implemented.
          // This likely signals that the architecture for these handlers could be improved.
          context.writeAndFlush(self.wrapOutboundOut(.headers(HTTPHeaders())), promise: nil)
        }
      }

      logger.info("adding handler \(type(of: codec)) to pipeline")
      context.pipeline.addHandler(codec, position: .after(self))
        .whenSuccess { context.pipeline.removeHandler(context: context, promise: handlerRemoved) }

    case .message, .end:
      // We can reach this point if we're receiving messages for a method that isn't implemented.
      // A status resposne will have been fired which should also close the stream; there's not a
      // lot we can do at this point.
      break
    }
  }

  private func makeCallHandler(channel: Channel, requestHead: HTTPRequestHead) -> GRPCCallHandler? {
    // URI format: "/package.Servicename/MethodName", resulting in the following components separated by a slash:
    // - uriComponents[0]: empty
    // - uriComponents[1]: service name (including the package name);
    //     `CallHandlerProvider`s should provide the service name including the package name.
    // - uriComponents[2]: method name.
    self.logger.info("making call handler", metadata: ["path": "\(requestHead.uri)"])
    let uriComponents = requestHead.uri.components(separatedBy: "/")

    var logger = self.logger
    // Unset the channel handler: it shouldn't be used for downstream handlers.
    logger[metadataKey: MetadataKey.channelHandler] = nil

    let context = CallHandlerContext(
      request: requestHead,
      channel: channel,
      errorDelegate: self.errorDelegate,
      logger: logger
    )

    guard uriComponents.count >= 3 && uriComponents[0].isEmpty,
      let providerForServiceName = servicesByName[uriComponents[1]],
      let callHandler = providerForServiceName.handleMethod(uriComponents[2], callHandlerContext: context) else {
        self.logger.notice("could not create handler", metadata: ["path": "\(requestHead.uri)"])
        return nil
    }
    return callHandler
  }
}
