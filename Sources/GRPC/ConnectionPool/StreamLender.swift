/*
 * Copyright 2021, gRPC Authors All rights reserved.
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

@usableFromInline
internal protocol StreamLender {
  /// `count` streams are being returned to the given `pool`.
  func returnStreams(_ count: Int, to pool: ConnectionPool)

  /// Update the total number of streams which may be available at given time for `pool` by `delta`.
  func changeStreamCapacity(by delta: Int, for pool: ConnectionPool)
}
