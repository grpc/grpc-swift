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

/// Supported message compression algorithms.
///
/// These algorithms are indicated in the "grpc-encoding" header. As such, a lack of "grpc-encoding"
/// header indicates that there is no message compression.
enum CompressionAlgorithm: String {
  /// Identity compression; "no" compression but indicated via the "grpc-encoding" header.
  case identity
}
