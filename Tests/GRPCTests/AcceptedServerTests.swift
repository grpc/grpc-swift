/*
 * Copyright 2025, gRPC Authors All rights reserved.
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

import EchoImplementation
import EchoModel
import GRPC
import GRPCSampleData
import Logging
import NIOConcurrencyHelpers
import NIOPosix
import XCTest

#if canImport(Darwin)
import Darwin
private let sys_bind = Darwin.bind
private let sys_listen = Darwin.listen
private let sys_close = Darwin.close
private let sys_accept = Darwin.accept
private let sys_strerror = Darwin.strerror
#elseif canImport(Glibc)
import Glibc
private let sys_bind = Glibc.bind
private let sys_listen = Glibc.listen
private let sys_close = Glibc.close
private let sys_accept = Glibc.accept
private let sys_strerror = Glibc.strerror
#endif

final class AcceptedServerTests: GRPCTestCase {
  private func withListener<Result>(
    _ handle: (ListeningServer) throws -> Result
  ) throws -> Result {
    let server = try ListeningServer.bind(logger: self.logger)

    do {
      return try handle(server)
    } catch {
      server.close()
      throw error
    }
  }

  func testBasicCommunication() throws {
    try self.withListener { listener in
      let client = try GRPCChannelPool.with(
        target: .host(listener.host, port: listener.port),
        transportSecurity: .plaintext,
        eventLoopGroup: .singletonMultiThreadedEventLoopGroup.next()
      )
      defer {
        try? client.close().wait()
      }

      // Start an RPC to trigger a connect.
      let echo = Echo_EchoNIOClient(channel: client)
      let response = echo.get(.with { $0.text = "Hello!" })

      // Now accept a connection and start the server.
      let acceptedFD = try listener.accept()

      let server = try Server.insecure(group: .singletonMultiThreadedEventLoopGroup)
        .withLogger(self.serverLogger)
        .withServiceProviders([EchoProvider()])
        .fromAcceptedConnection(takingOwnershipOf: acceptedFD)
        .wait()

      defer { try? server.close().wait() }
      XCTAssertEqual(try response.response.wait().text, "Swift echo get: Hello!")
    }
  }

  #if canImport(NIOSSL)
  func testBasicCommunicationWithTLS() throws {
    try self.withListener { listener in
      let client = try GRPCChannelPool.with(
        target: .host(listener.host, port: listener.port),
        transportSecurity: .tls(
          .makeClientConfigurationBackedByNIOSSL(
            trustRoots: .certificates([SampleCertificate.ca.certificate]),
            hostnameOverride: "localhost"
          )
        ),
        eventLoopGroup: .singletonMultiThreadedEventLoopGroup.next()
      )
      defer {
        try? client.close().wait()
      }

      // Start an RPC to trigger a connect.
      let echo = Echo_EchoNIOClient(channel: client)
      let response = echo.get(.with { $0.text = "Hello!" })

      // Now accept a connection and start the server.
      let acceptedFD = try listener.accept()

      let server = try Server.usingTLSBackedByNIOSSL(
        on: .singletonMultiThreadedEventLoopGroup,
        certificateChain: [SampleCertificate.server.certificate],
        privateKey: SamplePrivateKey.server
      )
      .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
      .withLogger(self.serverLogger)
      .withServiceProviders([EchoProvider()])
      .fromAcceptedConnection(takingOwnershipOf: acceptedFD)
      .wait()

      defer { try? server.close().wait() }
      XCTAssertEqual(try response.response.wait().text, "Swift echo get: Hello!")
    }
  }
  #endif  // canImport(NIOSSL)

  func testGracefulShutdownOfServer() throws {
    try self.withListener { listener in
      let group = MultiThreadedEventLoopGroup.singleton

      let client = try GRPCChannelPool.with(
        target: .host(listener.host, port: listener.port),
        transportSecurity: .plaintext,
        eventLoopGroup: group.next()
      )
      defer {
        try? client.close().wait()
      }

      // Start an RPC to trigger a connect.
      let echo = Echo_EchoNIOClient(channel: client)

      let messages = NIOLockedValueBox<[String]>([])
      let update = echo.update { reply in
        messages.withLockedValue({ $0.append(reply.text) })
      }

      // Now accept a connection and start the server.
      let acceptedFD = try listener.accept()

      let server = try Server.insecure(group: group)
        .withLogger(self.serverLogger)
        .withServiceProviders([EchoProvider()])
        .fromAcceptedConnection(takingOwnershipOf: acceptedFD)
        .wait()
      defer { try? server.close().wait() }

      // Initial metadata indicates both peers know about the RPC
      XCTAssertNoThrow(try update.initialMetadata.wait())

      // Begin graceful shutdown; 'update' can complete, new RPCs should fail.
      let shutdown = server.initiateGracefulShutdown()

      // Start a new RPC, it should fail.
      let getResponse = echo.get(.with { $0.text = "Bye!" })
      XCTAssertThrowsError(try getResponse.response.wait())

      // Update should still work.
      update.sendMessage(.with { $0.text = "Hello!" }, promise: nil)
      update.sendEnd(promise: nil)
      XCTAssertEqual(try update.status.wait().code, .ok)
      XCTAssertEqual(messages.withLockedValue { $0 }, ["Swift echo update (0): Hello!"])

      XCTAssertNoThrow(try shutdown.wait())
    }
  }
}

struct ListeningServer {
  private var fd: Int32

  let port: Int
  var host: String { "127.0.0.1" }
  var logger: Logger

  private init(fd: Int32, port: Int, logger: Logger) {
    self.fd = fd
    self.port = port
    self.logger = logger
  }

  func accept() throws(SocketError) -> CInt {
    self.logger.debug("Accepting new client connection")
    let fd = try Self.acceptConnection(on: self.fd)
    self.logger.debug("Accepted new connection", metadata: ["fd": "\(fd)"])
    return fd
  }

  func close() {
    self.logger.debug("Closing listener socket")
    _ = sys_close(self.fd)
  }

  static func bind(logger: Logger) throws(SocketError) -> Self {
    let fd = try Self.makeListeningSocket()
    let port = try Self.getListeningPort(for: fd)
    let server = ListeningServer(fd: fd, port: port, logger: logger)
    logger.info(
      "Opened listening socket",
      metadata: ["addr": "\(server.host):\(server.port)", "fd": "\(fd)"]
    )
    return server
  }

  enum SocketError: Error {
    case creationFailed
    case bindFailed
    case listenFailed
    case acceptFailed(String)
    case getsocknameFailed
  }

  private static func makeListeningSocket() throws(SocketError) -> CInt {
    #if canImport(Darwin)
    let sockfd = socket(AF_INET, SOCK_STREAM, 0)
    #elseif canImport(Glibc)
    let sockfd = socket(AF_INET, CInt(SOCK_STREAM.rawValue), 0)
    #else
    fatalError("Unsupported libc")
    #endif
    if sockfd == -1 {
      throw .creationFailed
    }

    // Allow address reuse
    var yes = 1
    setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int>.size))

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

    let bindResult = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        sys_bind(sockfd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }

    if bindResult == -1 {
      _ = sys_close(sockfd)
      throw .bindFailed
    }

    if sys_listen(sockfd, 5) == -1 {
      _ = sys_close(sockfd)
      throw .listenFailed
    }

    return sockfd
  }

  private static func getListeningPort(
    for listener: CInt,
  ) throws(SocketError) -> Int {
    var address = sockaddr_in()
    var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)

    let getsocknameResult = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(listener, $0, &addressLength)
      }
    }

    if getsocknameResult == 0 {
      return Int(UInt16(bigEndian: address.sin_port))
    } else {
      _ = sys_close(listener)
      throw .getsocknameFailed
    }
  }

  private static func acceptConnection(
    on listener: CInt,
  ) throws(SocketError) -> CInt {
    var clientAddress = sockaddr_in()
    var clientAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)

    let clientSocket = withUnsafeMutablePointer(to: &clientAddress) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        sys_accept(listener, $0, &clientAddressLength)
      }
    }

    if clientSocket == -1 {
      throw .acceptFailed(String(cString: sys_strerror(errno)!))
    } else {
      return clientSocket
    }
  }
}
