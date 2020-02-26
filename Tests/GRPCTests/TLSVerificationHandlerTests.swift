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
import Foundation
@testable import GRPC
import NIO
import NIOSSL
import XCTest
import NIOTLS

class TLSVerificationHandlerTests: GRPCTestCase {
  func testTLSValidationSucceededWithUnspecifiedProtocol() {
    let expectation = self.expectation(description: "tls handshake success")
    let tlsVerificationHandler = TLSVerificationHandler(logger: self.logger)
    let handshakeEvent = TLSUserEvent.handshakeCompleted(negotiatedProtocol: nil)
    let channel = EmbeddedChannel(handler: tlsVerificationHandler)
    channel.pipeline.fireUserInboundEventTriggered(handshakeEvent)
    tlsVerificationHandler.verification.assertSuccess(fulfill: expectation)
    self.wait(for: [expectation], timeout: 1.0)
  }
  
  func testTLSValidationSucceededWithGRPCApplicationProtocols() {
    var expectations = [XCTestExpectation]()
    
    GRPCApplicationProtocolIdentifier.allCases.forEach {
      let exp = self.expectation(description: "tls \(String(describing:$0)) protocol success")
      expectations.append(exp)
      let tlsVerificationHandler = TLSVerificationHandler(logger: self.logger)
      let channel = EmbeddedChannel(handler: tlsVerificationHandler)
      let handshakeEvent = TLSUserEvent.handshakeCompleted(negotiatedProtocol: $0.rawValue)
      channel.pipeline.fireUserInboundEventTriggered(handshakeEvent)
      tlsVerificationHandler.verification.assertSuccess(fulfill: exp)
    }
    
    self.wait(for: expectations, timeout: 1.0)
  }
  
  func testTLSValidationSucceededWithCustomProtocol() {
    let expectation = self.expectation(description: "tls custom protocol success")
    let tlsVerificationHandler = TLSVerificationHandler(logger: self.logger)
    let handshakeEvent = TLSUserEvent.handshakeCompleted(negotiatedProtocol: "some-protocol")
    let channel = EmbeddedChannel(handler: tlsVerificationHandler)
    channel.pipeline.fireUserInboundEventTriggered(handshakeEvent)
    tlsVerificationHandler.verification.assertSuccess(fulfill: expectation)
    self.wait(for: [expectation], timeout: 1.0)
  }
}
