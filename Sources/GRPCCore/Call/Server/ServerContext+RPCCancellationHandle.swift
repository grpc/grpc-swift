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

import Synchronization

extension ServerContext {
  @TaskLocal
  internal static var rpcCancellation: RPCCancellationHandle?

  /// A handle for the cancellation status of the RPC.
  public struct RPCCancellationHandle: Sendable {
    internal let manager: ServerCancellationManager

    /// Create a cancellation handle.
    ///
    /// To create an instance of this handle appropriately bound to a `Task`
    /// use ``withServerContextRPCCancellationHandle(_:)``.
    public init() {
      self.manager = ServerCancellationManager()
    }

    /// Returns whether the RPC has been cancelled.
    public var isCancelled: Bool {
      self.manager.isRPCCancelled
    }

    /// Waits until the RPC has been cancelled.
    ///
    /// Throws a `CancellationError` if the `Task` is cancelled.
    ///
    /// You can also be notified when an RPC is cancelled by using
    /// ``withRPCCancellationHandler(operation:onCancelRPC:)``.
    public var cancelled: Void {
      get async throws {
        try await self.manager.suspendUntilRPCIsCancelled()
      }
    }

    /// Signal that the RPC should be cancelled.
    ///
    /// This is idempotent: calling it more than once has no effect.
    public func cancel() {
      self.manager.cancelRPC()
    }
  }
}

/// Execute an operation with an RPC cancellation handler that's immediately invoked
/// if the RPC is canceled.
///
/// RPCs can be cancelled for a number of reasons including:
/// 1. The RPC was taking too long to process and a timeout passed.
/// 2. The remote peer closed the underlying stream, either because they were no longer
///    interested in the result or due to a broken connection.
/// 3. The server began shutting down.
///
/// - Important: This only applies to RPCs on the server.
/// - Parameters:
///   - operation: The operation to execute.
///   - handler: The handler which is invoked when the RPC is cancelled.
/// - Throws: Any error thrown by the `operation` closure.
/// - Returns: The result of the `operation` closure.
public func withRPCCancellationHandler<Result, Failure: Error>(
  operation: () async throws(Failure) -> Result,
  onCancelRPC handler: @Sendable @escaping () -> Void
) async throws(Failure) -> Result {
  guard let manager = ServerContext.rpcCancellation?.manager,
    let id = manager.addRPCCancelledHandler(handler)
  else {
    return try await operation()
  }

  defer {
    manager.removeRPCCancelledHandler(withID: id)
  }

  return try await operation()
}

/// Provides scoped access to a server RPC cancellation handle.
///
/// The cancellation handle should be passed to a ``ServerContext`` and last
/// the duration of the RPC.
///
/// - Important: This function is intended for use when implementing
///   a ``ServerTransport``.
///
/// If you want to be notified about RPCs being cancelled
/// use ``withRPCCancellationHandler(operation:onCancelRPC:)``.
///
/// - Parameter operation: The operation to execute with the handle.
public func withServerContextRPCCancellationHandle<Success, Failure: Error>(
  _ operation: (ServerContext.RPCCancellationHandle) async throws(Failure) -> Success
) async throws(Failure) -> Success {
  let handle = ServerContext.RPCCancellationHandle()
  let result = await ServerContext.$rpcCancellation.withValue(handle) {
    // Wrap up the outcome in a result as 'withValue' doesn't support typed throws.
    return await Swift.Result { () async throws(Failure) -> Success in
      return try await operation(handle)
    }
  }

  return try result.get()
}
