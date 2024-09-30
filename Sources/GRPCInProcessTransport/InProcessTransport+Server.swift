/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

public import GRPCCore

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension InProcessTransport {
  /// An in-process implementation of a ``ServerTransport``.
  ///
  /// This is useful when you're interested in testing your application without any actual networking layers
  /// involved, as the client and server will communicate directly with each other via in-process streams.
  ///
  /// To use this server, you call ``listen(streamHandler:)`` and iterate over the returned `AsyncSequence` to get all
  /// RPC requests made from clients (as ``RPCStream``s).
  /// To stop listening to new requests, call ``beginGracefulShutdown()``.
  ///
  /// - SeeAlso: ``ClientTransport``
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  public struct Server: ServerTransport, Sendable {
    public typealias Inbound = RPCAsyncSequence<RPCRequestPart, any Error>
    public typealias Outbound = RPCWriter<RPCResponsePart>.Closable

    private let newStreams: AsyncStream<RPCStream<Inbound, Outbound>>
    private let newStreamsContinuation: AsyncStream<RPCStream<Inbound, Outbound>>.Continuation

    /// Creates a new instance of ``Server``.
    public init() {
      (self.newStreams, self.newStreamsContinuation) = AsyncStream.makeStream()
    }

    /// Publish a new ``RPCStream``, which will be returned by the transport's ``events``
    /// successful case.
    ///
    /// - Parameter stream: The new ``RPCStream`` to publish.
    /// - Throws: ``RPCError`` with code ``RPCError/Code-swift.struct/failedPrecondition``
    /// if the server transport stopped listening to new streams (i.e., if ``beginGracefulShutdown()`` has been called).
    internal func acceptStream(_ stream: RPCStream<Inbound, Outbound>) throws {
      let yieldResult = self.newStreamsContinuation.yield(stream)
      if case .terminated = yieldResult {
        throw RPCError(
          code: .failedPrecondition,
          message: "The server transport is closed."
        )
      }
    }

    public func listen(
      streamHandler: @escaping @Sendable (
        _ stream: RPCStream<Inbound, Outbound>,
        _ context: ServerContext
      ) async -> Void
    ) async throws {
      await withDiscardingTaskGroup { group in
        for await stream in self.newStreams {
          group.addTask {
            let context = ServerContext(descriptor: stream.descriptor)
            await streamHandler(stream, context)
          }
        }
      }
    }

    /// Stop listening to any new ``RPCStream`` publications.
    ///
    /// - SeeAlso: ``ServerTransport``
    public func beginGracefulShutdown() {
      self.newStreamsContinuation.finish()
    }
  }
}
