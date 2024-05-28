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
@_spi(Package) @testable import GRPCHTTP2Core
import NIOHTTP2
import NIOPosix
import XCTest

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class RoundRobinLoadBalancerTests: XCTestCase {
  func testMultipleConnectionsAreEstablished() async throws {
    try await LoadBalancerTest.roundRobin(servers: 3, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        // Update the addresses for the load balancer, this will trigger subchannels to be created
        // for each.
        let endpoints = context.servers.map { Endpoint(addresses: [$0.address]) }
        context.roundRobin!.updateAddresses(endpoints)

      case .connectivityStateChanged(.ready):
        // Poll until each server has one connected client.
        try await XCTPoll(every: .milliseconds(10)) {
          context.servers.allSatisfy { server, _ in server.clients.count == 1 }
        }

        // Close to end the test.
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

  func testSubchannelsArePickedEvenly() async throws {
    try await LoadBalancerTest.roundRobin(servers: 3, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        // Update the addresses for the load balancer, this will trigger subchannels to be created
        // for each.
        let endpoints = context.servers.map { Endpoint(addresses: [$0.address]) }
        context.roundRobin!.updateAddresses(endpoints)

      case .connectivityStateChanged(.ready):
        // Subchannel is ready. This happens when any subchannel becomes ready. Loop until
        // we can pick three distinct subchannels.
        try await XCTPoll(every: .milliseconds(10)) {
          var subchannelIDs = Set<SubchannelID>()
          for _ in 0 ..< 3 {
            let subchannel = try XCTUnwrap(context.loadBalancer.pickSubchannel())
            subchannelIDs.insert(subchannel.id)
          }
          return subchannelIDs.count == 3
        }

        // Now that all are ready, load should be distributed evenly among them.
        var counts = [SubchannelID: Int]()

        for round in 1 ... 10 {
          for _ in 1 ... 3 {
            if let subchannel = context.loadBalancer.pickSubchannel() {
              counts[subchannel.id, default: 0] += 1
            } else {
              XCTFail("Didn't pick subchannel from ready load balancer")
            }
          }

          XCTAssertEqual(counts.count, 3, "\(counts)")
          XCTAssert(counts.values.allSatisfy({ $0 == round }), "\(counts)")
        }

        // Close to finish the test.
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

  func testAddressUpdatesAreHandledGracefully() async throws {
    try await LoadBalancerTest.roundRobin(servers: 3, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        // Do the first connect.
        let endpoints = [Endpoint(addresses: [context.servers[0].address])]
        context.roundRobin!.updateAddresses(endpoints)

      case .connectivityStateChanged(.ready):
        // Now the first connection should be established.
        do {
          try await XCTPoll(every: .milliseconds(10)) {
            context.servers[0].server.clients.count == 1
          }
        }

        // First connection is okay, add a second.
        do {
          let endpoints = [
            Endpoint(addresses: [context.servers[0].address]),
            Endpoint(addresses: [context.servers[1].address]),
          ]
          context.roundRobin!.updateAddresses(endpoints)

          try await XCTPoll(every: .milliseconds(10)) {
            context.servers.prefix(2).allSatisfy { $0.server.clients.count == 1 }
          }
        }

        // Remove those two endpoints and add a third.
        do {
          let endpoints = [Endpoint(addresses: [context.servers[2].address])]
          context.roundRobin!.updateAddresses(endpoints)

          try await XCTPoll(every: .milliseconds(10)) {
            let disconnected = context.servers.prefix(2).allSatisfy { $0.server.clients.isEmpty }
            let connected = context.servers.last!.server.clients.count == 1
            return disconnected && connected
          }
        }

        context.loadBalancer.close()

      default:
        ()
      }
    } verifyEvents: { events in
      // Transitioning to new addresses should be graceful, i.e. a complete change shouldn't
      // result in dropping away from the ready state.
      let expected: [LoadBalancerEvent] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.shutdown),
      ]
      XCTAssertEqual(events, expected)
    }
  }

  func testSameAddressUpdatesAreIgnored() async throws {
    try await LoadBalancerTest.roundRobin(servers: 3, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        let endpoints = context.servers.map { _, address in Endpoint(addresses: [address]) }
        context.roundRobin!.updateAddresses(endpoints)

      case .connectivityStateChanged(.ready):
        // Update with the same addresses, these should be ignored.
        let endpoints = context.servers.map { _, address in Endpoint(addresses: [address]) }
        context.roundRobin!.updateAddresses(endpoints)

        // We should still have three connections.
        try await XCTPoll(every: .milliseconds(10)) {
          context.servers.allSatisfy { $0.server.clients.count == 1 }
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

  func testEmptyAddressUpdatesAreIgnored() async throws {
    try await LoadBalancerTest.roundRobin(servers: 3, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        let endpoints = context.servers.map { _, address in Endpoint(addresses: [address]) }
        context.roundRobin!.updateAddresses(endpoints)

      case .connectivityStateChanged(.ready):
        // Update with no-addresses, should be ignored so a subchannel can still be picked.
        context.roundRobin!.updateAddresses([])

        // We should still have three connections.
        try await XCTPoll(every: .milliseconds(10)) {
          context.servers.allSatisfy { $0.server.clients.count == 1 }
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

  func testSubchannelReceivesGoAway() async throws {
    try await LoadBalancerTest.roundRobin(servers: 3, connector: .posix()) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        // Trigger the connect.
        let endpoints = context.servers.map { Endpoint(addresses: [$0.address]) }
        context.roundRobin!.updateAddresses(endpoints)

      case .connectivityStateChanged(.ready):
        // Wait for all servers to become ready.
        try await XCTPoll(every: .milliseconds(10)) {
          context.servers.allSatisfy { $0.server.clients.count == 1 }
        }

        // The above only checks whether each server has a client, the test relies on all three
        // subchannels being ready, poll until we get three distinct IDs.
        var ids = Set<SubchannelID>()
        try await XCTPoll(every: .milliseconds(10)) {
          for _ in 1 ... 3 {
            if let subchannel = context.loadBalancer.pickSubchannel() {
              ids.insert(subchannel.id)
            }
          }
          return ids.count == 3
        }

        // Pick the first server and send a GOAWAY to the client.
        let client = context.servers[0].server.clients[0]
        let goAway = HTTP2Frame(
          streamID: .rootStream,
          payload: .goAway(lastStreamID: 0, errorCode: .cancel, opaqueData: nil)
        )

        // Send a GOAWAY, this should eventually close the subchannel and trigger a name
        // resolution.
        client.writeAndFlush(goAway, promise: nil)

      case .requiresNameResolution:
        // One subchannel should've been taken out, meaning we can only pick from the remaining two:
        let id1 = try XCTUnwrap(context.loadBalancer.pickSubchannel()?.id)
        let id2 = try XCTUnwrap(context.loadBalancer.pickSubchannel()?.id)
        let id3 = try XCTUnwrap(context.loadBalancer.pickSubchannel()?.id)
        XCTAssertNotEqual(id1, id2)
        XCTAssertEqual(id1, id3)

        // End the test.
        context.loadBalancer.close()

      default:
        ()
      }
    } verifyEvents: { events in
      let expected: [LoadBalancerEvent] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .requiresNameResolution,
        .connectivityStateChanged(.shutdown),
      ]
      XCTAssertEqual(events, expected)
    }
  }

  func testPickSubchannelWhenNotReady() {
    let loadBalancer = RoundRobinLoadBalancer(
      connector: .never,
      backoff: .defaults,
      defaultCompression: .none,
      enabledCompression: .none
    )

    XCTAssertNil(loadBalancer.pickSubchannel())
  }

  func testPickSubchannelWhenClosed() async {
    let loadBalancer = RoundRobinLoadBalancer(
      connector: .never,
      backoff: .defaults,
      defaultCompression: .none,
      enabledCompression: .none
    )

    loadBalancer.close()
    await loadBalancer.run()

    XCTAssertNil(loadBalancer.pickSubchannel())
  }

  func testPickOnIdleLoadBalancerTriggersConnect() async throws {
    let idle = ManagedAtomic(0)
    let ready = ManagedAtomic(0)

    try await LoadBalancerTest.roundRobin(
      servers: 1,
      connector: .posix(maxIdleTime: .milliseconds(25))  // Aggressively idle the connection
    ) { context, event in
      switch event {
      case .connectivityStateChanged(.idle):
        let idleCount = idle.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent)

        switch idleCount {
        case 1:
          // The first idle happens when the load balancer in started, give it a set of addresses
          // which it will connect to. Wait for it to be ready and then idle again.
          let address = context.servers[0].address
          let endpoints = [Endpoint(addresses: [address])]
          context.roundRobin!.updateAddresses(endpoints)

        case 2:
          // Load-balancer has the endpoints but all are idle. Picking will trigger a connect.
          XCTAssertNil(context.loadBalancer.pickSubchannel())

        case 3:
          // Connection idled again. Shut it down.
          context.loadBalancer.close()

        default:
          XCTFail("Became idle too many times")
        }

      case .connectivityStateChanged(.ready):
        let readyCount = ready.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent)

        if readyCount == 2 {
          XCTAssertNotNil(context.loadBalancer.pickSubchannel())
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
}
