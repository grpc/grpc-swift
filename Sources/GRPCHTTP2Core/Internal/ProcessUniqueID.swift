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

private import Synchronization

/// An ID which is unique within this process.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct ProcessUniqueID: Hashable, Sendable, CustomStringConvertible {
  private static let source = Atomic(UInt64(0))
  private let rawValue: UInt64

  init() {
    let (_, newValue) = Self.source.add(1, ordering: .relaxed)
    self.rawValue = newValue
  }

  var description: String {
    String(describing: self.rawValue)
  }
}

/// A process-unique ID for a subchannel.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
package struct SubchannelID: Hashable, Sendable, CustomStringConvertible {
  private let id = ProcessUniqueID()
  package init() {}
  package var description: String {
    "subchan_\(self.id)"
  }
}

/// A process-unique ID for a load-balancer.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct LoadBalancerID: Hashable, Sendable, CustomStringConvertible {
  private let id = ProcessUniqueID()
  var description: String {
    "lb_\(self.id)"
  }
}

/// A process-unique ID for an entry in a queue.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct QueueEntryID: Hashable, Sendable, CustomStringConvertible {
  private let id = ProcessUniqueID()
  var description: String {
    "q_entry_\(self.id)"
  }
}
