/*
 * Copyright 2019, gRPC Authors All rights reserved.
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

enum CompressionError: Error {
  case unsupported(CompressionMechanism)
}

internal enum CompressionMechanism: String, CaseIterable {
  case none
  case identity
  case gzip
  case deflate
  case snappy
  case unknown

  /// Whether there should be a corresponding header flag.
  var requiresFlag: Bool {
    switch self {
    case .none:
      return false
    case .identity, .gzip, .deflate, .snappy, .unknown:
      return true
    }
  }

  /// Whether the given compression is supported.
  var supported: Bool {
    switch self {
    case .identity, .none:
      return true
    case .gzip, .deflate, .snappy, .unknown:
      return false
    }
  }

  static var acceptEncoding: [CompressionMechanism] {
    return CompressionMechanism
      .allCases
      .filter { $0.supported && $0.requiresFlag }
  }
}
