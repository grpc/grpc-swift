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

/// A type that provides a long-lived bidirectional communication channel to a server.
///
/// The client transport is responsible for providing streams to a backend on top of which an
/// RPC can be executed. A typical transport implementation will establish and maintain connections
/// to a server (or servers) and manage these over time, potentially closing idle connections and
/// creating new ones on demand. As such transports can be expensive to create and as such are
/// intended to be used as long-lived objects which exist for the lifetime of your application.
///
/// gRPC provides an in-process transport in the `GRPCInProcessTransport` module and HTTP/2
/// transport built on top of SwiftNIO in the https://github.com/grpc/grpc-swift-nio-transport
/// package.
@available(gRPCSwift 2.0, *)
public protocol ClientTransport<Bytes>: Sendable {
  /// The bag-of-bytes type used by the transport.
  associatedtype Bytes: GRPCContiguousBytes & Sendable

  typealias Inbound = RPCAsyncSequence<RPCResponsePart<Bytes>, any Error>
  typealias Outbound = RPCWriter<RPCRequestPart<Bytes>>.Closable

  /// Returns a throttle which gRPC uses to determine whether retries can be executed.
  ///
  /// Client transports don't need to implement the throttle or interact with it beyond its
  /// creation. gRPC will record the results of requests to determine whether retries can be
  /// performed.
  var retryThrottle: RetryThrottle? { get }

  /// Establish and maintain a connection to the remote destination.
  ///
  /// Maintains a long-lived connection, or set of connections, to a remote destination.
  /// Connections may be added or removed over time as required by the implementation and the
  /// demand for streams by the client.
  ///
  /// Implementations of this function will typically create a long-lived task group which
  /// maintains connections. The function exits when all open streams have been closed and new connections
  /// are no longer required by the caller who signals this by calling ``beginGracefulShutdown()``, or by cancelling the
  /// task this function runs in.
  func connect() async throws

  /// Signal to the transport that no new streams may be created.
  ///
  /// Existing streams may run to completion naturally but calling
  /// ``ClientTransport/withStream(descriptor:options:_:)`` should result in an ``RPCError`` with
  /// code ``RPCError/Code/failedPrecondition`` being thrown.
  ///
  /// If you want to forcefully cancel all active streams then cancel the task
  /// running ``connect()``.
  func beginGracefulShutdown()

  /// Opens a stream using the transport, and uses it as input into a user-provided closure alongisde the given context.
  ///
  /// - Important: The opened stream is closed after the closure is finished.
  ///
  /// Transport implementations should throw an ``RPCError`` with the following error codes:
  /// - ``RPCError/Code/failedPrecondition`` if the transport is closing or has been closed.
  /// - ``RPCError/Code/unavailable`` if it's temporarily not possible to create a stream and it
  ///   may be possible after some backoff period.
  ///
  /// - Parameters:
  ///   - descriptor: A description of the method to open a stream for.
  ///   - options: Options specific to the stream.
  ///   - closure: A closure that takes the opened stream and the client context as its parameters.
  /// - Returns: Whatever value was returned from `closure`.
  func withStream<T: Sendable>(
    descriptor: MethodDescriptor,
    options: CallOptions,
    _ closure: (_ stream: RPCStream<Inbound, Outbound>, _ context: ClientContext) async throws -> T
  ) async throws -> T

  /// Returns the configuration for a given method.
  ///
  /// - Parameter descriptor: The method to lookup configuration for.
  /// - Returns: Configuration for the method, if it exists.
  func config(forMethod descriptor: MethodDescriptor) -> MethodConfig?
}
