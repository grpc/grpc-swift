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
import Instrumentation
import Logging
import NIO
import NIOHTTP1
import NIOInstrumentation
import OpenTelemetryInstrumentationSupport
import SwiftProtobuf
import Tracing

/// Processes individual gRPC messages and stream-close events on an HTTP2 channel.
public protocol GRPCCallHandler: ChannelHandler {
  var _codec: ChannelHandler { get }
}

/// Provides `GRPCCallHandler` objects for the methods on a particular service name.
///
/// Implemented by the generated code.
public protocol CallHandlerProvider: AnyObject {
  /// The name of the service this object is providing methods for, including the package path.
  ///
  /// - Example: "io.grpc.Echo.EchoService"
  var serviceName: Substring { get }

  /// Determines, calls and returns the appropriate request handler (`GRPCCallHandler`), depending on the request's
  /// method. Returns nil for methods not handled by this service.
  func handleMethod(_ methodName: Substring, callHandlerContext: CallHandlerContext)
    -> GRPCCallHandler?
}

// This is public because it will be passed into generated code, all members are `internal` because
// the context will get passed from generated code back into gRPC library code and all members should
// be considered an implementation detail to the user.
public struct CallHandlerContext {
  internal var errorDelegate: ServerErrorDelegate?
  internal var logger: Logger
  internal var encoding: ServerMessageEncoding
}

/// Attempts to route a request to a user-provided call handler. Also validates that the request has
/// a suitable 'content-type' for gRPC.
///
/// Once the request headers are available, asks the `CallHandlerProvider` corresponding to the request's service name
/// for a `GRPCCallHandler` object. That object is then forwarded the individual gRPC messages.
///
/// After the pipeline has been configured with the `GRPCCallHandler`, this handler removes itself
/// from the pipeline.
public final class GRPCServerRequestRoutingHandler {
  private let logger: Logger
  private let servicesByName: [Substring: CallHandlerProvider]
  private let encoding: ServerMessageEncoding
  private weak var errorDelegate: ServerErrorDelegate?

  private enum State: Equatable {
    case notConfigured
    case configuring([InboundOut])
  }

  private var state: State = .notConfigured

  public init(
    servicesByName: [Substring: CallHandlerProvider],
    encoding: ServerMessageEncoding,
    errorDelegate: ServerErrorDelegate?,
    logger: Logger
  ) {
    self.servicesByName = servicesByName
    self.encoding = encoding
    self.errorDelegate = errorDelegate
    self.logger = logger
  }
}

extension GRPCServerRequestRoutingHandler: ChannelInboundHandler, RemovableChannelHandler {
  public typealias InboundIn = HTTPServerRequestPart
  public typealias InboundOut = HTTPServerRequestPart
  public typealias OutboundOut = HTTPServerResponsePart

  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    let status: GRPCStatus
    if let errorWithContext = error as? GRPCError.WithContext {
      self.errorDelegate?.observeLibraryError(errorWithContext.error)
      status = errorWithContext.error.makeGRPCStatus()
    } else {
      self.errorDelegate?.observeLibraryError(error)
      status = (error as? GRPCStatusTransformable)?.makeGRPCStatus() ?? .processingError
    }

    switch self.state {
    case .notConfigured:
      // We don't know what protocol we're speaking at this point. We'll just have to close the
      // channel.
      ()

    case let .configuring(messages):
      // first! is fine here: we only go from `.notConfigured` to `.configuring` when we receive
      // and validate the request head.
      let head = messages.compactMap { part -> HTTPRequestHead? in
        switch part {
        case let .head(head):
          return head
        default:
          return nil
        }
      }.first!

      let responseHead = self.makeResponseHead(requestHead: head, status: status)
      context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
      context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
      context.flush()
    }

    context.close(mode: .all, promise: nil)
  }

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    var span: Span

    let requestPart = self.unwrapInboundIn(data)
    switch requestPart {
    case let .head(requestHead):
      precondition(self.state == .notConfigured)

      InstrumentationSystem.instrument.extract(
        requestHead.headers,
        into: &context.baggage,
        using: HTTPHeadersExtractor()
      )

      span = InstrumentationSystem.tracer.startSpan(
        named: String(requestHead.uri.dropFirst()),
        baggage: context.baggage,
        ofKind: .server
      )

      if let userAgent = requestHead.headers.first(name: "User-Agent") {
        span.attributes[SpanAttributeName.HTTP.userAgent] = .string(userAgent)
      }
      if let host = requestHead.headers.first(name: "Host") {
        span.attributes[SpanAttributeName.HTTP.host] = .string(host)
      }
      if let port = context.channel.localAddress?.port {
        span.attributes[SpanAttributeName.Net.hostPort] = .int(port)
      }
      if let peerIP = context.channel.remoteAddress?.ipAddress {
        span.attributes[SpanAttributeName.Net.peerIP] = .string(peerIP)
      }
      span.attributes[SpanAttributeName.HTTP.method] = .string(requestHead.method.rawValue)

      let flavor = "\(requestHead.version.major).\(requestHead.version.minor)"
      span.attributes[SpanAttributeName.HTTP.flavor] = .string(flavor)
      span.attributes[SpanAttributeName.RPC.system] = "grpc"

      // Validate the 'content-type' is related to gRPC before proceeding.
      let maybeContentType = requestHead.headers.first(name: GRPCHeaderName.contentType)
      guard let contentType = maybeContentType,
        contentType.starts(with: ContentType.commonPrefix) else {
        self.logger.warning(
          "received request whose 'content-type' does not exist or start with '\(ContentType.commonPrefix)'",
          metadata: ["content-type": "\(String(describing: maybeContentType))"]
        )

        // From: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md
        //
        //   If 'content-type' does not begin with "application/grpc", gRPC servers SHOULD respond
        //   with HTTP status of 415 (Unsupported Media Type). This will prevent other HTTP/2
        //   clients from interpreting a gRPC error response, which uses status 200 (OK), as
        //   successful.
        let responseHead = HTTPResponseHead(
          version: requestHead.version,
          status: .unsupportedMediaType
        )

        // Fail the call. Note: we're not speaking gRPC here, so no status or message.
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        return
      }

      // Do we know how to handle this RPC?
      guard let requestInfo = GRPCRequestInfo(parsing: requestHead.uri),
        let callHandler = self.makeCallHandler(
          channel: context.channel,
          requestInfo: requestInfo
        ) else {
        self.logger.warning(
          "unable to make call handler; the RPC is not implemented on this server",
          metadata: ["uri": "\(requestHead.uri)"]
        )

        let status = GRPCError.RPCNotImplemented(rpc: requestHead.uri).makeGRPCStatus()
        let responseHead = self.makeResponseHead(requestHead: requestHead, status: status)

        // Write back a 'trailers-only' response.
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        return
      }

      span.attributes[SpanAttributeName.RPC.service] = .string(String(requestInfo.service))
      span.attributes[SpanAttributeName.RPC.method] = .string(String(requestInfo.method))

      self.logger.debug("received request head, configuring pipeline")

      // Buffer the request head; we'll replay it in the next handler when we're removed from the
      // pipeline.
      self.state = .configuring([requestPart])

      // Configure the rest of the pipeline to serve the RPC.
      let httpToGRPC = HTTP1ToGRPCServerCodec(
        encoding: self.encoding,
        logger: self.logger,
        span: span
      )
      let codec = callHandler._codec
      context.pipeline.addHandlers([httpToGRPC, codec, callHandler], position: .after(self))
        .whenSuccess {
          context.pipeline.removeHandler(self, promise: nil)
        }

    case .body, .end:
      switch self.state {
      case .notConfigured:
        // We can reach this point if we're receiving messages for a method that isn't implemented,
        // in which case we just drop the messages; our response should already be in-flight.
        ()

      case var .configuring(buffer):
        // We received a message while the pipeline was being configured; hold on to it while we
        // finish configuring the pipeline.
        buffer.append(requestPart)
        self.state = .configuring(buffer)
      }
    }
  }

  public func handlerRemoved(context: ChannelHandlerContext) {
    switch self.state {
    case .notConfigured:
      ()

    case let .configuring(messages):
      for message in messages {
        context.fireChannelRead(self.wrapInboundOut(message))
      }
    }
  }

  private func makeCallHandler(channel: Channel, requestInfo: GRPCRequestInfo) -> GRPCCallHandler? {
    self.logger.debug("making call handler", metadata: ["path": "\(requestInfo.uri)"])

    let context = CallHandlerContext(
      errorDelegate: self.errorDelegate,
      logger: self.logger,
      encoding: self.encoding
    )

    guard let providerForServiceName = servicesByName[requestInfo.service],
      let callHandler = providerForServiceName.handleMethod(
        requestInfo.method,
        callHandlerContext: context
      ) else {
      self.logger.notice("could not create handler", metadata: ["path": "\(requestInfo.uri)"])
      return nil
    }
    return callHandler
  }

  private func makeResponseHead(requestHead: HTTPRequestHead,
                                status: GRPCStatus) -> HTTPResponseHead {
    var headers: HTTPHeaders = [
      GRPCHeaderName.contentType: ContentType.protobuf.canonicalValue,
      GRPCHeaderName.statusCode: "\(status.code.rawValue)",
    ]

    if let message = status.message.flatMap(GRPCStatusMessageMarshaller.marshall) {
      headers.add(name: GRPCHeaderName.statusMessage, value: message)
    }

    return HTTPResponseHead(version: requestHead.version, status: .ok, headers: headers)
  }
}
