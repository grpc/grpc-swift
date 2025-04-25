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

import GRPC
import NIOConcurrencyHelpers
import NIOTransportServices
import XCTest

#if canImport(Network)
import Network
#endif

class ServerTests: GRPCTestCase {
  #if canImport(Network)
  func testParametersConfigurator() throws {
    let counter = NIOLockedValueBox(0)
    let serverEventLoopGroup = NIOTSEventLoopGroup()
    var serverConfiguration = Server.Configuration.default(
      target: .hostAndPort("localhost", 0),
      eventLoopGroup: serverEventLoopGroup,
      serviceProviders: []
    )
    serverConfiguration.nwParametersConfigurator = { _ in
      counter.withLockedValue { $0 += 1 }
    }

    let server = try Server.start(configuration: serverConfiguration).wait()
    XCTAssertEqual(1, counter.withLockedValue({ $0 }))

    try? server.close().wait()
  }
  #endif
}
