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
#if compiler(>=5.6)
import NIOHPACK

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine {
  enum HandleMetadataAction {
    /// Invoke the user handler.
    case invokeHandler(Ref<UserInfo>, CallHandlerContext)
    /// Cancel the RPC, the metadata was not expected.
    case cancel
  }

  enum HandleMessageAction: Hashable {
    /// Forward the message to the interceptors, via the interceptor state machine.
    case forward
    /// Cancel the RPC, the message was not expected.
    case cancel
  }

  /// The same as 'HandleMessageAction.
  typealias HandleEndAction = HandleMessageAction

  enum SendMessageAction: Equatable {
    /// Intercept the message, but first intercept the headers if they are non-nil. Must go via
    /// the interceptor state machine first.
    case intercept(headers: HPACKHeaders?)
    /// Drop the message.
    case drop
  }

  enum SendStatusAction: Equatable {
    /// Intercept the status, providing the given trailers.
    case intercept(trailers: HPACKHeaders)
    /// Drop the status.
    case drop
  }

  enum CancelAction: Hashable {
    /// Cancel and nil out the handler 'bits'.
    case cancelAndNilOutHandlerComponents
    /// Don't do anything.
    case none
  }
}
#endif // compiler(>=5.6)
