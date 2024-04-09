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

import Atomics

enum RawID {
  private static let source = ManagedAtomic(0)

  static func next() -> Int {
    self.source.loadThenWrappingIncrement(ordering: .relaxed)
  }
}

/// The ID of a connection pool.
public struct GRPCConnectionPoolID: Hashable, Sendable, CustomStringConvertible {
  private var rawValue: Int

  private init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static func next() -> Self {
    return Self(rawValue: RawID.next())
  }

  public var description: String {
    "ConnectionPool(\(self.rawValue))"
  }
}

/// The ID of a sub-pool in a connection pool.
public struct GRPCSubPoolID: Hashable, Sendable, CustomStringConvertible {
  private var rawValue: Int

  private init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static func next() -> Self {
    return Self(rawValue: RawID.next())
  }

  public var description: String {
    "SubPool(\(self.rawValue))"
  }
}
