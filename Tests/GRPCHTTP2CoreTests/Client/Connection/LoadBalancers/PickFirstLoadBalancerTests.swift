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

import Atomics
import GRPCCore
import GRPCHTTP2Core
import NIOHTTP2
import NIOPosix
import XCTest

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class PickFirstLoadBalancerTests: XCTestCase {
  func testPickFirstConnectsToServer() async throws {
    try await LoadBalancerTest.pickFirst(servers: 1, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        let endpoint = Endpoint(addresses: context.servers.map { $0.address })
        context.pickFirst!.updateEndpoint(endpoint)
      case .connectivityStateChanged(.ready):
        context.loadBalancer.close()
      default:
        ()
      }
    } verifyEvents: { events in
      let expected: [LoadBalancerEvent] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.shutdown),
      ]
      XCTAssertEqual(events, expected)
    }
  }

  func testPickSubchannelWhenNotReady() async throws {
    try await LoadBalancerTest.pickFirst(servers: 1, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        XCTAssertNil(context.loadBalancer.pickSubchannel())
        context.loadBalancer.close()
      case .connectivityStateChanged(.shutdown):
        XCTAssertNil(context.loadBalancer.pickSubchannel())
      default:
        ()
      }
    } verifyEvents: { events in
      let expected: [LoadBalancerEvent] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.shutdown),
      ]
      XCTAssertEqual(events, expected)
    }
  }

  func testPickSubchannelReturnsSameSubchannel() async throws {
    try await LoadBalancerTest.pickFirst(servers: 1, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        let endpoint = Endpoint(addresses: context.servers.map { $0.address })
        context.pickFirst!.updateEndpoint(endpoint)

      case .connectivityStateChanged(.ready):
        var ids = Set<SubchannelID>()
        for _ in 0 ..< 100 {
          let subchannel = try XCTUnwrap(context.loadBalancer.pickSubchannel())
          ids.insert(subchannel.id)
        }
        XCTAssertEqual(ids.count, 1)
        context.loadBalancer.close()

      default:
        ()
      }
    } verifyEvents: { events in
      let expected: [LoadBalancerEvent] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.shutdown),
      ]
      XCTAssertEqual(events, expected)
    }
  }

  func testEndpointUpdateHandledGracefully() async throws {
    try await LoadBalancerTest.pickFirst(servers: 2, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        let endpoint = Endpoint(addresses: [context.servers[0].address])
        context.pickFirst!.updateEndpoint(endpoint)

      case .connectivityStateChanged(.ready):
        // Must be connected to server-0.
        try await XCTPoll(every: .milliseconds(10)) {
          context.servers[0].server.clients.count == 1
        }

        // Update the endpoint so that it contains server-1.
        let endpoint = Endpoint(addresses: [context.servers[1].address])
        context.pickFirst!.updateEndpoint(endpoint)

        // Should remain in the ready state
        try await XCTPoll(every: .milliseconds(10)) {
          context.servers[0].server.clients.isEmpty && context.servers[1].server.clients.count == 1
        }

        context.loadBalancer.close()

      default:
        ()
      }
    } verifyEvents: { events in
      let expected: [LoadBalancerEvent] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.shutdown),
      ]
      XCTAssertEqual(events, expected)
    }
  }

  func testSameEndpointUpdateIsIgnored() async throws {
    try await LoadBalancerTest.pickFirst(servers: 1, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        let endpoint = Endpoint(addresses: context.servers.map { $0.address })
        context.pickFirst!.updateEndpoint(endpoint)

      case .connectivityStateChanged(.ready):
        // Must be connected to server-0.
        try await XCTPoll(every: .milliseconds(10)) {
          context.servers[0].server.clients.count == 1
        }

        // Update the endpoint. This should be a no-op, server should remain connected.
        let endpoint = Endpoint(addresses: context.servers.map { $0.address })
        context.pickFirst!.updateEndpoint(endpoint)
        try await XCTPoll(every: .milliseconds(10)) {
          context.servers[0].server.clients.count == 1
        }

        context.loadBalancer.close()

      default:
        ()
      }
    } verifyEvents: { events in
      let expected: [LoadBalancerEvent] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.shutdown),
      ]
      XCTAssertEqual(events, expected)
    }
  }

  func testEmptyEndpointUpdateIsIgnored() async throws {
    // Checks that an update using the empty endpoint is ignored.
    try await LoadBalancerTest.pickFirst(servers: 0, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        let endpoint = Endpoint(addresses: [])
        // Should no-op.
        context.pickFirst!.updateEndpoint(endpoint)
        context.loadBalancer.close()

      default:
        ()
      }
    } verifyEvents: { events in
      let expected: [LoadBalancerEvent] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.shutdown),
      ]
      XCTAssertEqual(events, expected)
    }
  }

  func testPickOnIdleTriggersConnect() async throws {
    // Tests that picking a subchannel when the load balancer is idle triggers a reconnect and
    // becomes ready again. Uses a very short idle time to re-enter the idle state.
    let idle = ManagedAtomic(0)

    try await LoadBalancerTest.pickFirst(
      servers: 1,
      connector: .posix(maxIdleTime: .milliseconds(1))  // Aggressively idle the connection
    ) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        let idleCount = idle.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent)

        switch idleCount {
        case 1:
          // The first idle happens when the load balancer in started, give it an endpoint
          // which it will connect to. Wait for it to be ready and then idle again.
          let endpoint = Endpoint(addresses: context.servers.map { $0.address })
          context.pickFirst!.updateEndpoint(endpoint)
        case 2:
          // Load-balancer has the endpoints but all are idle. Picking will trigger a connect.
          XCTAssertNil(context.loadBalancer.pickSubchannel())
        case 3:
          // Connection idled again. Shut it down.
          context.loadBalancer.close()

        default:
          XCTFail("Became idle too many times")
        }

      default:
        ()
      }
    } verifyEvents: { events in
      let expected: [LoadBalancerEvent] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.shutdown),
      ]
      XCTAssertEqual(events, expected)
    }
  }

  func testPickFirstConnectionDropReturnsToIdle() async throws {
    // Checks that when the load balancers connection is unexpectedly dropped when there are no
    // open streams that it returns to the idle state.
    let idleCount = ManagedAtomic(0)

    try await LoadBalancerTest.pickFirst(servers: 1, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        switch idleCount.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent) {
        case 1:
          let endpoint = Endpoint(addresses: context.servers.map { $0.address })
          context.pickFirst!.updateEndpoint(endpoint)
        case 2:
          context.loadBalancer.close()
        default:
          ()
        }

      case .connectivityStateChanged(.ready):
        // Drop the connection.
        context.servers[0].server.clients[0].close(mode: .all, promise: nil)

      default:
        ()
      }
    } verifyEvents: { events in
      let expected: [LoadBalancerEvent] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.shutdown),
      ]
      XCTAssertEqual(events, expected)
    }
  }

  func testPickFirstReceivesGoAway() async throws {
    let idleCount = ManagedAtomic(0)
    try await LoadBalancerTest.pickFirst(servers: 2, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        switch idleCount.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent) {
        case 1:
          // Provide the address of the first server.
          context.pickFirst!.updateEndpoint(Endpoint(context.servers[0].address))
        case 2:
          // Provide the address of the second server.
          context.pickFirst!.updateEndpoint(Endpoint(context.servers[1].address))
        default:
          ()
        }

      case .connectivityStateChanged(.ready):
        switch idleCount.load(ordering: .sequentiallyConsistent) {
        case 1:
          // Must be connected to server 1, send a GOAWAY frame.
          let channel = context.servers[0].server.clients.first!
          let goAway = HTTP2Frame(
            streamID: .rootStream,
            payload: .goAway(lastStreamID: 0, errorCode: .noError, opaqueData: nil)
          )
          channel.writeAndFlush(goAway, promise: nil)

        case 2:
          // Must only be connected to server 2 now.
          XCTAssertEqual(context.servers[0].server.clients.count, 0)
          XCTAssertEqual(context.servers[1].server.clients.count, 1)
          context.loadBalancer.close()

        default:
          ()
        }

      default:
        ()
      }
    } verifyEvents: { events in
      let expected: [LoadBalancerEvent] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .requiresNameResolution,
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.shutdown),
      ]
      XCTAssertEqual(events, expected)
    }
  }
}
