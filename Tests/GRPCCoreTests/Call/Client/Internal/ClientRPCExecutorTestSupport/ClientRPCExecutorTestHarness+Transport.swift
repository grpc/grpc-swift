/*
 * Copyright 2023-2025, gRPC Authors All rights reserved.
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
import GRPCInProcessTransport

extension InProcessTransport.Server {
  func spawnClientTransport(
    throttle: RetryThrottle = RetryThrottle(maxTokens: 10, tokenRatio: 0.1)
  ) -> InProcessTransport.Client {
    return InProcessTransport.Client(server: self, peer: self.peer)
  }
}
