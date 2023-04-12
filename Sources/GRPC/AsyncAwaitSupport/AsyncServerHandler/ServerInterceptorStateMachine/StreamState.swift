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
extension ServerInterceptorStateMachine {
  @usableFromInline
  internal enum StreamFilter: Hashable {
    case accept
    case reject
  }

  @usableFromInline
  internal enum InboundStreamState: Hashable {
    case idle
    case receivingMessages
    case done

    @inlinable
    mutating func receiveMetadata() -> StreamFilter {
      switch self {
      case .idle:
        self = .receivingMessages
        return .accept
      case .receivingMessages, .done:
        return .reject
      }
    }

    @inlinable
    func receiveMessage() -> StreamFilter {
      switch self {
      case .receivingMessages:
        return .accept
      case .idle, .done:
        return .reject
      }
    }

    @inlinable
    mutating func receiveEnd() -> StreamFilter {
      switch self {
      case .idle, .receivingMessages:
        self = .done
        return .accept
      case .done:
        return .reject
      }
    }
  }

  @usableFromInline
  internal enum OutboundStreamState: Hashable {
    case idle
    case writingMessages
    case done

    @inlinable
    mutating func sendMetadata() -> StreamFilter {
      switch self {
      case .idle:
        self = .writingMessages
        return .accept
      case .writingMessages, .done:
        return .reject
      }
    }

    @inlinable
    func sendMessage() -> StreamFilter {
      switch self {
      case .writingMessages:
        return .accept
      case .idle, .done:
        return .reject
      }
    }

    @inlinable
    mutating func sendEnd() -> StreamFilter {
      switch self {
      case .idle, .writingMessages:
        self = .done
        return .accept
      case .done:
        return .reject
      }
    }
  }
}
