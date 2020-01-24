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
      requests: CompressionAlgorithm?,
      responses: [CompressionAlgorithm]
    ) {
      self.outbound = requests
      self.inbound = responses
    }

    /// The compression algorithm used for outbound messages.
    public internal(set) var outbound: CompressionAlgorithm?

    /// The set of compression algorithms advertised to the remote peer that they may use.
    public internal(set) var inbound: [CompressionAlgorithm]

    /// No compression.
    public static let none = MessageEncoding(requests: nil, responses: [.identity])

    /// Accept all supported compression on responses, do not compress requests.
    public static let onlyResponses = MessageEncoding(requests: nil, responses: CompressionAlgorithm.all)
  }
}

extension ClientConnection.Configuration.MessageEncoding {
  var acceptEncoding: String {
    return self.inbound.map { $0.name }.joined(separator: ",")
  }
}
