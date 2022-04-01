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
extension ServerInterceptorStateMachine {
  @usableFromInline
  enum InterceptAction: Hashable {
    /// Forward the message to the interceptor pipeline.
    case intercept
    /// Cancel the call.
    case cancel
    /// Drop the message.
    case drop

    @inlinable
    init(from streamFilter: ServerInterceptorStateMachine.StreamFilter) {
      switch streamFilter {
      case .accept:
        self = .intercept
      case .reject:
        self = .cancel
      }
    }
  }

  @usableFromInline
  enum InterceptedAction: Hashable {
    /// Forward the message to the network or user handler.
    case forward
    /// Cancel the call.
    case cancel
    /// Drop the message.
    case drop

    @inlinable
    init(from streamFilter: ServerInterceptorStateMachine.StreamFilter) {
      switch streamFilter {
      case .accept:
        self = .forward
      case .reject:
        self = .cancel
      }
    }
  }

  @usableFromInline
  enum CancelAction: Hashable {
    /// Write a status then nil out the interceptor pipeline.
    case sendStatusThenNilOutInterceptorPipeline
    /// Nil out the interceptor pipeline.
    case nilOutInterceptorPipeline
    /// Do nothing.
    case none
  }
}
#endif // compiler(>=5.6)
