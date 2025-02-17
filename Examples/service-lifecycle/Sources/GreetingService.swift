/*
 * Copyright 2025, gRPC Authors All rights reserved.
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

import GRPCCore
import ServiceLifecycle
import Synchronization

/// Implements the "Hello World" gRPC service but modifies the greeting on a timer.
///
/// The service conforms to the 'ServiceLifecycle.Service' and uses its 'run()' method
/// to execute the run loop which updates the greeting.
final class GreetingService {
  private let updateInterval: Duration
  private let currentGreetingIndex: Mutex<Int>
  private let greetings: [String] = [
    "Hello",
    "你好",
    "नमस्ते",
    "Hola",
    "Bonjour",
    "Olá",
    "Здравствуйте",
    "こんにちは",
    "Ciao",
  ]

  private func personalizedGreeting(forName name: String) -> String {
    let index = self.currentGreetingIndex.withLock { $0 }
    return "\(self.greetings[index]), \(name)!"
  }

  private func periodicallyUpdateGreeting() async throws {
    while !Task.isShuttingDownGracefully {
      try await Task.sleep(for: self.updateInterval)

      // Increment the greeting index.
      self.currentGreetingIndex.withLock { index in
        // '!' is fine; greetings is non-empty.
        index = self.greetings.indices.randomElement()!
      }
    }
  }

  init(updateInterval: Duration) {
    // '!' is fine; greetings is non-empty.
    let index = self.greetings.indices.randomElement()!
    self.currentGreetingIndex = Mutex(index)
    self.updateInterval = updateInterval
  }
}

extension GreetingService: Helloworld_Greeter.SimpleServiceProtocol {
  func sayHello(
    request: Helloworld_HelloRequest,
    context: ServerContext
  ) async throws -> Helloworld_HelloReply {
    return .with {
      $0.message = self.personalizedGreeting(forName: request.name)
    }
  }
}

extension GreetingService: Service {
  func run() async throws {
    try await self.periodicallyUpdateGreeting()
  }
}
