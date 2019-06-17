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

/// A channel handler which allows caught errors to be passed to a `ClientErrorDelegate`. This
/// handler is intended to be used in the client channel pipeline after the HTTP/2 stream
/// multiplexer to handle errors which occur on the underlying connection.
public class DelegatingErrorHandler: ChannelInboundHandler {
  public typealias InboundIn = Any

  private let delegate: ClientErrorDelegate?

  public init(delegate: ClientErrorDelegate?) {
    self.delegate = delegate
  }

  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    if let delegate = self.delegate {
      let grpcError = (error as? GRPCError) ?? .unknown(error, origin: .client)
      delegate.didCatchError(grpcError.wrappedError, file: grpcError.file, line: grpcError.line)
    }
    context.close(promise: nil)
  }
}
