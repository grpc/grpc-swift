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

@Suite("ServerContext")
struct ServerContextTests {
  @Suite("CancellationHandle")
  struct CancellationHandle {
    @Test("Is cancelled")
    @available(gRPCSwift 2.0, *)
    func isCancelled() async throws {
      await withServerContextRPCCancellationHandle { handle in
        #expect(!handle.isCancelled)
        handle.cancel()
        #expect(handle.isCancelled)
      }
    }

    @Test("Wait for cancellation")
    @available(gRPCSwift 2.0, *)
    func waitForCancellation() async throws {
      await withServerContextRPCCancellationHandle { handle in
        await withTaskGroup(of: Void.self) { group in
          group.addTask {
            try? await handle.cancelled
          }
          handle.cancel()
          await group.waitForAll()
        }
      }
    }

    @Test("Binds task local")
    @available(gRPCSwift 2.0, *)
    func bindsTaskLocal() async throws {
      await withServerContextRPCCancellationHandle { handle in
        let signal = AsyncStream.makeStream(of: Void.self)

        await withRPCCancellationHandler {
          handle.cancel()
          for await _ in signal.stream {}
        } onCancelRPC: {
          // If the task local wasn't bound, this wouldn't run.
          signal.continuation.finish()
        }
      }

    }
  }
}
