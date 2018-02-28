/*
 * Copyright 2016, gRPC Authors All rights reserved.
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
#if SWIFT_PACKAGE
  import CgRPC
#endif

/// A general-purpose Mutex used to synchronize gRPC operations
/// but it can be used anywhere
public class Mutex {
  /// Pointer to underlying C representation
  private let underlyingMutex: UnsafeMutableRawPointer

  /// Initializes a Mutex
  public init() {
    underlyingMutex = cgrpc_mutex_create()
  }

  deinit {
    cgrpc_mutex_destroy(underlyingMutex)
  }

  /// Locks a Mutex
  ///
  /// Waits until no thread has a lock on the Mutex,
  /// causes the calling thread to own an exclusive lock on the Mutex,
  /// then returns.
  ///
  /// May block indefinitely or crash if the calling thread has a lock on the Mutex.
  public func lock() {
    cgrpc_mutex_lock(underlyingMutex)
  }

  /// Unlocks a Mutex
  ///
  /// Releases an exclusive lock on the Mutex held by the calling thread.
  public func unlock() {
    cgrpc_mutex_unlock(underlyingMutex)
  }

  /// Runs a block within a locked mutex
  ///
  /// Parameter block: the code to run while the mutex is locked
  public func synchronize(block: () throws -> Void) rethrows {
    lock()
    try block()
    unlock()
  }
}
