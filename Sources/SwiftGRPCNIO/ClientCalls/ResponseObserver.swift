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
import Foundation
import NIO
import SwiftProtobuf

/// A response message observer.
///
/// - succeedPromise: succeed the given promise on receipt of a message.
/// - callback: calls the given callback for each response observed.
public enum ResponseObserver<ResponseMessage: Message> {
  case succeedPromise(EventLoopPromise<ResponseMessage>)
  case callback((ResponseMessage) -> Void)

  /// Observe the given message.
  func observe(_ message: ResponseMessage) {
    switch self {
    case .callback(let callback):
      callback(message)

    case .succeedPromise(let promise):
      promise.succeed(message)
    }
  }

  var expectsMultipleResponses: Bool {
    switch self {
    case .callback:
      return true

    case .succeedPromise:
      return false
    }
  }
}
