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
import NIOCore
import NIOSSL
import NIOTLS

/// Application protocol identifiers for ALPN.
internal enum GRPCApplicationProtocolIdentifier {
  static let gRPC = "grpc-exp"
  static let h2 = "h2"
  static let http1_1 = "http/1.1"

  static let client = [gRPC, h2]
  static let server = [gRPC, h2, http1_1]

  static func isHTTP2Like(_ value: String) -> Bool {
    switch value {
    case self.gRPC, self.h2:
      return true
    default:
      return false
    }
  }

  static func isHTTP1(_ value: String) -> Bool {
    return value == self.http1_1
  }
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
