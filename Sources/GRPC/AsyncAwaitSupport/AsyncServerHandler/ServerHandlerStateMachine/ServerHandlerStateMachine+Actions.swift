/*
 * Copyright 2022, gRPC Authors All rights reserved.
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
import NIOHPACK

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine {
  @usableFromInline
  enum HandleMetadataAction: Hashable {
    /// Invoke the user handler.
    case invokeHandler
    /// Cancel the RPC, the metadata was not expected.
    case cancel
  }

  @usableFromInline
  enum HandleMessageAction: Hashable {
    /// Forward the message to the interceptors, via the interceptor state machine.
    case forward
    /// Cancel the RPC, the message was not expected.
    case cancel
  }

  /// The same as 'HandleMessageAction.
  @usableFromInline
  typealias HandleEndAction = HandleMessageAction

  @usableFromInline
  enum SendMessageAction: Equatable {
    /// Intercept the message, but first intercept the headers if they are non-nil. Must go via
    /// the interceptor state machine first.
    case intercept(headers: HPACKHeaders?)
    /// Drop the message.
    case drop
  }

  @usableFromInline
  enum SendStatusAction: Equatable {
    /// Intercept the status, providing the given trailers.
    case intercept(requestHeaders: HPACKHeaders, trailers: HPACKHeaders)
    /// Drop the status.
    case drop
  }

  @usableFromInline
  enum CancelAction: Hashable {
    /// Cancel and nil out the handler 'bits'.
    case cancelAndNilOutHandlerComponents
    /// Don't do anything.
    case none
  }

  /// Tracks whether response metadata has been written.
  @usableFromInline
  internal enum ResponseMetadata {
    case notWritten(HPACKHeaders)
    case written

    /// Update the metadata. It must not have been written yet.
    @inlinable
    mutating func update(_ metadata: HPACKHeaders) -> Bool {
      switch self {
      case .notWritten:
        self = .notWritten(metadata)
        return true
      case .written:
        return false
      }
    }

    /// Returns the metadata if it has not been written and moves the state to
    /// `written`. Returns `nil` if it has already been written.
    @inlinable
    mutating func getIfNotWritten() -> HPACKHeaders? {
      switch self {
      case let .notWritten(metadata):
        self = .written
        return metadata
      case .written:
        return nil
      }
    }
  }
}
