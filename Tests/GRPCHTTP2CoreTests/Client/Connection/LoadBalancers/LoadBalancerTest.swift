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

@_spi(Package) @testable import GRPCHTTP2Core
import XCTest

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
enum LoadBalancerTest {
  struct Context {
    let servers: [(server: TestServer, address: GRPCHTTP2Core.SocketAddress)]
    let loadBalancer: LoadBalancer
  }

  static func roundRobin(
    servers serverCount: Int,
    connector: any HTTP2Connector,
    backoff: ConnectionBackoff = .defaults,
    timeout: Duration = .seconds(10),
    function: String = #function,
    handleEvent: @escaping @Sendable (Context, LoadBalancerEvent) async throws -> Void,
    verifyEvents: @escaping @Sendable ([LoadBalancerEvent]) -> Void = { _ in }
  ) async throws {
    try await Self.run(
      servers: serverCount,
      timeout: timeout,
      function: function,
      handleEvent: handleEvent,
      verifyEvents: verifyEvents
    ) {
      let roundRobin = RoundRobinLoadBalancer(
        connector: connector,
        backoff: backoff,
        defaultCompression: .none,
        enabledCompression: .none
      )
      return .roundRobin(roundRobin)
    }
  }

  private static func run(
    servers serverCount: Int,
    timeout: Duration,
    function: String,
    handleEvent: @escaping @Sendable (Context, LoadBalancerEvent) async throws -> Void,
    verifyEvents: @escaping @Sendable ([LoadBalancerEvent]) -> Void = { _ in },
    makeLoadBalancer: @escaping @Sendable () -> LoadBalancer
  ) async throws {
    enum TestEvent {
      case timedOut
      case completed(Result<Void, Error>)
    }

    try await withThrowingTaskGroup(of: TestEvent.self) { group in
      group.addTask {
        try? await Task.sleep(for: timeout)
        return .timedOut
      }

      group.addTask {
        do {
          try await Self._run(
            servers: serverCount,
            handleEvent: handleEvent,
            verifyEvents: verifyEvents,
            makeLoadBalancer: makeLoadBalancer
          )
          return .completed(.success(()))
        } catch {
          return .completed(.failure(error))
        }
      }

      let result = try await group.next()!
      group.cancelAll()

      switch result {
      case .timedOut:
        XCTFail("'\(function)' timed out after \(timeout)")
      case .completed(let result):
        try result.get()
      }
    }
  }

  private static func _run(
    servers serverCount: Int,
    handleEvent: @escaping @Sendable (Context, LoadBalancerEvent) async throws -> Void,
    verifyEvents: @escaping @Sendable ([LoadBalancerEvent]) -> Void,
    makeLoadBalancer: @escaping @Sendable () -> LoadBalancer
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      // Create the test servers.
      var servers = [(server: TestServer, address: GRPCHTTP2Core.SocketAddress)]()
      for _ in 0 ..< serverCount {
        let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
        let address = try await server.bind()
        servers.append((server, address))

        group.addTask {
          try await server.run { _, _ in
            XCTFail("Unexpected stream")
          }
        }
      }

      // Create the load balancer.
      let loadBalancer = makeLoadBalancer()

      group.addTask {
        await loadBalancer.run()
      }

      let context = Context(servers: servers, loadBalancer: loadBalancer)

      var events = [LoadBalancerEvent]()
      for await event in loadBalancer.events {
        events.append(event)
        try await handleEvent(context, event)
      }

      verifyEvents(events)
      group.cancelAll()
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension LoadBalancerTest.Context {
  var roundRobin: RoundRobinLoadBalancer? {
    switch self.loadBalancer {
    case .roundRobin(let loadBalancer):
      return loadBalancer
    }
  }
}
