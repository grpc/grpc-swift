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

public struct DecompressionLimit: Equatable {
  private enum Limit: Equatable {
    case ratio(Int)
    case absolute(Int)
  }
  private let limit: Limit

  /// Limits decompressed payloads to be no larger than the product of the compressed size
  /// and `ratio`.
  ///
  /// - Parameter ratio: The decompression ratio.
  /// - Precondition: `ratio` must be greater than zero.
  public static func ratio(_ ratio: Int) -> DecompressionLimit {
    precondition(ratio > 0, "ratio must be greater than zero")
    return DecompressionLimit(limit: .ratio(ratio))
  }

  /// Limits decompressed payloads to be no larger than the given `size`.
  ///
  /// - Parameter size: The absolute size limit of decompressed payloads.
  /// - Precondition: `size` must not be negative.
  public static func absolute(_ size: Int) -> DecompressionLimit {
    precondition(size >= 0, "absolute size must be non-negative")
    return DecompressionLimit(limit: .absolute(size))
  }
}

extension DecompressionLimit {
  /// The largest allowed decompressed size for this limit.
  func maximumDecompressedSize(compressedSize: Int) -> Int {
    switch self.limit {
    case .ratio(let ratio):
      return ratio * compressedSize
    case .absolute(let size):
      return size
    }
  }
}
