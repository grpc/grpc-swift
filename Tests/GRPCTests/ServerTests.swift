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
import EchoModel
import EchoImplementation

#if canImport(Network)
import Network
#endif

class ServerTests: GRPCTestCase {
  #if canImport(Network)
  func testParametersConfigurators() throws {
    let listenerCounter = NIOLockedValueBox(0)
    let childChannelsCounter = NIOLockedValueBox(0)
    let group = NIOTSEventLoopGroup()
    defer {
      try? group.syncShutdownGracefully()
    }

    var serverConfiguration = Server.Configuration.default(
      target: .hostAndPort("localhost", 0),
      eventLoopGroup: group,
      serviceProviders: []
    )
    serverConfiguration.listenerNWParametersConfigurator = { _ in
      listenerCounter.withLockedValue { $0 += 1 }
    }
    serverConfiguration.childChannelNWParametersConfigurator = { _ in
      childChannelsCounter.withLockedValue { $0 += 1 }
    }

    let server = try Server.start(configuration: serverConfiguration).wait()
    defer {
      try? server.close().wait()
    }

    // The listener channel should be up and running after starting the server
    XCTAssertEqual(1, listenerCounter.withLockedValue({ $0 }))
    // However we don't have any child channels set up as there are no active connections
    XCTAssertEqual(0, childChannelsCounter.withLockedValue({ $0 }))

    // Start a client and execute a request so that a connection is established.
    let channel = try GRPCChannelPool.with(
      target: .hostAndPort("localhost", server.channel.localAddress!.port!),
      transportSecurity: .plaintext,
      eventLoopGroup: group
    )
    defer {
      try? channel.close().wait()
    }
    let echo = Echo_EchoNIOClient(channel: channel)
    _ = try echo.get(.with { $0.text = "" }).status.wait()

    // Now the configurator should have run.
    XCTAssertEqual(1, childChannelsCounter.withLockedValue({ $0 }))
  }
  #endif
}
