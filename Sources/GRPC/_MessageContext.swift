/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import SwiftProtobuf

/// Provides a context for gRPC payloads.
///
/// - Important: This is **NOT** part of the public API.
public final class _MessageContext<M: GRPCPayload> {
  /// The message being sent or received.
  let message: M

  /// Whether the message was, or should be compressed.
  let compressed: Bool

  /// Constructs a box for a value.
  ///
  /// - Important: This is **NOT** part of the public API.
  public init(_ message: M, compressed: Bool) {
    self.message = message
    self.compressed = compressed
  }
}
