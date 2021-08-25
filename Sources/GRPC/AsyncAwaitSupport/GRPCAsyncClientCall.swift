/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import NIOCore
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import SwiftProtobuf

#if compiler(>=5.5)

/// Base protocol for an async client call to a gRPC service.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public protocol GRPCAsyncClientCall {
  /// The type of the request message for the call.
  associatedtype Request
  /// The type of the response message for the call.
  associatedtype Response

  /// The options used to make the RPC.
  var options: CallOptions { get }

  /// Initial response metadata.
  var initialMetadata: HPACKHeaders { get async throws }

  /// Status of this call which may be populated by the server or client.
  ///
  /// The client may populate the status if, for example, it was not possible to connect to the service.
  var status: GRPCStatus { get async }

  /// Trailing response metadata.
  var trailingMetadata: HPACKHeaders { get async throws }

  /// Cancel the current call.
  ///
  /// Closes the HTTP/2 stream once it becomes available. Additional writes to the channel will be ignored.
  /// Any unfulfilled promises will be failed with a cancelled status (excepting `status` which will be
  /// succeeded, if not already succeeded).
  func cancel() async throws
}

/// A `ClientCall` with request streaming; i.e. client-streaming and bidirectional-streaming.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public protocol AsyncStreamingRequestClientCall: GRPCAsyncClientCall {
  /// Sends a message to the service.
  ///
  /// - Important: Callers must terminate the stream of messages by calling `sendEnd()` or `sendEnd(promise:)`.
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - compression: Whether compression should be used for this message. Ignored if compression
  ///     was not enabled for the RPC.
  /// - Returns: A future which will be fullfilled when the message has been sent.
  func sendMessage(_ message: Request, compression: Compression) async throws

  /// Sends a sequence of messages to the service.
  ///
  /// - Important: Callers must terminate the stream of messages by calling `sendEnd()` or `sendEnd(promise:)`.
  ///
  /// - Parameters:
  ///   - messages: The sequence of messages to send.
  ///   - compression: Whether compression should be used for this message. Ignored if compression
  ///     was not enabled for the RPC.
  func sendMessages<S: Sequence>(_ messages: S, compression: Compression) async throws
    where S.Element == Request

  /// Terminates a stream of messages sent to the service.
  ///
  /// - Important: This should only ever be called once.
  /// - Returns: A future which will be fulfilled when the end has been sent.
  func sendEnd() async throws
}

/// A `ClientCall` with a unary response; i.e. unary and client-streaming.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public protocol AsyncUnaryResponseClientCall: GRPCAsyncClientCall {
  /// The response message returned from the service if the call is successful. This may be failed
  /// if the call encounters an error.
  ///
  /// Callers should rely on the `status` of the call for the canonical outcome.
  var response: Response { get async throws }
}

#endif
