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
import Logging
import NIO
import NIOSSL
import NIOTLS

/// Application protocol identifiers for ALPN.
internal enum GRPCApplicationProtocolIdentifier: String, CaseIterable {
  // This is not in the IANA ALPN protocol ID registry, but may be used by servers to indicate that
  // they serve only gRPC traffic. It is part of the gRPC core implementation.
  case gRPC = "grpc-exp"
  case h2
}

internal class TLSVerificationHandler: ChannelInboundHandler, RemovableChannelHandler {
  typealias InboundIn = Any
  private let logger: Logger

  init(logger: Logger) {
    self.logger = logger
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    if let tlsEvent = event as? TLSUserEvent {
      switch tlsEvent {
      case let .handshakeCompleted(negotiatedProtocol: .some(`protocol`)):
        self.logger.debug("TLS handshake completed, negotiated protocol: \(`protocol`)")
      case .handshakeCompleted(negotiatedProtocol: nil):
        self.logger.debug("TLS handshake completed, no protocol negotiated")
      case .shutdownCompleted:
        ()
      }
    }

    context.fireUserInboundEventTriggered(event)
  }
}
