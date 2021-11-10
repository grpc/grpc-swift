/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
#if canImport(NIOSSL)
#if canImport(Network)
import Dispatch
import EchoImplementation
import EchoModel
import GRPC
import Network
import NIOCore
import NIOPosix
import NIOSSL
import NIOTransportServices
import Security
import XCTest

@available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
final class GRPCNetworkFrameworkTests: GRPCTestCase {
  private var server: Server!
  private var client: ClientConnection!
  private var identity: SecIdentity!
  private var pkcs12Bundle: NIOSSLPKCS12Bundle!
  private var tsGroup: NIOTSEventLoopGroup!
  private var group: MultiThreadedEventLoopGroup!
  private let queue = DispatchQueue(label: "io.grpc.verify-handshake")

  private static let p12bundleURL = URL(fileURLWithPath: #file)
    .deletingLastPathComponent() // (this file)
    .deletingLastPathComponent() // GRPCTests
    .deletingLastPathComponent() // Tests
    .appendingPathComponent("Sources")
    .appendingPathComponent("GRPCSampleData")
    .appendingPathComponent("bundle")
    .appendingPathExtension("p12")

  override func setUp() {
    super.setUp()

    self.tsGroup = NIOTSEventLoopGroup(loopCount: 1)
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    self.identity = try? self.loadIdentity()
    XCTAssertNotNil(
      self.identity,
      "Unable to load identity from '\(GRPCNetworkFrameworkTests.p12bundleURL)'"
    )

    self.pkcs12Bundle = try? NIOSSLPKCS12Bundle(
      file: GRPCNetworkFrameworkTests.p12bundleURL.path,
      passphrase: "password".utf8
    )

    XCTAssertNotNil(
      self.pkcs12Bundle,
      "Unable to load PCKS12 bundle from '\(GRPCNetworkFrameworkTests.p12bundleURL)'"
    )
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.client.close().wait())
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    XCTAssertNoThrow(try self.tsGroup.syncShutdownGracefully())
    super.tearDown()
  }

  private func loadIdentity() throws -> SecIdentity? {
    let data = try Data(contentsOf: GRPCNetworkFrameworkTests.p12bundleURL)
    let options = [kSecImportExportPassphrase as String: "password"]

    var rawItems: CFArray?
    let status = SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems)

    guard status == errSecSuccess else {
      XCTFail("SecPKCS12Import failed with status \(status)")
      return nil
    }

    let items = rawItems! as! [[String: Any]]
    return items.first?[kSecImportItemIdentity as String] as! SecIdentity?
  }

  private func doEchoGet() throws {
    let echo = Echo_EchoClient(channel: self.client)
    let get = echo.get(.with { $0.text = "hello" })
    XCTAssertNoThrow(try get.response.wait())
  }

  private func startServer(_ builder: Server.Builder) throws {
    self.server = try builder
      .withServiceProviders([EchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "127.0.0.1", port: 0)
      .wait()
  }

  private func startClient(_ builder: ClientConnection.Builder) {
    self.client = builder
      .withBackgroundActivityLogger(self.clientLogger)
      .withConnectionReestablishment(enabled: false)
      .connect(host: "127.0.0.1", port: self.server.channel.localAddress!.port!)
  }

  func testNetworkFrameworkServerWithNIOSSLClient() throws {
    let serverBuilder = Server.usingTLSBackedByNetworkFramework(
      on: self.tsGroup,
      with: self.identity
    )
    XCTAssertNoThrow(try self.startServer(serverBuilder))

    let clientBuilder = ClientConnection.usingTLSBackedByNIOSSL(on: self.group)
      .withTLS(serverHostnameOverride: "localhost")
      .withTLS(trustRoots: .certificates(self.pkcs12Bundle.certificateChain))

    self.startClient(clientBuilder)

    XCTAssertNoThrow(try self.doEchoGet())
  }

  func testNIOSSLServerOnMTELGWithNetworkFrameworkClient() throws {
    try self.doTestNIOSSLServerWithNetworkFrameworkClient(serverGroup: self.group)
  }

  func testNIOSSLServerOnNIOTSGroupWithNetworkFrameworkClient() throws {
    try self.doTestNIOSSLServerWithNetworkFrameworkClient(serverGroup: self.tsGroup)
  }

  func doTestNIOSSLServerWithNetworkFrameworkClient(serverGroup: EventLoopGroup) throws {
    let serverBuilder = Server.usingTLSBackedByNIOSSL(
      on: serverGroup,
      certificateChain: self.pkcs12Bundle.certificateChain,
      privateKey: self.pkcs12Bundle.privateKey
    )
    XCTAssertNoThrow(try self.startServer(serverBuilder))

    var certificate: SecCertificate?
    guard SecIdentityCopyCertificate(self.identity, &certificate) == errSecSuccess else {
      XCTFail("Unable to extract certificate from identity")
      return
    }

    let clientBuilder = ClientConnection.usingTLSBackedByNetworkFramework(on: self.tsGroup)
      .withTLS(serverHostnameOverride: "localhost")
      .withTLSHandshakeVerificationCallback(on: self.queue) { _, trust, verify in
        let actualTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        SecTrustSetAnchorCertificates(actualTrust, [certificate!] as CFArray)
        SecTrustEvaluateAsyncWithError(actualTrust, self.queue) { _, valid, error in
          if let error = error {
            XCTFail("Trust evaluation error: \(error)")
          }
          verify(valid)
        }
      }

    self.startClient(clientBuilder)

    XCTAssertNoThrow(try self.doEchoGet())
  }

  func testNetworkFrameworkTLServerAndClient() throws {
    let serverBuilder = Server.usingTLSBackedByNetworkFramework(
      on: self.tsGroup,
      with: self.identity
    )
    XCTAssertNoThrow(try self.startServer(serverBuilder))

    var certificate: SecCertificate?
    guard SecIdentityCopyCertificate(self.identity, &certificate) == errSecSuccess else {
      XCTFail("Unable to extract certificate from identity")
      return
    }

    let clientBuilder = ClientConnection.usingTLSBackedByNetworkFramework(on: self.tsGroup)
      .withTLS(serverHostnameOverride: "localhost")
      .withTLSHandshakeVerificationCallback(on: self.queue) { _, trust, verify in
        let actualTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        SecTrustSetAnchorCertificates(actualTrust, [certificate!] as CFArray)
        SecTrustEvaluateAsyncWithError(actualTrust, self.queue) { _, valid, error in
          if let error = error {
            XCTFail("Trust evaluation error: \(error)")
          }
          verify(valid)
        }
      }

    self.startClient(clientBuilder)

    XCTAssertNoThrow(try self.doEchoGet())
  }
}

#endif // canImport(Network)
#endif // canImport(NIOSSL)
