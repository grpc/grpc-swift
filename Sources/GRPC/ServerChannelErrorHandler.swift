/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIOCore

/// A handler that passes errors thrown into the server channel to the server error delegate.
///
/// A NIO server bootstrap produces two kinds of channels. The first and most common is the "child" channel:
/// each of these corresponds to one connection, and has the connection state stored on it. The other kind is
/// the "server" channel. Each bootstrap produces only one of these, and it is the channel that owns the listening
/// socket.
///
/// This channel handler is inserted into the server channel, and is responsible for passing any errors in that pipeline
/// to the server error delegate. If there is no error delegate, this handler is not inserted into the pipeline.
final class ServerChannelErrorHandler {
  private let errorDelegate: ServerErrorDelegate

  init(errorDelegate: ServerErrorDelegate) {
    self.errorDelegate = errorDelegate
  }
}

extension ServerChannelErrorHandler: ChannelInboundHandler {
  typealias InboundIn = Any
  typealias InboundOut = Any

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    // This handler does not treat errors as fatal to the listening socket, as it's possible they were transiently
    // occurring in a single connection setup attempt.
    self.errorDelegate.observeLibraryError(error)
    context.fireErrorCaught(error)
  }
}
