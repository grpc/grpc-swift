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
import Testing

@Suite
struct ServerCancellationManagerTests {
  @Test("Isn't cancelled after init")
  @available(gRPCSwift 2.0, *)
  func isNotCancelled() {
    let manager = ServerCancellationManager()
    #expect(!manager.isRPCCancelled)
  }

  @Test("Is cancelled")
  @available(gRPCSwift 2.0, *)
  func isCancelled() {
    let manager = ServerCancellationManager()
    manager.cancelRPC()
    #expect(manager.isRPCCancelled)
  }

  @Test("Cancellation handler runs")
  @available(gRPCSwift 2.0, *)
  func addCancellationHandler() async throws {
    let manager = ServerCancellationManager()
    let signal = AsyncStream.makeStream(of: Void.self)

    let id = manager.addRPCCancelledHandler {
      signal.continuation.finish()
    }

    #expect(id != nil)
    manager.cancelRPC()
    let events: [Void] = await signal.stream.reduce(into: []) { $0.append($1) }
    #expect(events.isEmpty)
  }

  @Test("Cancellation handler runs immediately when already cancelled")
  @available(gRPCSwift 2.0, *)
  func addCancellationHandlerAfterCancelled() async throws {
    let manager = ServerCancellationManager()
    let signal = AsyncStream.makeStream(of: Void.self)
    manager.cancelRPC()

    let id = manager.addRPCCancelledHandler {
      signal.continuation.finish()
    }

    #expect(id == nil)
    let events: [Void] = await signal.stream.reduce(into: []) { $0.append($1) }
    #expect(events.isEmpty)
  }

  @Test("Remove cancellation handler")
  @available(gRPCSwift 2.0, *)
  func removeCancellationHandler() async throws {
    let manager = ServerCancellationManager()

    let id = manager.addRPCCancelledHandler {
      Issue.record("Unexpected cancellation")
    }

    #expect(id != nil)
    manager.removeRPCCancelledHandler(withID: id!)
    manager.cancelRPC()
  }

  @Test("Wait for cancellation")
  @available(gRPCSwift 2.0, *)
  func waitForCancellation() async throws {
    let manager = ServerCancellationManager()
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await manager.suspendUntilRPCIsCancelled()
      }

      manager.cancelRPC()
      try await group.waitForAll()
    }
  }
}
