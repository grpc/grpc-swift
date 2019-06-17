import Foundation
import NIO
import NIOSSL
import NIOTLS

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

  private var verificationPromise: EventLoopPromise<Void>!
  private let delegate: ClientErrorDelegate?

  /// A future which is fulfilled when the state of the TLS handshake is known. If the handshake
  /// was successful and the negotiated application protocol is valid then the future is succeeded.
  /// If an error occured or the application protocol is not valid then the future will have been
  /// failed.
  ///
  /// - Important: The promise associated with this future is created in `handlerAdded(context:)`,
  ///   and as such must _not_ be accessed before the handler has be added to a pipeline.
  public var verification: EventLoopFuture<Void>! {
    return verificationPromise.futureResult
  }

  public init(errorDelegate: ClientErrorDelegate?) {
    self.delegate = errorDelegate
  }

  public func handlerAdded(context: ChannelHandlerContext) {
    self.verificationPromise = context.eventLoop.makePromise()
    // Remove ourselves from the pipeline when the promise gets fulfilled.
    self.verificationPromise.futureResult.whenComplete { _ in
      context.pipeline.removeHandler(self, promise: nil)
    }
  }

  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    precondition(self.verificationPromise != nil, "handler has not been added to the pipeline")

    if let delegate = self.delegate {
      let grpcError = (error as? GRPCError) ?? GRPCError.unknown(error, origin: .client)
      delegate.didCatchError(grpcError.wrappedError, file: grpcError.file, line: grpcError.line)
    }

    verificationPromise.fail(error)
  }

  public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    precondition(self.verificationPromise != nil, "handler has not been added to the pipeline")

    guard let tlsEvent = event as? TLSUserEvent,
      case .handshakeCompleted(negotiatedProtocol: let negotiatedProtocol) = tlsEvent else {
        context.fireUserInboundEventTriggered(event)
        return
    }

    if let proto = negotiatedProtocol, GRPCApplicationProtocolIdentifier(rawValue: proto) != nil {
      self.verificationPromise.succeed(())
    } else {
      self.verificationPromise.fail(GRPCError.client(.applicationLevelProtocolNegotiationFailed))
    }
  }
}
