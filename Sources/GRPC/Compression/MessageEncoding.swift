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
public struct Compression: Hashable, GRPCSendable {
  @usableFromInline
  internal enum _Wrapped: Hashable, GRPCSendable {
    case enabled
    case disabled
    case deferToCallDefault
  }

  @usableFromInline
  internal var _wrapped: _Wrapped

  private init(_ wrapped: _Wrapped) {
    self._wrapped = wrapped
  }

  /// Enable compression. Note that this will be ignored if compression has not been enabled or is
  /// not supported on the call.
  public static let enabled = Compression(.enabled)

  /// Disable compression.
  public static let disabled = Compression(.disabled)

  /// Defer to the call (the `CallOptions` for the client, and the context for the server) to
  /// determine whether compression should be used for the message.
  public static let deferToCallDefault = Compression(.deferToCallDefault)
}

extension Compression {
  @inlinable
  internal func isEnabled(callDefault: Bool) -> Bool {
    switch self._wrapped {
    case .enabled:
      return callDefault
    case .disabled:
      return false
    case .deferToCallDefault:
      return callDefault
    }
  }
}

/// Whether compression is enabled or disabled for a client.
public enum ClientMessageEncoding: GRPCSendable {
  /// Compression is enabled with the given configuration.
  case enabled(Configuration)
  /// Compression is disabled.
  case disabled
}

extension ClientMessageEncoding {
  internal var enabledForRequests: Bool {
    switch self {
    case let .enabled(configuration):
      return configuration.outbound != nil
    case .disabled:
      return false
    }
  }
}

extension ClientMessageEncoding {
  public struct Configuration: GRPCSendable {
    public init(
      forRequests outbound: CompressionAlgorithm?,
      acceptableForResponses inbound: [CompressionAlgorithm] = CompressionAlgorithm.all,
      decompressionLimit: DecompressionLimit
    ) {
      self.outbound = outbound
      self.inbound = inbound
      self.decompressionLimit = decompressionLimit
    }

    /// The compression algorithm used for outbound messages.
    public var outbound: CompressionAlgorithm?

    /// The set of compression algorithms advertised to the remote peer that they may use.
    public var inbound: [CompressionAlgorithm]

    /// The decompression limit acceptable for responses. RPCs which receive a message whose
    /// decompressed size exceeds the limit will be cancelled.
    public var decompressionLimit: DecompressionLimit

    /// Accept all supported compression on responses, do not compress requests.
    public static func responsesOnly(
      acceptable: [CompressionAlgorithm] = CompressionAlgorithm.all,
      decompressionLimit: DecompressionLimit
    ) -> Configuration {
      return Configuration(
        forRequests: .identity,
        acceptableForResponses: acceptable,
        decompressionLimit: decompressionLimit
      )
    }

    internal var acceptEncodingHeader: String {
      return self.inbound.map { $0.name }.joined(separator: ",")
    }
  }
}

/// Whether compression is enabled or disabled on the server.
public enum ServerMessageEncoding {
  /// Compression is supported with this configuration.
  case enabled(Configuration)
  /// Compression is not enabled. However, 'identity' compression is still supported.
  case disabled

  @usableFromInline
  internal var isEnabled: Bool {
    switch self {
    case .enabled:
      return true
    case .disabled:
      return false
    }
  }
}

extension ServerMessageEncoding {
  public struct Configuration {
    /// The set of compression algorithms advertised that we will accept from clients for requests.
    /// Note that clients may send us messages compressed with algorithms not included in this list;
    /// if we support it then we still accept the message.
    ///
    /// All cases of `CompressionAlgorithm` are supported.
    public var enabledAlgorithms: [CompressionAlgorithm]

    /// The decompression limit acceptable for requests. RPCs which receive a message whose
    /// decompressed size exceeds the limit will be cancelled.
    public var decompressionLimit: DecompressionLimit

    /// Create a configuration for server message encoding.
    ///
    /// - Parameters:
    ///   - enabledAlgorithms: The list of algorithms which are enabled.
    ///   - decompressionLimit: Decompression limit acceptable for requests.
    public init(
      enabledAlgorithms: [CompressionAlgorithm] = CompressionAlgorithm.all,
      decompressionLimit: DecompressionLimit
    ) {
      self.enabledAlgorithms = enabledAlgorithms
      self.decompressionLimit = decompressionLimit
    }
  }
}
