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

import Dispatch

#if canImport(Darwin)
import Darwin
#elseif os(Linux) || os(FreeBSD) || os(Android)
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import CNIOLinux
#else
#error("The GRPCHTTP2Core module was unable to identify your C library.")
#endif

/// An asynchronous non-blocking DNS resolver built on top of the libc `getaddrinfo` function.
@available(macOS 10.15, *)
package enum SimpleAsyncDNSResolver {
  private static let dispatchQueue = DispatchQueue(
    label: "io.grpc.SimpleAsyncDNSResolver.dispatchQueue"
  )

  /// Resolves a hostname  and port number to a list of IP addresses and port numbers.
  ///
  /// This method is non-blocking. As calls to `getaddrinfo` are blocking, this method executes `getaddrinfo` in a
  /// `DispatchQueue` and uses a `CheckedContinuation` to interface with the execution.
  package static func resolve(host: String, port: Int) async throws -> [SocketAddress] {
    if Task.isCancelled {
      return []
    }

    return try await withCheckedThrowingContinuation { continuation in
      dispatchQueue.async {
        do {
          let result = try Self.resolveBlocking(host: host, port: port)
          continuation.resume(returning: result)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Resolves a hostname and port number to a list of IP addresses and port numbers.
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

    guard errorCode == 0, var result else {
      throw SimpleAsyncDNSResolverError(code: errorCode)
    }

    var socketAddressList = [SocketAddress]()

    while true {
      let addressBytes = UnsafeRawPointer(result.pointee.ai_addr)
      let socketAddress: SocketAddress?

      switch result.pointee.ai_family {  // Enum with two cases
      case AF_INET:  // IPv4 address
        let ipv4NetworkAddressStructure = addressBytes!.load(as: sockaddr_in.self)
        let ipv4PresentationAddress = Self.convertFromNetworkToPresentationFormat(
          address: ipv4NetworkAddressStructure.sin_addr,
          family: AF_INET,
          length: INET_ADDRSTRLEN
        )

        socketAddress = .ipv4(
          .init(
            host: ipv4PresentationAddress,
            port: Int(in_port_t(bigEndian: ipv4NetworkAddressStructure.sin_port))
          )
        )
      case AF_INET6:  // IPv6 address
        let ipv6NetworkAddressStructure = addressBytes!.load(as: sockaddr_in6.self)
        let ipv6PresentationAddress = Self.convertFromNetworkToPresentationFormat(
          address: ipv6NetworkAddressStructure.sin6_addr,
          family: AF_INET6,
          length: INET6_ADDRSTRLEN
        )

        socketAddress = .ipv6(
          .init(
            host: ipv6PresentationAddress,
            port: Int(in_port_t(bigEndian: ipv6NetworkAddressStructure.sin6_port))
          )
        )
      default:
        socketAddress = nil
      }

      if let socketAddress {
        socketAddressList.append(socketAddress)
      }

      guard let nextResult = result.pointee.ai_next else { break }
      result = nextResult
    }

    return socketAddressList
  }

  /// Converts an address from a network format to a presentation format using `inet_ntop`.
  private static func convertFromNetworkToPresentationFormat<T>(
    address: T,
    family: Int32,
    length: Int32
  ) -> String {
    var resultingAddressBytes = [Int8](repeating: 0, count: Int(length))

    return withUnsafePointer(to: address) { addressPtr in
      return resultingAddressBytes.withUnsafeMutableBufferPointer {
        (resultingAddressBytesPtr: inout UnsafeMutableBufferPointer<Int8>) -> String in

        // Convert
        inet_ntop(family, addressPtr, resultingAddressBytesPtr.baseAddress!, socklen_t(length))

        // Create the result string from now-filled resultingAddressBytes.
        return resultingAddressBytesPtr.baseAddress!.withMemoryRebound(
          to: UInt8.self,
          capacity: Int(length)
        ) { resultingAddressBytesPtr -> String in
          String(cString: resultingAddressBytesPtr)
        }
      }
    }
  }
}

/// `Error` that may be thrown based on the error code returned by `getaddrinfo`.
package enum SimpleAsyncDNSResolverError: Error {
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

  package init(code: Int32) {
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
