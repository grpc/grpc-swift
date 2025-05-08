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

/// A request received at the server containing a single message.
@available(gRPCSwift 2.0, *)
public struct ServerRequest<Message: Sendable>: Sendable {
  /// Metadata received from the client at the start of the RPC.
  ///
  /// The metadata contains gRPC and transport specific entries in addition to user-specified
  /// metadata.
  public var metadata: Metadata

  /// The message received from the client.
  public var message: Message

  /// Create a new single server request.
  ///
  /// - Parameters:
  ///   - metadata: Metadata received from the client.
  ///   - message: The message received from the client.
  public init(metadata: Metadata, message: Message) {
    self.metadata = metadata
    self.message = message
  }
}

/// A request received at the server containing a stream of messages.
@available(gRPCSwift 2.0, *)
public struct StreamingServerRequest<Message: Sendable>: Sendable {
  /// Metadata received from the client at the start of the RPC.
  ///
  /// The metadata contains gRPC and transport specific entries in addition to user-specified
  /// metadata.
  public var metadata: Metadata

  /// A sequence of messages received from the client.
  ///
  /// The sequence may be iterated at most once.
  public var messages: RPCAsyncSequence<Message, any Error>

  /// Create a new streaming request.
  ///
  /// - Parameters:
  ///   - metadata: Metadata received from the client.
  ///   - messages: A sequence of messages received from the client.
  public init(metadata: Metadata, messages: RPCAsyncSequence<Message, any Error>) {
    self.metadata = metadata
    self.messages = messages
  }
}

// MARK: - Conversion

@available(gRPCSwift 2.0, *)
extension StreamingServerRequest {
  public init(single request: ServerRequest<Message>) {
    self.init(metadata: request.metadata, messages: .one(request.message))
  }
}

@available(gRPCSwift 2.0, *)
extension ServerRequest {
  public init(stream request: StreamingServerRequest<Message>) async throws {
    var iterator = request.messages.makeAsyncIterator()

    guard let message = try await iterator.next() else {
      throw RPCError(code: .internalError, message: "Empty stream.")
    }

    guard try await iterator.next() == nil else {
      throw RPCError(code: .internalError, message: "Too many messages.")
    }

    self = ServerRequest(metadata: request.metadata, message: message)
  }
}
