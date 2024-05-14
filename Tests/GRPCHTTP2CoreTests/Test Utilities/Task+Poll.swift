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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Task where Success == Never, Failure == Never {
  static func poll(
    every interval: Duration,
    timeLimit: Duration = .seconds(5),
    until predicate: () async throws -> Bool
  ) async throws -> Bool {
    var start = ContinuousClock.now
    let end = start.advanced(by: timeLimit)

    while end > .now {
      let canReturn = try await predicate()
      if canReturn { return true }

      start = start.advanced(by: interval)
      try await Task.sleep(until: start)
    }

    return false
  }
}
