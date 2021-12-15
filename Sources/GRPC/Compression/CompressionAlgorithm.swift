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
public struct CompressionAlgorithm: Equatable, GRPCSendable {
  /// Identity compression; "no" compression but indicated via the "grpc-encoding" header.
  public static let identity = CompressionAlgorithm(.identity)
  public static let deflate = CompressionAlgorithm(.deflate)
  public static let gzip = CompressionAlgorithm(.gzip)

  // The order here is important: most compression to least.
  public static let all: [CompressionAlgorithm] = [.gzip, .deflate, .identity]

  /// The name of the compression algorithm.
  public var name: String {
    return self.algorithm.rawValue
  }

  internal enum Algorithm: String {
    case identity
    case deflate
    case gzip
  }

  internal let algorithm: Algorithm

  private init(_ algorithm: Algorithm) {
    self.algorithm = algorithm
  }

  internal init?(rawValue: String) {
    guard let algorithm = Algorithm(rawValue: rawValue) else {
      return nil
    }
    self.algorithm = algorithm
  }
}
