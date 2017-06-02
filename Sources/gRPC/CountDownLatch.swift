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
import Foundation

/// A synchronization primitive used to synchronize gRPC operations
/// Initialize it with a count, a call to wait() will block until
/// signal() has been called the specified number of times.
public class CountDownLatch {
  private var condition : NSCondition
  private var count : Int

  public init(_ count : Int) {
    self.condition = NSCondition()
    self.count = count
  }

  public func signal() {
    self.condition.lock()
    self.count = self.count - 1
    self.condition.signal()
    self.condition.unlock()
  }

  public func wait() {
    var running = true
    while (running) {
      self.condition.lock()
      self.condition.wait()
      if (self.count == 0) {
        running = false
      }
      self.condition.unlock()
    }
  }
}
