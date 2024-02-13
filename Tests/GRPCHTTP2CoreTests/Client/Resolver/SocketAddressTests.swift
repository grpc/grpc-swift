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

import GRPCHTTP2Core
import XCTest

final class SocketAddressTests: XCTestCase {
  func testSocketAddressUnwrapping() {
    var address: SocketAddress = .ipv4(host: "foo", port: 42)
    XCTAssertEqual(address.ipv4, SocketAddress.IPv4(host: "foo", port: 42))
    XCTAssertNil(address.ipv6)
    XCTAssertNil(address.unixDomainSocket)
    XCTAssertNil(address.virtualSocket)

    address = .ipv6(host: "bar", port: 42)
    XCTAssertEqual(address.ipv6, SocketAddress.IPv6(host: "bar", port: 42))
    XCTAssertNil(address.ipv4)
    XCTAssertNil(address.unixDomainSocket)
    XCTAssertNil(address.virtualSocket)

    address = .unixDomainSocket(path: "baz")
    XCTAssertEqual(address.unixDomainSocket, SocketAddress.UnixDomainSocket(path: "baz"))
    XCTAssertNil(address.ipv4)
    XCTAssertNil(address.ipv6)
    XCTAssertNil(address.virtualSocket)

    address = .vsock(contextID: .any, port: .any)
    XCTAssertEqual(address.virtualSocket, SocketAddress.VirtualSocket(contextID: .any, port: .any))
    XCTAssertNil(address.ipv4)
    XCTAssertNil(address.ipv6)
    XCTAssertNil(address.unixDomainSocket)
  }

  func testSocketAddressDescription() {
    var address: SocketAddress = .ipv4(host: "127.0.0.1", port: 42)
    XCTAssertDescription(address, "[ipv4]127.0.0.1:42")

    address = .ipv6(host: "::1", port: 42)
    XCTAssertDescription(address, "[ipv6]::1:42")

    address = .unixDomainSocket(path: "baz")
    XCTAssertDescription(address, "[unix]baz")

    address = .vsock(contextID: 314, port: 159)
    XCTAssertDescription(address, "[vsock]314:159")
    address = .vsock(contextID: .any, port: .any)
    XCTAssertDescription(address, "[vsock]-1:-1")

  }

  func testSocketAddressSubTypesDescription() {
    let ipv4 = SocketAddress.IPv4(host: "127.0.0.1", port: 42)
    XCTAssertDescription(ipv4, "[ipv4]127.0.0.1:42")

    let ipv6 = SocketAddress.IPv6(host: "foo", port: 42)
    XCTAssertDescription(ipv6, "[ipv6]foo:42")

    let uds = SocketAddress.UnixDomainSocket(path: "baz")
    XCTAssertDescription(uds, "[unix]baz")

    var vsock = SocketAddress.VirtualSocket(contextID: 314, port: 159)
    XCTAssertDescription(vsock, "[vsock]314:159")
    vsock.contextID = .any
    vsock.port = .any
    XCTAssertDescription(vsock, "[vsock]-1:-1")
  }
}
