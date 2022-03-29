/*
 * Copyright 2021, gRPC Authors All rights reserved.
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

/// NOTE: This file should be removed when the `async` branch of `swift-argument-parser` has been
///       released: https://github.com/apple/swift-argument-parser/tree/async

#if compiler(>=5.6)

import ArgumentParser

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
protocol AsyncParsableCommand: ParsableCommand {
  mutating func runAsync() async throws
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension AsyncParsableCommand {
  public mutating func run() throws {
    throw CleanExit.helpRequest(self)
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ParsableCommand {
  static func main(_ arguments: [String]? = nil) async {
    do {
      var command = try parseAsRoot(arguments)
      if var asyncCommand = command as? AsyncParsableCommand {
        try await asyncCommand.runAsync()
      } else {
        try command.run()
      }
    } catch {
      exit(withError: error)
    }
  }
}

#endif
