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

import GRPCCore

/// An in-process implementation of a ``ServerTransport``.
///
/// This is useful when you're interested in testing your application without any actual networking layers
/// involved, as the client and server will communicate directly with each other via in-process streams.
///
/// To use this server, you call ``listen()`` and iterate over the returned `AsyncSequence` to get all
/// RPC requests made from clients (as ``RPCStream``s).
/// To stop listening to new requests, call ``stopListening()``.
///
/// - SeeAlso: ``ClientTransport``
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct InProcessServerTransport: ServerTransport, Sendable {
  public typealias Inbound = RPCAsyncSequence<RPCRequestPart>
  public typealias Outbound = RPCWriter<RPCResponsePart>.Closable

  private let newStreams: AsyncStream<RPCStream<Inbound, Outbound>>
  private let newStreamsContinuation: AsyncStream<RPCStream<Inbound, Outbound>>.Continuation

  /// Creates a new instance of ``InProcessServerTransport``.
  public init() {
    (self.newStreams, self.newStreamsContinuation) = AsyncStream.makeStream()
  }

  /// Publish a new ``RPCStream``, which will be returned by the transport's ``events``
  /// successful case.
  ///
  /// - Parameter stream: The new ``RPCStream`` to publish.
  /// - Throws: ``RPCError`` with code ``RPCError/Code-swift.struct/failedPrecondition``
  /// if the server transport stopped listening to new streams (i.e., if ``stopListening()`` has been called).
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
    _ streamHandler: @escaping (RPCStream<Inbound, Outbound>) async -> Void
  ) async throws {
    await withDiscardingTaskGroup { group in
      for await stream in self.newStreams {
        group.addTask {
          await streamHandler(stream)
        }
      }
    }
  }

  /// Stop listening to any new ``RPCStream`` publications.
  ///
  /// All further calls to ``acceptStream(_:)`` will not produce any new elements on the
  /// ``RPCAsyncSequence`` returned by ``listen()``.
  ///
  /// - SeeAlso: ``ServerTransport``
  public func stopListening() {
    self.newStreamsContinuation.finish()
  }
}
