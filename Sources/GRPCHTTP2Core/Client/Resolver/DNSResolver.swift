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

private import Dispatch

#if canImport(Darwin)
package import Darwin
#elseif canImport(Glibc)
package import Glibc
#elseif canImport(Musl)
package import Musl
#else
#error("The GRPCHTTP2Core module was unable to identify your C library.")
#endif
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
/// An asynchronous non-blocking DNS resolver built on top of the libc `getaddrinfo` function.
package enum DNSResolver {
  private static let dispatchQueue = DispatchQueue(
    label: "io.grpc.DNSResolver"
  )

  /// Resolves a hostname and port number to a list of socket addresses. This method is non-blocking.
  package static func resolve(host: String, port: Int) async throws -> [SocketAddress] {
    if Task.isCancelled {
      return []
    }

    return try await withCheckedThrowingContinuation { continuation in
      Self.dispatchQueue.async {
        do {
          let result = try Self.resolveBlocking(host: host, port: port)
          continuation.resume(returning: result)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Resolves a hostname and port number to a list of socket addresses.
  ///
  /// Calls to `getaddrinfo` are blocking and this method calls `getaddrinfo` directly. Hence, this method is also blocking.
  private static func resolveBlocking(host: String, port: Int) throws -> [SocketAddress] {
    var result: UnsafeMutablePointer<addrinfo>?
    defer {
      if let result {
        // Release memory allocated by a successful call to getaddrinfo
        freeaddrinfo(result)
      }
    }

    var hints = addrinfo()
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = IPPROTO_TCP

    let errorCode = getaddrinfo(host, String(port), &hints, &result)

    guard errorCode == 0, let result else {
      throw DNSResolver.GetAddrInfoError(code: errorCode)
    }

    return try Self.parseResult(result)
  }

  /// Parses the linked list of DNS results (`addrinfo`), returning an array of socket addresses.
  private static func parseResult(
    _ result: UnsafeMutablePointer<addrinfo>
  ) throws -> [SocketAddress] {
    var result = result
    var socketAddresses = [SocketAddress]()

    while true {
      let addressBytes: UnsafeRawPointer = .init(result.pointee.ai_addr)

      switch result.pointee.ai_family {
      case AF_INET:  // IPv4 address
        let ipv4AddressStructure = addressBytes.load(as: sockaddr_in.self)
        try socketAddresses.append(.ipv4(.init(ipv4AddressStructure)))
      case AF_INET6:  // IPv6 address
        let ipv6AddressStructure = addressBytes.load(as: sockaddr_in6.self)
        try socketAddresses.append(.ipv6(.init(ipv6AddressStructure)))
      default:
        ()
      }

      guard let nextResult = result.pointee.ai_next else { break }
      result = nextResult
    }

    return socketAddresses
  }

  /// Converts an address from a network format to a presentation format using `inet_ntop`.
  fileprivate static func convertAddressFromNetworkToPresentationFormat<T>(
    addressPtr: UnsafePointer<T>,
    family: CInt,
    length: CInt
  ) throws -> String {
    var presentationAddressBytes = [CChar](repeating: 0, count: Int(length))

    return try presentationAddressBytes.withUnsafeMutableBufferPointer {
      (presentationAddressBytesPtr: inout UnsafeMutableBufferPointer<CChar>) throws -> String in

      // Convert
      let presentationAddressStringPtr = inet_ntop(
        family,
        addressPtr,
        presentationAddressBytesPtr.baseAddress!,
        socklen_t(length)
      )

      if let presentationAddressStringPtr {
        return String(cString: presentationAddressStringPtr)
      } else {
        throw DNSResolver.InetNetworkToPresentationError.systemError(errno: errno)
      }
    }
  }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension DNSResolver {
  /// `Error` that may be thrown based on the error code returned by `getaddrinfo`.
  package enum GetAddrInfoError: Error, Hashable {
    /// Address family for nodename not supported.
    case addressFamilyForNodenameNotSupported

    /// Temporary failure in name resolution.
    case temporaryFailure

    /// Invalid value for `ai_flags`.
    case invalidAIFlags

    /// Invalid value for `hints`.
    case invalidHints

    /// Non-recoverable failure in name resolution.
    case nonRecoverableFailure

    /// `ai_family` not supported.
    case aiFamilyNotSupported

    /// Memory allocation failure.
    case memoryAllocationFailure

    /// No address associated with nodename.
    case noAddressAssociatedWithNodename

    /// `hostname` or `servname` not provided, or not known.
    case hostnameOrServnameNotProvidedOrNotKnown

    /// Argument buffer overflow.
    case argumentBufferOverflow

    /// Resolved protocol is unknown.
    case resolvedProtocolIsUnknown

    /// `servname` not supported for `ai_socktype`.
    case servnameNotSupportedForSocktype

    /// `ai_socktype` not supported.
    case socktypeNotSupported

    /// System error returned in `errno`.
    case systemError

    /// Unknown error.
    case unknown

    package init(code: CInt) {
      switch code {
      case EAI_ADDRFAMILY:
        self = .addressFamilyForNodenameNotSupported
      case EAI_AGAIN:
        self = .temporaryFailure
      case EAI_BADFLAGS:
        self = .invalidAIFlags
      case EAI_BADHINTS:
        self = .invalidHints
      case EAI_FAIL:
        self = .nonRecoverableFailure
      case EAI_FAMILY:
        self = .aiFamilyNotSupported
      case EAI_MEMORY:
        self = .memoryAllocationFailure
      case EAI_NODATA:
        self = .noAddressAssociatedWithNodename
      case EAI_NONAME:
        self = .hostnameOrServnameNotProvidedOrNotKnown
      case EAI_OVERFLOW:
        self = .argumentBufferOverflow
      case EAI_PROTOCOL:
        self = .resolvedProtocolIsUnknown
      case EAI_SERVICE:
        self = .servnameNotSupportedForSocktype
      case EAI_SOCKTYPE:
        self = .socktypeNotSupported
      case EAI_SYSTEM:
        self = .systemError
      default:
        self = .unknown
      }
    }
  }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension DNSResolver {
  /// `Error` that may be thrown based on the system error encountered by `inet_ntop`.
  package enum InetNetworkToPresentationError: Error, Hashable {
    case systemError(errno: errno_t)
  }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension SocketAddress.IPv4 {
  fileprivate init(_ address: sockaddr_in) throws {
    var presentationAddress = ""

    try withUnsafePointer(to: address.sin_addr) { addressPtr in
      presentationAddress = try DNSResolver.convertAddressFromNetworkToPresentationFormat(
        addressPtr: addressPtr,
        family: AF_INET,
        length: INET_ADDRSTRLEN
      )
    }

    self = .init(host: presentationAddress, port: Int(in_port_t(bigEndian: address.sin_port)))
  }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension SocketAddress.IPv6 {
  fileprivate init(_ address: sockaddr_in6) throws {
    var presentationAddress = ""

    try withUnsafePointer(to: address.sin6_addr) { addressPtr in
      presentationAddress = try DNSResolver.convertAddressFromNetworkToPresentationFormat(
        addressPtr: addressPtr,
        family: AF_INET6,
        length: INET6_ADDRSTRLEN
      )
    }

    self = .init(host: presentationAddress, port: Int(in_port_t(bigEndian: address.sin6_port)))
  }
}
