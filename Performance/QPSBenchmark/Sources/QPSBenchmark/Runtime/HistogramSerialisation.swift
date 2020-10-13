/*
 * Copyright 2020, gRPC Authors All rights reserved.
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

import BenchmarkUtils
import Foundation

extension Grpc_Testing_HistogramData {
  /// Construct a RPC histogram suitable for sending.
  /// - parameters:
  ///     - from: The internal histogram representation.
  init(from: Histogram) {
    self.init()
    self.bucket = from.buckets
    self.minSeen = from.minSeen
    self.maxSeen = from.maxSeen
    self.sum = from.sum
    self.sumOfSquares = from.sumOfSquares
    self.count = from.countOfValuesSeen
  }
}
