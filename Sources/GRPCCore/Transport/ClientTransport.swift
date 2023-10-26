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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public protocol ClientTransport: Sendable {
  associatedtype Inbound: (AsyncSequence & Sendable) where Inbound.Element == RPCResponsePart
  associatedtype Outbound: ClosableRPCWriterProtocol<RPCRequestPart>

  /// Returns a throttle which gRPC uses to determine whether retries can be executed.
  ///
  /// Client transports don't need to implement the throttle or interact with it beyond its
  /// creation. gRPC will record the results of requests to determine whether retries can be
  /// performed.
  var retryThrottle: RetryThrottle { get }

  /// Establish and maintain a connection to the remote destination.
  ///
  /// Maintains a long-lived connection, or set of connections, to a remote destination.
  /// Connections may be added or removed over time as required by the implementation and the
  /// demand for streams by the client.
  ///
  /// Implementations of this function will typically create a long-lived task group which
  /// maintains connections. The function exits when connections are no longer required by
  /// the caller who signals this by calling ``close()`` to indicate that no new streams are
  /// required or by cancelling the task this function runs in.
  ///
  /// - Parameter lazily: Whether the transport should establish connections lazily, that is,
  ///     when the first stream is opened or eagerly, when this function is called. If `false`
  ///     then the transport should attempt to establish a connection immediately. Note that
  ///     this is a _hint_: transports aren't required to respect this value and you should
  ///     refer to the documentation of the transport you're using to check whether it's supported.
  func connect(lazily: Bool) async throws

  /// Signal to the transport that no new streams may be created.
  ///
  /// Existing streams may run to completion naturally but calling ``openStream(descriptor:)``
  /// should result in an ``RPCError`` with code ``RPCError/Code/failedPrecondition`` being thrown.
  ///
  /// If you want to forcefully cancel all active streams then cancel the task
  /// running ``connect(lazily:)``.
  func close()

  /// Open a stream using the transport.
  ///
  /// Transport implementations should throw an ``RPCError`` with the following error codes:
  /// - ``RPCError/Code/failedPrecondition`` if the transport is closing or has been closed.
  /// - ``RPCError/Code/unavailable`` if it's temporarily not possible to create a stream and it
  ///   may be possible after some backoff period.
  ///
  /// - Parameter descriptor: A description of the method to open a stream for.
  /// - Returns: A stream.
  func openStream(
    descriptor: MethodDescriptor
  ) async throws -> RPCStream<Inbound, Outbound>

  /// Returns the execution configuration for a given method.
  ///
  /// - Parameter descriptor: The method to lookup configuration for.
  /// - Returns: Execution configuration for the method, if it exists.
  func executionConfiguration(
    forMethod descriptor: MethodDescriptor
  ) -> ClientRPCExecutionConfiguration?
}
