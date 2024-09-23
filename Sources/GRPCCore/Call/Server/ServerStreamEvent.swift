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

/// An out-of-band event which can happen to the underlying stream
/// which an RPC is executing on.
public struct ServerStreamEvent: Hashable, Sendable {
  internal enum Value: Hashable, Sendable {
    case rpcCancelled
  }

  internal var value: Value

  private init(_ value: Value) {
    self.value = value
  }

  /// The RPC was cancelled and the service should stop processing it.
  ///
  /// RPCs can be cancelled for a number of reasons including, but not limited to:
  /// - it took too long to complete
  /// - the client closed the underlying stream
  /// - the stream closed unexpectedly (due to a network failure, for example)
  /// - the server initiated a graceful shutdown
  ///
  /// You should stop processing the RPC and cleanup any associated state if you
  /// receive this event.
  public static let rpcCancelled = Self(.rpcCancelled)
}

extension ServerStreamEvent: CustomStringConvertible {
  public var description: String {
    String(describing: self.value)
  }
}
