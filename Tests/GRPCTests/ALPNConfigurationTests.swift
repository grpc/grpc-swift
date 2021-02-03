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
import GRPC
import NIOSSL
import XCTest

class ALPNConfigurationTests: GRPCTestCase {
  private func assertExpectedClientALPNTokens(in tokens: [String]) {
    XCTAssertEqual(tokens, ["grpc-exp", "h2"])
  }

  private func assertExpectedServerALPNTokens(in tokens: [String]) {
    XCTAssertEqual(tokens, ["grpc-exp", "h2", "http/1.1"])
  }

  func testClientDefaultALPN() {
    let config = ClientConnection.Configuration.TLS()
    self.assertExpectedClientALPNTokens(in: config.configuration.applicationProtocols)
  }

  func testClientAddsTokensFromEmptyNIOSSLConfig() {
    let tlsConfig = TLSConfiguration.forClient()
    XCTAssertTrue(tlsConfig.applicationProtocols.isEmpty)

    let config = ClientConnection.Configuration.TLS(configuration: tlsConfig)
    // Should now contain expected config.
    self.assertExpectedClientALPNTokens(in: config.configuration.applicationProtocols)
  }

  func testClientDoesNotOverrideNonEmptyNIOSSLConfig() {
    let tlsConfig = TLSConfiguration.forClient(applicationProtocols: ["foo"])

    let config = ClientConnection.Configuration.TLS(configuration: tlsConfig)
    // Should not be overridden.
    XCTAssertEqual(config.configuration.applicationProtocols, ["foo"])
  }

  func testServerDefaultALPN() {
    let config = Server.Configuration.TLS(certificateChain: [], privateKey: .file(""))
    self.assertExpectedServerALPNTokens(in: config.configuration.applicationProtocols)
  }

  func testServerAddsTokensFromEmptyNIOSSLConfig() {
    let tlsConfig = TLSConfiguration.forServer(certificateChain: [], privateKey: .file(""))
    XCTAssertTrue(tlsConfig.applicationProtocols.isEmpty)

    let config = Server.Configuration.TLS(configuration: tlsConfig)
    // Should now contain expected config.
    self.assertExpectedServerALPNTokens(in: config.configuration.applicationProtocols)
  }

  func testServerDoesNotOverrideNonEmptyNIOSSLConfig() {
    let tlsConfig = TLSConfiguration.forServer(
      certificateChain: [],
      privateKey: .file(""),
      applicationProtocols: ["foo"]
    )

    let config = ClientConnection.Configuration.TLS(configuration: tlsConfig)
    // Should not be overridden.
    XCTAssertEqual(config.configuration.applicationProtocols, ["foo"])
  }
}
