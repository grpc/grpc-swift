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

import GRPCCore
@_spi(Package) @testable import GRPCHTTP2Core
import NIOHTTP2
import NIOPosix
import XCTest

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class GRPCChannelTests: XCTestCase {
  func testDefaultServiceConfig() throws {
    var serviceConfig = ServiceConfig()
    serviceConfig.loadBalancingConfig = [.roundRobin]
    serviceConfig.methodConfig = [MethodConfig(names: [MethodConfig.Name(.echoGet)])]
    serviceConfig.retryThrottling = try ServiceConfig.RetryThrottling(
      maxTokens: 100,
      tokenRatio: 0.1
    )

    let channel = GRPCChannel(
      resolver: .static(endpoints: []),
      connector: .never,
      config: .defaults,
      defaultServiceConfig: serviceConfig
    )

    XCTAssertNotNil(channel.configuration(forMethod: .echoGet))
    XCTAssertNil(channel.configuration(forMethod: .echoUpdate))

    let throttle = try XCTUnwrap(channel.retryThrottle)
    XCTAssertEqual(throttle.maximumTokens, 100)
    XCTAssertEqual(throttle.tokenRatio, 0.1)
  }

  func testServiceConfigFromResolver() async throws {
    // Verify that service config from the resolver takes precedence over the default service
    // config. This is done indirectly by checking method config and retry throttle config.

    // Create a service config to provide via the resolver.
    var serviceConfig = ServiceConfig()
    serviceConfig.loadBalancingConfig = [.roundRobin]
    serviceConfig.methodConfig = [MethodConfig(names: [MethodConfig.Name(.echoGet)])]
    serviceConfig.retryThrottling = try ServiceConfig.RetryThrottling(
      maxTokens: 100,
      tokenRatio: 0.1
    )

    // Need a server to connect to, no RPCs will be created though.
    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address = try await server.bind()

    let channel = GRPCChannel(
      resolver: .static(endpoints: [Endpoint(addresses: [address])], serviceConfig: serviceConfig),
      connector: .posix(),
      config: .defaults,
      defaultServiceConfig: ServiceConfig()
    )

    // Not resolved yet so the default (empty) service config is used.
    XCTAssertNil(channel.configuration(forMethod: .echoGet))
    XCTAssertNil(channel.configuration(forMethod: .echoUpdate))
    XCTAssertNil(channel.retryThrottle)

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await server.run(.never)
      }

      group.addTask {
        await channel.connect()
      }

      for await event in channel.connectivityState {
        switch event {
        case .ready:
          // When the channel is ready it must have the service config from the resolver.
          XCTAssertNotNil(channel.configuration(forMethod: .echoGet))
          XCTAssertNil(channel.configuration(forMethod: .echoUpdate))

          let throttle = try XCTUnwrap(channel.retryThrottle)
          XCTAssertEqual(throttle.maximumTokens, 100)
          XCTAssertEqual(throttle.tokenRatio, 0.1)

          // Now close.
          channel.close()

        default:
          ()
        }
      }

      group.cancelAll()
    }
  }

  func testServiceConfigFromResolverAfterUpdate() async throws {
    // Verify that the channel uses service config from the resolver and that it uses the latest
    // version provided by the resolver. This is done indirectly by checking method config and retry
    // throttle config.

    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address = try await server.bind()

    let (resolver, continuation) = NameResolver.dynamic(updateMode: .push)
    let channel = GRPCChannel(
      resolver: resolver,
      connector: .posix(),
      config: .defaults,
      defaultServiceConfig: ServiceConfig()
    )

    // Not resolved yet so the default (empty) service config is used.
    XCTAssertNil(channel.configuration(forMethod: .echoGet))
    XCTAssertNil(channel.configuration(forMethod: .echoUpdate))
    XCTAssertNil(channel.retryThrottle)

    // Yield the first address list and service config.
    var serviceConfig = ServiceConfig()
    serviceConfig.loadBalancingConfig = [.roundRobin]
    serviceConfig.methodConfig = [MethodConfig(names: [MethodConfig.Name(.echoGet)])]
    serviceConfig.retryThrottling = try ServiceConfig.RetryThrottling(
      maxTokens: 100,
      tokenRatio: 0.1
    )
    let resolutionResult = NameResolutionResult(
      endpoints: [Endpoint(address)],
      serviceConfig: .success(serviceConfig)
    )
    continuation.yield(resolutionResult)

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await server.run(.never)
      }

      group.addTask {
        await channel.connect()
      }

      for await event in channel.connectivityState {
        switch event {
        case .ready:
          // When the channel it must have the service config from the resolver.
          XCTAssertNotNil(channel.configuration(forMethod: .echoGet))
          XCTAssertNil(channel.configuration(forMethod: .echoUpdate))
          let throttle = try XCTUnwrap(channel.retryThrottle)
          XCTAssertEqual(throttle.maximumTokens, 100)
          XCTAssertEqual(throttle.tokenRatio, 0.1)

          // Now yield a new service config with the same addresses.
          var resolutionResult = resolutionResult
          serviceConfig.methodConfig = [MethodConfig(names: [MethodConfig.Name(.echoUpdate)])]
          serviceConfig.retryThrottling = nil
          resolutionResult.serviceConfig = .success(serviceConfig)
          continuation.yield(resolutionResult)

          // This should be propagated quickly.
          try await XCTPoll(every: .milliseconds(10)) {
            let noConfigForGet = channel.configuration(forMethod: .echoGet) == nil
            let configForUpdate = channel.configuration(forMethod: .echoUpdate) != nil
            let noThrottle = channel.retryThrottle == nil
            return noConfigForGet && configForUpdate && noThrottle
          }

          channel.close()

        default:
          ()
        }
      }

      group.cancelAll()
    }
  }

  func testPushBasedResolutionUpdates() async throws {
    // Verify that the channel responds to name resolution changes which are pushed into
    // the resolver. Do this by starting two servers and only making the address of one available
    // via the resolver at a time. Server identity is provided via metadata in the RPC.

    // Start a few servers.
    let server1 = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address1 = try await server1.bind()

    let server2 = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address2 = try await server2.bind()

    // Setup a resolver and push some changes into it.
    let (resolver, continuation) = NameResolver.dynamic(updateMode: .push)
    let resolution1 = NameResolutionResult(endpoints: [Endpoint(address1)], serviceConfig: nil)
    continuation.yield(resolution1)

    var serviceConfig = ServiceConfig()
    serviceConfig.loadBalancingConfig = [.roundRobin]
    let channel = GRPCChannel(
      resolver: resolver,
      connector: .posix(),
      config: .defaults,
      defaultServiceConfig: serviceConfig
    )

    try await withThrowingDiscardingTaskGroup { group in
      // Servers respond with their own address in the trailing metadata.
      for (server, address) in [(server1, address1), (server2, address2)] {
        group.addTask {
          try await server.run { inbound, outbound in
            let status = Status(code: .ok, message: "")
            let metadata: Metadata = ["server-addr": "\(address)"]
            try await outbound.write(.status(status, metadata))
            outbound.finish()
          }
        }
      }

      group.addTask {
        await channel.connect()
      }

      // The stream will be queued until the channel is ready.
      let serverAddress1 = try await channel.serverAddress()
      XCTAssertEqual(serverAddress1, "\(address1)")
      XCTAssertEqual(server1.clients.count, 1)
      XCTAssertEqual(server2.clients.count, 0)

      // Yield the second address. Because this happens asynchronously there's no guarantee that
      // the next stream will be made against the same server, so poll until the servers have the
      // appropriate connections.
      let resolution2 = NameResolutionResult(endpoints: [Endpoint(address2)], serviceConfig: nil)
      continuation.yield(resolution2)

      try await XCTPoll(every: .milliseconds(10)) {
        server1.clients.count == 0 && server2.clients.count == 1
      }

      let serverAddress2 = try await channel.serverAddress()
      XCTAssertEqual(serverAddress2, "\(address2)")

      group.cancelAll()
    }
  }

  func testPullBasedResolutionUpdates() async throws {
    // Verify that the channel responds to name resolution changes which are pulled because a
    // subchannel asked the channel to re-resolve. Do this by starting two servers and changing
    // which is available via resolution updates. Server identity is provided via metadata in
    // the RPC.

    // Start a few servers.
    let server1 = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address1 = try await server1.bind()

    let server2 = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address2 = try await server2.bind()

    // Setup a resolve which we push changes into.
    let (resolver, continuation) = NameResolver.dynamic(updateMode: .pull)

    // Yield the addresses.
    for address in [address1, address2] {
      let resolution = NameResolutionResult(endpoints: [Endpoint(address)], serviceConfig: nil)
      continuation.yield(resolution)
    }

    var serviceConfig = ServiceConfig()
    serviceConfig.loadBalancingConfig = [.roundRobin]
    let channel = GRPCChannel(
      resolver: resolver,
      connector: .posix(),
      config: .defaults,
      defaultServiceConfig: serviceConfig
    )

    try await withThrowingDiscardingTaskGroup { group in
      // Servers respond with their own address in the trailing metadata.
      for (server, address) in [(server1, address1), (server2, address2)] {
        group.addTask {
          try await server.run { inbound, outbound in
            let status = Status(code: .ok, message: "")
            let metadata: Metadata = ["server-addr": "\(address)"]
            try await outbound.write(.status(status, metadata))
            outbound.finish()
          }
        }
      }

      group.addTask {
        await channel.connect()
      }

      // The stream will be queued until the channel is ready.
      let serverAddress1 = try await channel.serverAddress()
      XCTAssertEqual(serverAddress1, "\(address1)")
      XCTAssertEqual(server1.clients.count, 1)
      XCTAssertEqual(server2.clients.count, 0)

      // Tell the first server to GOAWAY. This will cause the subchannel to re-resolve.
      let server1Client = try XCTUnwrap(server1.clients.first)
      let goAway = HTTP2Frame(
        streamID: .rootStream,
        payload: .goAway(lastStreamID: 1, errorCode: .noError, opaqueData: nil)
      )
      try await server1Client.writeAndFlush(goAway)

      // Poll until the first client drops, addresses are re-resolved, and a connection is
      // established to server2.
      try await XCTPoll(every: .milliseconds(10)) {
        server1.clients.count == 0 && server2.clients.count == 1
      }

      let serverAddress2 = try await channel.serverAddress()
      XCTAssertEqual(serverAddress2, "\(address2)")

      group.cancelAll()
    }
  }

  func testCloseWhenRPCsAreInProgress() async throws {
    // Verify that closing the channel while there are RPCs in progress allows the RPCs to finish
    // gracefully.

    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address = try await server.bind()

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await server.run(.echo)
      }

      var serviceConfig = ServiceConfig()
      serviceConfig.loadBalancingConfig = [.roundRobin]

      let channel = GRPCChannel(
        resolver: .static(endpoints: [Endpoint(address)]),
        connector: .posix(),
        config: .defaults,
        defaultServiceConfig: serviceConfig
      )

      group.addTask {
        await channel.connect()
      }

      try await channel.withStream(descriptor: .echoGet, options: .defaults) { stream in
        try await stream.outbound.write(.metadata([:]))

        var iterator = stream.inbound.makeAsyncIterator()
        let part1 = try await iterator.next()
        switch part1 {
        case .metadata:
          // Got metadata, close the channel.
          channel.close()
        case .message, .status, .none:
          XCTFail("Expected metadata, got \(String(describing: part1))")
        }

        for await state in channel.connectivityState {
          switch state {
          case .shutdown:
            // Happens when shutting-down has been initiated, so finish the RPC.
            stream.outbound.finish()

            let part2 = try await iterator.next()
            switch part2 {
            case .status(let status, _):
              XCTAssertEqual(status.code, .ok)
            case .metadata, .message, .none:
              XCTFail("Expected status, got \(String(describing: part2))")
            }

          default:
            ()
          }
        }
      }

      group.cancelAll()
    }
  }

  func testQueueRequestsWhileNotReady() async throws {
    // Verify that requests are queued until the channel becomes ready. As creating streams
    // will race with the channel becoming ready, we add numerous tasks to the task group which
    // each create a stream before making the server address known to the channel via the resolver.
    // This isn't perfect as the resolution _could_ happen before attempting to create all streams
    // although this is unlikely.

    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address = try await server.bind()

    let (resolver, continuation) = NameResolver.dynamic(updateMode: .push)
    var serviceConfig = ServiceConfig()
    serviceConfig.loadBalancingConfig = [.roundRobin]
    let channel = GRPCChannel(
      resolver: resolver,
      connector: .posix(),
      config: .defaults,
      defaultServiceConfig: serviceConfig
    )

    enum Subtask { case rpc, other }
    try await withThrowingTaskGroup(of: Subtask.self) { group in
      // Run the server.
      group.addTask {
        try await server.run { inbound, outbound in
          for try await part in inbound {
            switch part {
            case .metadata:
              try await outbound.write(.metadata([:]))
            case .message(let bytes):
              try await outbound.write(.message(bytes))
            }
          }

          let status = Status(code: .ok, message: "")
          try await outbound.write(.status(status, [:]))
          outbound.finish()
        }

        return .other
      }

      group.addTask {
        await channel.connect()
        return .other
      }

      // Start a bunch of requests. These won't start until an address is yielded, they should
      // be queued though.
      for _ in 1 ... 100 {
        group.addTask {
          try await channel.withStream(descriptor: .echoGet, options: .defaults) { stream in
            try await stream.outbound.write(.metadata([:]))
            stream.outbound.finish()

            for try await part in stream.inbound {
              switch part {
              case .metadata, .message:
                ()
              case .status(let status, _):
                XCTAssertEqual(status.code, .ok)
              }
            }
          }

          return .rpc
        }
      }

      // At least some of the RPCs should have been queued by now.
      let resolution = NameResolutionResult(endpoints: [Endpoint(address)], serviceConfig: nil)
      continuation.yield(resolution)

      var outstandingRPCs = 100
      for try await subtask in group {
        switch subtask {
        case .rpc:
          outstandingRPCs -= 1

          // All RPCs done, close the channel and cancel the group to stop the server.
          if outstandingRPCs == 0 {
            channel.close()
            group.cancelAll()
          }

        case .other:
          ()
        }
      }
    }
  }

  func testQueueRequestsFailFast() async throws {
    // Verifies that if 'waitsForReady' is 'false', that queued requests are failed when there is
    // a transient failure. The transient failure is triggered by attempting to connect to a
    // non-existent server.

    let (resolver, continuation) = NameResolver.dynamic(updateMode: .push)
    var serviceConfig = ServiceConfig()
    serviceConfig.loadBalancingConfig = [.roundRobin]
    let channel = GRPCChannel(
      resolver: resolver,
      connector: .posix(),
      config: .defaults,
      defaultServiceConfig: serviceConfig
    )

    enum Subtask { case rpc, other }
    try await withThrowingTaskGroup(of: Subtask.self) { group in
      group.addTask {
        await channel.connect()
        return .other
      }

      for _ in 1 ... 100 {
        group.addTask {
          var options = CallOptions.defaults
          options.waitForReady = false

          await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
            try await channel.withStream(descriptor: .echoGet, options: options) { _ in
              XCTFail("Unexpected stream")
            }
          } errorHandler: { error in
            XCTAssertEqual(error.code, .unavailable)
          }

          return .rpc
        }
      }

      // At least some of the RPCs should have been queued by now.
      let resolution = NameResolutionResult(
        endpoints: [Endpoint(.unixDomainSocket(path: "/test-queue-requests-fail-fast"))],
        serviceConfig: nil
      )
      continuation.yield(resolution)

      var outstandingRPCs = 100
      for try await subtask in group {
        switch subtask {
        case .rpc:
          outstandingRPCs -= 1

          // All RPCs done, close the channel and cancel the group to stop the server.
          if outstandingRPCs == 0 {
            channel.close()
            group.cancelAll()
          }

        case .other:
          ()
        }
      }
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension GRPCChannel.Config {
  static var defaults: Self {
    Self(
      http2: .defaults,
      backoff: .defaults,
      connection: .defaults,
      compression: .defaults
    )
  }
}

extension Endpoint {
  init(_ addresses: SocketAddress...) {
    self.init(addresses: addresses)
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension GRPCChannel {
  fileprivate func serverAddress() async throws -> String? {
    let values: Metadata.StringValues? = try await self.withStream(
      descriptor: .echoGet,
      options: .defaults
    ) { stream in
      try await stream.outbound.write(.metadata([:]))
      stream.outbound.finish()

      for try await part in stream.inbound {
        switch part {
        case .metadata, .message:
          XCTFail("Unexpected part: \(part)")
        case .status(_, let metadata):
          return metadata[stringValues: "server-addr"]
        }
      }
      return nil
    }

    return values?.first(where: { _ in true })
  }
}
