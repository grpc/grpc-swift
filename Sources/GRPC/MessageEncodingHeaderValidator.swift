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

struct MessageEncodingHeaderValidator {
  var encoding: ServerMessageEncoding

  enum ValidationResult {
    /// The requested compression is supported.
    case supported(
      algorithm: CompressionAlgorithm,
      decompressionLimit: DecompressionLimit,
      acceptEncoding: [String]
    )

    /// The `requestEncoding` is not supported; `acceptEncoding` contains all algorithms we do
    /// support.
    case unsupported(requestEncoding: String, acceptEncoding: [String])

    /// No compression was requested.
    case noCompression
  }

  /// Validates the value of the 'grpc-encoding' header against compression algorithms supported and
  /// advertised by this peer.
  ///
  /// - Parameter requestEncoding: The value of the 'grpc-encoding' header.
  func validate(requestEncoding: String?) -> ValidationResult {
    switch (self.encoding, requestEncoding) {
    // Compression is enabled and the client sent a message encoding header. Do we support it?
    case let (.enabled(configuration), .some(header)):
      guard let algorithm = CompressionAlgorithm(rawValue: header) else {
        return .unsupported(
          requestEncoding: header,
          acceptEncoding: configuration.enabledAlgorithms.map { $0.name }
        )
      }

      if configuration.enabledAlgorithms.contains(algorithm) {
        return .supported(
          algorithm: algorithm,
          decompressionLimit: configuration.decompressionLimit,
          acceptEncoding: []
        )
      } else {
        // From: https://github.com/grpc/grpc/blob/master/doc/compression.md
        //
        //   Note that a peer MAY choose to not disclose all the encodings it supports. However, if
        //   it receives a message compressed in an undisclosed but supported encoding, it MUST
        //   include said encoding in the response's grpc-accept-encoding header.
        return .supported(
          algorithm: algorithm,
          decompressionLimit: configuration.decompressionLimit,
          acceptEncoding: configuration.enabledAlgorithms.map { $0.name } + CollectionOfOne(header)
        )
      }

    // Compression is disabled and the client sent a message encoding header. We don't support this
    // unless the header is "identity", which is no compression. Note this is different to the
    // supported but not advertised case since we have explicitly not enabled compression.
    case let (.disabled, .some(header)):
      guard let algorithm = CompressionAlgorithm(rawValue: header) else {
        return .unsupported(
          requestEncoding: header,
          acceptEncoding: []
        )
      }

      if algorithm == .identity {
        return .noCompression
      } else {
        return .unsupported(requestEncoding: header, acceptEncoding: [])
      }

    // The client didn't send a message encoding header.
    case (_, .none):
      return .noCompression
    }
  }
}
