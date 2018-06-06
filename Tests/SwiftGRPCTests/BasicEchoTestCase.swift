/*
 * Copyright 2018, gRPC Authors All rights reserved.
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
import Foundation
@testable import SwiftGRPC
import XCTest

extension Echo_EchoRequest {
  init(text: String) {
    self.text = text
  }
}

extension Echo_EchoResponse {
  init(text: String) {
    self.text = text
  }
}

class BasicEchoTestCase: XCTestCase {
  func makeProvider() -> Echo_EchoProvider { return EchoProvider() }

  enum Security {
    case secure(certificate: String, key: String)
    case root
    case none

    init(certificate: Data, key: Data) {
      let certString = String(data: certificate, encoding: .utf8)!
      let keyString = String(data: key, encoding: .utf8)!
      self = .secure(certificate: certString, key: keyString)
    }

    static var trusted: Security {
      return self.init(certificate: certificateForTests, key: keyForTests)
    }

    static var selfSigned: Security {
      return self.init(certificate: selfSignedCertificateForTests, key: selfSignedKeyForTests)
    }
  }

  var provider: Echo_EchoProvider!
  var server: Echo_EchoServer!
  var client: Echo_EchoServiceClient!
  
  var defaultTimeout: TimeInterval { return 1.0 }
  var security: Security { return .none }
  var address: String { return "localhost:5050" }

  override func setUp() {
    super.setUp()
    
    provider = makeProvider()

    switch security {
    case let .secure(certificate, key):
      server = Echo_EchoServer(address: address,
                               certificateString: certificate,
                               keyString: key,
                               provider: provider)
      server.start()
      client = Echo_EchoServiceClient(address: address, certificates: certificate, arguments: [.sslTargetNameOverride("example.com")])
      client.host = "example.com"
    case .root:
      server = Echo_EchoServer(address: address, provider: provider)
      server.start()
      client = Echo_EchoServiceClient(address: address, secure: true)
    case .none:
      server = Echo_EchoServer(address: address, provider: provider)
      server.start()
      client = Echo_EchoServiceClient(address: address, secure: false)
    }
    
    client.timeout = defaultTimeout
  }

  override func tearDown() {
    client = nil
    
    server.server.stop()
    server = nil
    
    super.tearDown()
  }
}
