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

@Suite("ServerStreamState")
struct ServerStreamStateTests {
  @Test("Does nothing on init")
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  func nothingOnInit() {
    let (state, _) = ServerStreamState.makeState()
    #expect(!state.isRPCCancelled)
  }

  @Test("Multiple iterators are allowed")
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  func multipleIteratorsAreAllowed() async {
    let (state, continuation) = ServerStreamState.makeState()
    await withTaskGroup(of: [ServerStreamEvent].self) { group in
      for _ in 0 ..< 100 {
        group.addTask {
          await state.events.reduce(into: []) { $0.append($1) }
        }
      }

      continuation.yield(.rpcCancelled)
      continuation.finish()

      for await events in group {
        #expect(events == [.rpcCancelled])
      }
    }
  }

  @Test("State is set after event is yielded")
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  func stateSetAfterYield() async {
    let (state, continuation) = ServerStreamState.makeState()
    #expect(!state.isRPCCancelled)
    continuation.yield(.rpcCancelled)
    #expect(state.isRPCCancelled)
  }

  @Test("Events are only delivered once")
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  func eventsAreOnlyDeliveredOnce() async {
    let (state, continuation) = ServerStreamState.makeState()
    continuation.yield(.rpcCancelled)
    continuation.yield(.rpcCancelled)
    continuation.yield(.rpcCancelled)
    continuation.finish()

    let events = await state.events.reduce(into: []) { $0.append($1) }
    #expect(events == [.rpcCancelled])
  }
}
