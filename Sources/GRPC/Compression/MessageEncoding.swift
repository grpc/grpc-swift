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

extension ClientConnection.Configuration {
  public struct MessageEncoding {
    public init(
      forRequests outbound: CompressionAlgorithm?,
      acceptableForResponses inbound: [CompressionAlgorithm]
    ) {
      self.outbound = outbound
      self.inbound = inbound
    }

    /// The compression algorithm used for outbound messages.
    public var outbound: CompressionAlgorithm?

    /// The set of compression algorithms advertised to the remote peer that they may use.
    public var inbound: [CompressionAlgorithm]

    /// No compression.
    public static let none = MessageEncoding(
      forRequests: nil,
      acceptableForResponses: []
    )

    /// Accept all supported compression on responses, do not compress requests.
    public static let responsesOnly = MessageEncoding(
      forRequests: .identity,
      acceptableForResponses: CompressionAlgorithm.all
    )
  }
}

extension ClientConnection.Configuration.MessageEncoding {
  var acceptEncodingHeader: String {
    return self.inbound.map { $0.name }.joined(separator: ",")
  }
}
