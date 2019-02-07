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
import NIOHTTP2
import SwiftProtobuf

public protocol ClientCall {
  associatedtype RequestMessage: Message
  associatedtype ResponseMessage: Message

  /// HTTP/2 stream that requests and responses are sent and received on.
  var subchannel: EventLoopFuture<Channel> { get }

  /// Initial response metadata.
  var initialMetadata: EventLoopFuture<HTTPHeaders> { get }

  /// Response status.
  var status: EventLoopFuture<GRPCStatus> { get }

  /// Trailing response metadata.
  ///
  /// This is the same metadata as `GRPCStatus.trailingMetadata` returned by `status`.
  var trailingMetadata: EventLoopFuture<HTTPHeaders> { get }

  /// Cancels the current call.
  func cancel()
}

extension ClientCall {
  public var trailingMetadata: EventLoopFuture<HTTPHeaders> {
    return status.map { $0.trailingMetadata }
  }
}

/// A `ClientCall` with server-streaming; i.e. server-streaming and bidirectional-streaming.
public protocol StreamingRequestClientCall: ClientCall {
  /// Sends a request to the service. Callers must terminate the stream of messages
  /// with an `.end` event.
  ///
  /// - Parameter event: event to send.
  func send(_ event: StreamEvent<RequestMessage>)
}

extension StreamingRequestClientCall {
  public func send(_ event: StreamEvent<RequestMessage>) {
    switch event {
    case .message(let message):
      subchannel.whenSuccess { channel in
        channel.write(NIOAny(GRPCClientRequestPart<RequestMessage>.message(message)), promise: nil)
      }

    case .end:
      subchannel.whenSuccess { channel in
        channel.writeAndFlush(NIOAny(GRPCClientRequestPart<RequestMessage>.end), promise: nil)
      }
    }
  }
}

/// A `ClientCall` with a unary response; i.e. unary and client-streaming.
public protocol UnaryResponseClientCall: ClientCall {
  var response: EventLoopFuture<ResponseMessage> { get }
}
