/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

/// An address to which a socket may connect or bind.
public struct SocketAddress: Hashable, Sendable {
  private enum Value: Hashable, Sendable {
    case ipv4(IPv4)
    case ipv6(IPv6)
    case unix(UnixDomainSocket)
    case vsock(VirtualSocket)
  }

  private var value: Value
  private init(_ value: Value) {
    self.value = value
  }

  /// Returns the address as an IPv4 address, if possible.
  public var ipv4: IPv4? {
    switch self.value {
    case .ipv4(let address):
      return address
    default:
      return nil
    }
  }

  /// Returns the address as an IPv6 address, if possible.
  public var ipv6: IPv6? {
    switch self.value {
    case .ipv6(let address):
      return address
    default:
      return nil
    }
  }

  /// Returns the address as an Unix domain socket address, if possible.
  public var unixDomainSocket: UnixDomainSocket? {
    switch self.value {
    case .unix(let address):
      return address
    default:
      return nil
    }
  }

  /// Returns the address as an VSOCK address, if possible.
  public var virtualSocket: VirtualSocket? {
    switch self.value {
    case .vsock(let address):
      return address
    default:
      return nil
    }
  }
}

extension SocketAddress {
  /// Creates a socket address by wrapping a ``SocketAddress/IPv4-swift.struct``.
  public static func ipv4(_ address: IPv4) -> Self {
    return Self(.ipv4(address))
  }

  /// Creates a socket address by wrapping a ``SocketAddress/IPv6-swift.struct``.
  public static func ipv6(_ address: IPv6) -> Self {
    return Self(.ipv6(address))
  }

  /// Creates a socket address by wrapping a ``SocketAddress/UnixDomainSocket-swift.struct``.
  public static func unixDomainSocket(_ address: UnixDomainSocket) -> Self {
    return Self(.unix(address))
  }

  /// Creates a socket address by wrapping a ``SocketAddress/VirtualSocket-swift.struct``.
  public static func vsock(_ address: VirtualSocket) -> Self {
    return Self(.vsock(address))
  }
}

extension SocketAddress {
  /// Creates an IPv4 socket address.
  public static func ipv4(host: String, port: Int) -> Self {
    return .ipv4(IPv4(host: host, port: port))
  }

  /// Creates an IPv6 socket address.
  public static func ipv6(host: String, port: Int) -> Self {
    return .ipv6(IPv6(host: host, port: port))
  }
  /// Creates a Unix socket address.
  public static func unixDomainSocket(path: String) -> Self {
    return .unixDomainSocket(UnixDomainSocket(path: path))
  }

  /// Create a Virtual Socket ('vsock') address.
  public static func vsock(contextID: VirtualSocket.ContextID, port: VirtualSocket.Port) -> Self {
    return .vsock(VirtualSocket(contextID: contextID, port: port))
  }
}

extension SocketAddress: CustomStringConvertible {
  public var description: String {
    switch self.value {
    case .ipv4(let address):
      return String(describing: address)
    case .ipv6(let address):
      return String(describing: address)
    case .unix(let address):
      return String(describing: address)
    case .vsock(let address):
      return String(describing: address)
    }
  }
}

extension SocketAddress {
  public struct IPv4: Hashable, Sendable {
    /// The resolved host address.
    public var host: String
    /// The port to connect to.
    public var port: Int

    /// Creates a new IPv4 address.
    ///
    /// - Parameters:
    ///   - host: Resolved host address.
    ///   - port: Port to connect to.
    public init(host: String, port: Int) {
      self.host = host
      self.port = port
    }
  }

  public struct IPv6: Hashable, Sendable {
    /// The resolved host address.
    public var host: String
    /// The port to connect to.
    public var port: Int

    /// Creates a new IPv6 address.
    ///
    /// - Parameters:
    ///   - host: Resolved host address.
    ///   - port: Port to connect to.
    public init(host: String, port: Int) {
      self.host = host
      self.port = port
    }
  }

  public struct UnixDomainSocket: Hashable, Sendable {
    /// The path name of the Unix domain socket.
    public var path: String

    /// Create a new Unix domain socket address.
    ///
    /// - Parameter path: The path name of the Unix domain socket.
    public init(path: String) {
      self.path = path
    }
  }

  public struct VirtualSocket: Hashable, Sendable {
    /// A context identifier.
    ///
    /// Indicates the source or destination which is either a virtual machine or the host.
    public var contextID: ContextID

    /// The port number.
    public var port: Port

    /// Create a new VSOCK address.
    ///
    /// - Parameters:
    ///   - contextID: The context ID (or 'cid') of the address.
    ///   - port: The port number.
    public init(contextID: ContextID, port: Port) {
      self.contextID = contextID
      self.port = port
    }

    public struct Port: Hashable, Sendable, RawRepresentable, ExpressibleByIntegerLiteral {
      /// The port number.
      public var rawValue: UInt32

      public init(rawValue: UInt32) {
        self.rawValue = rawValue
      }

      public init(integerLiteral value: UInt32) {
        self.rawValue = value
      }

      public init(_ value: Int) {
        self.init(rawValue: UInt32(bitPattern: Int32(truncatingIfNeeded: value)))
      }

      /// Used to bind to any port number.
      ///
      /// This is equal to `VMADDR_PORT_ANY (-1U)`.
      public static var any: Self {
        Self(rawValue: UInt32(bitPattern: -1))
      }
    }

    public struct ContextID: Hashable, Sendable, RawRepresentable, ExpressibleByIntegerLiteral {
      /// The context identifier.
      public var rawValue: UInt32

      public init(rawValue: UInt32) {
        self.rawValue = rawValue
      }

      public init(integerLiteral value: UInt32) {
        self.rawValue = value
      }

      public init(_ value: Int) {
        self.rawValue = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
      }

      /// Wildcard, matches any address.
      ///
      /// On all platforms, using this value with `bind(2)` means "any address".
      ///
      /// On Darwin platforms, the man page states this can be used with `connect(2)`
      /// to mean "this host".
      ///
      /// This is equal to `VMADDR_CID_ANY (-1U)`.
      public static var any: Self {
        Self(rawValue: UInt32(bitPattern: -1))
      }

      /// The address of the hypervisor.
      ///
      /// This is equal to `VMADDR_CID_HYPERVISOR (0)`.
      public static var hypervisor: Self {
        Self(rawValue: 0)
      }

      /// The address of the host.
      ///
      /// This is equal to `VMADDR_CID_HOST (2)`.
      public static var host: Self {
        Self(rawValue: 2)
      }

      /// The address for local communication (loopback).
      ///
      /// This directs packets to the same host that generated them.  This is useful for testing
      /// applications on a single host and for debugging.
      ///
      /// This is equal to `VMADDR_CID_LOCAL (1)` on platforms that define it.
      ///
      /// - Warning: `VMADDR_CID_LOCAL (1)` is available from Linux 5.6. Its use is unsupported on
      /// other platforms.
      /// - SeeAlso: https://man7.org/linux/man-pages/man7/vsock.7.html
      public static var local: Self {
        Self(rawValue: 1)
      }
    }
  }
}

extension SocketAddress.IPv4: CustomStringConvertible {
  public var description: String {
    "[ipv4]\(self.host):\(self.port)"
  }
}

extension SocketAddress.IPv6: CustomStringConvertible {
  public var description: String {
    "[ipv6]\(self.host):\(self.port)"
  }
}

extension SocketAddress.UnixDomainSocket: CustomStringConvertible {
  public var description: String {
    "[unix]\(self.path)"
  }
}

extension SocketAddress.VirtualSocket: CustomStringConvertible {
  public var description: String {
    "[vsock]\(self.contextID):\(self.port)"
  }
}

extension SocketAddress.VirtualSocket.ContextID: CustomStringConvertible {
  public var description: String {
    self == .any ? "-1" : String(describing: self.rawValue)
  }
}

extension SocketAddress.VirtualSocket.Port: CustomStringConvertible {
  public var description: String {
    self == .any ? "-1" : String(describing: self.rawValue)
  }
}
