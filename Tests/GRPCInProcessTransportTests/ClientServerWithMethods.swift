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

import GRPCCore
import GRPCInProcessTransport
import Testing

@Suite("withGRPCServer / withGRPCClient")
struct WithMethods {
  @Test("Actor isolation")
  func actorIsolation() async throws {
    let testActor = TestActor()
    #expect(await !testActor.hasRun)
    try await testActor.run()
    #expect(await testActor.hasRun)
  }
}

fileprivate actor TestActor {
  private(set) var hasRun = false

  func run() async throws {
    let inProcess = InProcessTransport()

    try await withGRPCServer(transport: inProcess.server, services: []) { server in
      try await withGRPCClient(transport: inProcess.client) { client in
        self.hasRun = true
      }
    }
  }
}
