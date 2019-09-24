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

public enum CompressionError: Error {
  case unsupported(CompressionMechanism)
}

/// The mechanism to use for message compression.
public enum CompressionMechanism: String, CaseIterable {
  // No compression was indicated.
  case none

  // Compression indicated via a header.
  case gzip
  case deflate
  case snappy
  // This is the same as `.none` but was indicated via a "grpc-encoding" and may be listed
  // in the "grpc-accept-encoding" header. If this is the compression mechanism being used
  // then the compression flag should be indicated in length-prefxied messages (see
  // `LengthPrefixedMessageReader`).
  case identity

  // Compression indicated via a header, but not one listed in the specification.
  case unknown

  init(value: String?) {
    self = value.map { CompressionMechanism(rawValue: $0) ?? .unknown } ?? .none
  }

  /// Whether the compression flag in gRPC length-prefixed messages should be set or not.
  ///
  /// See `LengthPrefixedMessageReader` for the message format.
  public var requiresFlag: Bool {
    switch self {
    case .none:
      return false

    case .identity, .gzip, .deflate, .snappy, .unknown:
      return true
    }
  }

  /// Whether the given compression is supported.
  public var supported: Bool {
    switch self {
    case .identity, .none:
      return true

    case .gzip, .deflate, .snappy, .unknown:
      return false
    }
  }

  /// A string containing the supported compression mechanisms to list in the "grpc-accept-encoding" header.
  static let acceptEncodingHeader: String = {
    return CompressionMechanism
      .allCases
      .filter { $0.supported && $0.requiresFlag }
      .map { $0.rawValue }
      .joined(separator: ", ")
  }()
}
