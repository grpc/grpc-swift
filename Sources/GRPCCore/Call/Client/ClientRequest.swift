/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

/// A request created by the client for a single message.
///
/// This is used for unary and server-streaming RPCs.
///
/// See ``StreamingClientRequest`` for streaming requests and ``ServerRequest`` for the
/// servers representation of a single-message request.
///
/// ## Creating requests
///
/// ```swift
/// let request = ClientRequest<String>(message: "Hello, gRPC!")
/// print(request.metadata)  // prints '[:]'
/// print(request.message)  // prints 'Hello, gRPC!'
/// ```
@available(gRPCSwift 2.0, *)
public struct ClientRequest<Message: Sendable>: Sendable {
  /// Caller-specified metadata to send to the server at the start of the RPC.
  ///
  /// Both gRPC Swift and its transport layer may insert additional metadata. Keys prefixed with
  /// "grpc-" are prohibited and may result in undefined behaviour. Transports may also insert
  /// their own metadata, you should avoid using key names which may clash with transport specific
  /// metadata. Note that transports may also impose limits in the amount of metadata which may
  /// be sent.
  public var metadata: Metadata

  /// The message to send to the server.
  public var message: Message

  /// Create a new single client request.
  ///
  /// - Parameters:
  ///   - message: The message to send to the server.
  ///   - metadata: Metadata to send to the server at the start of the request. Defaults to empty.
  public init(
    message: Message,
    metadata: Metadata = [:]
  ) {
    self.metadata = metadata
    self.message = message
  }
}

/// A request created by the client for a stream of messages.
///
/// This is used for client-streaming and bidirectional-streaming RPCs.
///
/// See ``ClientRequest`` for single-message requests and ``StreamingServerRequest`` for the
/// servers representation of a streaming-message request.
@available(gRPCSwift 2.0, *)
public struct StreamingClientRequest<Message: Sendable>: Sendable {
  /// Caller-specified metadata sent to the server at the start of the RPC.
  ///
  /// Both gRPC Swift and its transport layer may insert additional metadata. Keys prefixed with
  /// "grpc-" are prohibited and may result in undefined behaviour. Transports may also insert
  /// their own metadata, you should avoid using key names which may clash with transport specific
  /// metadata. Note that transports may also impose limits in the amount of metadata which may
  /// be sent.
  public var metadata: Metadata

  /// A closure which, when called, writes messages in the writer.
  ///
  /// The producer will only be consumed once by gRPC and therefore isn't required to be
  /// idempotent. If the producer throws an error then the RPC will be cancelled. Once the
  /// producer returns the request stream is closed.
  public var producer: @Sendable (RPCWriter<Message>) async throws -> Void

  /// Create a new streaming client request.
  ///
  /// - Parameters:
  ///   - messageType: The type of message contained in this request, defaults to `Message.self`.
  ///   - metadata: Metadata to send to the server at the start of the request. Defaults to empty.
  ///   - producer: A closure which writes messages to send to the server. The closure is called
  ///       at most once and may not be called.
  public init(
    of messageType: Message.Type = Message.self,
    metadata: Metadata = [:],
    producer: @escaping @Sendable (RPCWriter<Message>) async throws -> Void
  ) {
    self.metadata = metadata
    self.producer = producer
  }
}
