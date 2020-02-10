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


/// Whether compression should be enabled for the message.
public enum Compression {
  /// Enable compression. Note that this will be ignored if compression has not been enabled or is
  /// not supported on the call.
  case enabled

  /// Disable compression.
  case disabled

  /// Defer to the call (the `CallOptions` for the client, and the context for the server) to
  /// determine whether compression should be used for the message.
  case deferToCallDefault
}

extension Compression {
  func isEnabled(enabledOnCall: Bool) -> Bool {
    switch self {
    case .enabled:
      return enabledOnCall
    case .disabled:
      return false
    case .deferToCallDefault:
      return enabledOnCall
    }
  }
}

extension CallOptions {
  public struct MessageEncoding {
    public init(
      forRequests outbound: CompressionAlgorithm?,
      acceptableForResponses inbound: [CompressionAlgorithm] = CompressionAlgorithm.all
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

    /// Whether compression is enabled for requests.
    internal var enabledForRequests: Bool {
      return self.outbound != nil
    }
  }
}

extension CallOptions.MessageEncoding {
  var acceptEncodingHeader: String {
    return self.inbound.map { $0.name }.joined(separator: ",")
  }
}

extension Server.Configuration {
  public struct MessageEncoding {
    /// The set of compression algorithms advertised that we will accept from clients. Note that
    /// clients may send us messages compressed with algorithms not included in this list; if we
    /// support it then we still accept the message.
    public var enabled: [CompressionAlgorithm]

    public init(enabled: [CompressionAlgorithm]) {
      self.enabled = enabled
    }

    // All supported algorithms are enabled.
    public static let enabled = MessageEncoding(enabled: CompressionAlgorithm.all)

    /// No compression.
    public static let none = MessageEncoding(enabled: [.identity])
  }

}
