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

extension StatusCounts {
  /// Convert status count to a protobuf for sending to the driver process.
  /// - returns: The protobuf message for sending.
  public func toRequestResultCounts() -> [Grpc_Testing_RequestResultCount] {
    return counts.map { key, value -> Grpc_Testing_RequestResultCount in
      var grpc = Grpc_Testing_RequestResultCount()
      grpc.count = value
      grpc.statusCode = Int32(key)
      return grpc
    }
  }
}
