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
import Atomics

@testable import GRPCCore

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension InProcessServerTransport {
  func spawnClientTransport(
    throttle: RetryThrottle = RetryThrottle(maximumTokens: 10, tokenRatio: 0.1)
  ) -> InProcessClientTransport {
    return InProcessClientTransport(
      server: self,
      executionConfigurations: .init(
        defaultConfiguration: .init(
          hedgingPolicy: .init(
            maximumAttempts: 2,
            hedgingDelay: .milliseconds(100),
            nonFatalStatusCodes: []
          )
        )
      )
    )
  }
}
