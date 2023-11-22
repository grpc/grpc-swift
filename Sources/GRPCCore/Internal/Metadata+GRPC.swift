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
extension Metadata {
  @inlinable
  var previousRPCAttempts: Int? {
    get {
      self.firstString(forKey: .previousRPCAttempts).flatMap { Int($0) }
    }
    set {
      if let newValue = newValue {
        self.replaceOrAddString(String(describing: newValue), forKey: .previousRPCAttempts)
      } else {
        self.removeAllValues(forKey: .previousRPCAttempts)
      }
    }
  }

  @inlinable
  var retryPushback: RetryPushback? {
    return self.firstString(forKey: .retryPushbackMs).map {
      RetryPushback(milliseconds: $0)
    }
  }

  @inlinable
  var timeout: Duration? {
    // Temporary hack to support tests; only supports nanoseconds.
    guard let value = self.firstString(forKey: .timeout) else { return nil }
    guard value.utf8.last == UTF8.CodeUnit(ascii: "n") else { return nil }
    var index = value.utf8.endIndex
    value.utf8.formIndex(before: &index)
    guard let digits = String(value.utf8[..<index]) else { return nil }
    guard let nanoseconds = Int64(digits) else { return nil }
    return .nanoseconds(nanoseconds)
  }
}

extension Metadata {
  @usableFromInline
  enum GRPCKey: String, Sendable, Hashable {
    case timeout = "grpc-timeout"
    case retryPushbackMs = "grpc-retry-pushback-ms"
    case previousRPCAttempts = "grpc-previous-rpc-attempts"
  }

  @inlinable
  func firstString(forKey key: GRPCKey) -> String? {
    self[stringValues: key.rawValue].first(where: { _ in true })
  }

  @inlinable
  mutating func replaceOrAddString(_ value: String, forKey key: GRPCKey) {
    self.replaceOrAddString(value, forKey: key.rawValue)
  }

  @inlinable
  mutating func removeAllValues(forKey key: GRPCKey) {
    self.removeAllValues(forKey: key.rawValue)
  }
}

extension Metadata {
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  @usableFromInline
  enum RetryPushback: Hashable, Sendable {
    case retryAfter(Duration)
    case stopRetrying

    @inlinable
    init(milliseconds value: String) {
      if let milliseconds = Int64(value), milliseconds >= 0 {
        let (seconds, remainingMilliseconds) = milliseconds.quotientAndRemainder(dividingBy: 1000)
        // 1e18 attoseconds per second
        // 1e15 attoseconds per millisecond.
        let attoseconds = Int64(remainingMilliseconds) * 1_000_000_000_000_000
        self = .retryAfter(Duration(secondsComponent: seconds, attosecondsComponent: attoseconds))
      } else {
        // Negative or not parseable means stop trying.
        // Source: https://github.com/grpc/proposal/blob/master/A6-client-retries.md
        self = .stopRetrying
      }
    }
  }
}
