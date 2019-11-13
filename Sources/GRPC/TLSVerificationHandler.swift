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
import NIOSSL
import NIOTLS
import Logging

/// Application protocol identifiers for ALPN.
public enum GRPCApplicationProtocolIdentifier: String, CaseIterable {
  // This is not in the IANA ALPN protocol ID registry, but may be used by servers to indicate that
  // they serve only gRPC traffic. It is part of the gRPC core implementation.
  case gRPC = "grpc-ext"
  case h2 = "h2"
}

/// A helper `ChannelInboundHandler` to verify that a TLS handshake was completed successfully
/// and that the negotiated application protocol is valid.
///
/// The handler holds a promise which is succeeded on successful verification of the negotiated
/// application protocol and failed if any error is received by this handler or an invalid
/// application protocol was negotiated.
///
/// Users of this handler should rely on the `verification` future held by this instance.
///
/// On fulfillment of the promise this handler is removed from the channel pipeline.
public class TLSVerificationHandler: ChannelInboundHandler, RemovableChannelHandler {
  public typealias InboundIn = Any

  private let logger = Logger(subsystem: .clientChannel)
  private var verificationPromise: EventLoopPromise<Void>!

  /// A future which is fulfilled when the state of the TLS handshake is known. If the handshake
  /// was successful and the negotiated application protocol is valid then the future is succeeded.
  /// If an error occurred or the application protocol is not valid then the future will have been
  /// failed.
  ///
  /// - Important: The promise associated with this future is created in `handlerAdded(context:)`,
  ///   and as such must _not_ be accessed before the handler has be added to a pipeline.
  public var verification: EventLoopFuture<Void>! {
    return verificationPromise.futureResult
  }

  public init() { }

  public func handlerAdded(context: ChannelHandlerContext) {
    self.verificationPromise = context.eventLoop.makePromise()
    // Remove ourselves from the pipeline when the promise gets fulfilled.
    self.verificationPromise.futureResult.recover { error in
      // If we have an error we should let the rest of the pipeline know.
      context.fireErrorCaught(error)
    }.whenComplete { _ in
      context.pipeline.removeHandler(self, promise: nil)
    }
  }

  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    precondition(self.verificationPromise != nil, "handler has not been added to the pipeline")
    self.logger.error(
      "error caught before TLS was verified",
      metadata: [MetadataKey.error: "\(error)"]
    )
    verificationPromise.fail(error)
  }

  public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    precondition(self.verificationPromise != nil, "handler has not been added to the pipeline")

    guard let tlsEvent = event as? TLSUserEvent,
      case .handshakeCompleted(negotiatedProtocol: let negotiatedProtocol) = tlsEvent else {
        context.fireUserInboundEventTriggered(event)
        return
    }

    self.logger.info("TLS handshake completed, negotiated protocol: \(String(describing: negotiatedProtocol))")
    if let proto = negotiatedProtocol, GRPCApplicationProtocolIdentifier(rawValue: proto) != nil {
      self.logger.debug("negotiated application protocol is valid")
      self.verificationPromise.succeed(())
    } else {
      self.logger.error("negotiated application protocol is invalid: \(String(describing: negotiatedProtocol))")
      let error = GRPCError.client(.applicationLevelProtocolNegotiationFailed)
      self.verificationPromise.fail(error)
    }
  }
}
