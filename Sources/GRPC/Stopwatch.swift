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

internal class Stopwatch {
  private let dateProvider: () -> Date
  private let start: Date

  init(provider: @escaping () -> Date = { Date() }) {
    self.dateProvider = provider
    self.start = provider()
  }

  static func start() -> Stopwatch {
    return Stopwatch()
  }

  func elapsed() -> TimeInterval {
    return self.dateProvider().timeIntervalSince(self.start)
  }

  func elapsedMillis() -> Int64 {
    return Int64(self.elapsed() * 1_000)
  }
}
