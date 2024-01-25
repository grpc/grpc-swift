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

/// A namespace for request message types used by servers.
public enum ServerRequest {}

extension ServerRequest {
  /// A request received at the server containing a single message.
  public struct Single<Message: Sendable>: Sendable {
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
    ///   - messages: The message received from the client.
    public init(metadata: Metadata, message: Message) {
      self.metadata = metadata
      self.message = message
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerRequest {
  /// A request received at the server containing a stream of messages.
  public struct Stream<Message: Sendable>: Sendable {
    /// Metadata received from the client at the start of the RPC.
    ///
    /// The metadata contains gRPC and transport specific entries in addition to user-specified
    /// metadata.
    public var metadata: Metadata

    /// A sequence of messages received from the client.
    ///
    /// The sequence may be iterated at most once.
    public var messages: RPCAsyncSequence<Message>

    /// Create a new streaming request.
    ///
    /// - Parameters:
    ///   - metadata: Metadata received from the client.
    ///   - messages: A sequence of messages received from the client.
    public init(metadata: Metadata, messages: RPCAsyncSequence<Message>) {
      self.metadata = metadata
      self.messages = messages
    }
  }
}

// MARK: - Conversion

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerRequest.Stream {
  public init(single request: ServerRequest.Single<Message>) {
    self.init(metadata: request.metadata, messages: .one(request.message))
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerRequest.Single {
  public init(stream request: ServerRequest.Stream<Message>) async throws {
    var iterator = request.messages.makeAsyncIterator()

    guard let message = try await iterator.next() else {
      throw RPCError(code: .internalError, message: "Empty stream.")
    }

    guard try await iterator.next() == nil else {
      throw RPCError(code: .internalError, message: "Too many messages.")
    }

    self = ServerRequest.Single(metadata: request.metadata, message: message)
  }
}
