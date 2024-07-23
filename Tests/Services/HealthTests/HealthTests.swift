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

import GRPCHealth
import GRPCInProcessTransport
import XCTest

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class HealthTests: XCTestCase {
  private func withHealthClient(
    _ body: @Sendable (Grpc_Health_V1_HealthClient, HealthProvider) async throws -> Void
  ) async throws {
    let health = Health()
    let inProcess = InProcessTransport.makePair()
    let server = GRPCServer(transport: inProcess.server, services: [health.service])
    let client = GRPCClient(transport: inProcess.client)
    let healthClient = Grpc_Health_V1_HealthClient(client: client)

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await server.run()
      }

      group.addTask {
        try await client.run()
      }

      do {
        try await body(healthClient, health.provider)
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      group.cancelAll()
    }
  }

  func testCheckOnKnownService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor(package: "test.package", service: "TestService")

      try healthProvider.updateService(
        descriptor: testServiceDescriptor,
        status: .serving
      )

      try healthProvider.updateService(
        descriptor: ServiceDescriptor(package: "package.to.be.ignored", service: "IgnoredService"),
        status: .notServing
      )

      var message = Grpc_Health_V1_HealthCheckRequest()
      message.service = testServiceDescriptor.fullyQualifiedService

      try await healthClient.check(request: ClientRequest.Single(message: message)) { response in
        try XCTAssertEqual(response.message.status, .serving)
      }
    }
  }

  func testCheckOnUnknownService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      try healthProvider.updateService(
        descriptor: ServiceDescriptor(package: "package.to.be.ignored", service: "IgnoredService"),
        status: .notServing
      )

      var message = Grpc_Health_V1_HealthCheckRequest()
      message.service =
        ServiceDescriptor(package: "does.not", service: "Exist").fullyQualifiedService

      try await healthClient.check(request: ClientRequest.Single(message: message)) { response in
        try XCTAssertThrowsError(response.message) { error in
          XCTAssertTrue(error is RPCError)
          XCTAssertEqual((error as! RPCError).code, .notFound)
        }
      }
    }
  }

  func testWatchOnKnownService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor(package: "test.package", service: "TestService")
      let ignoredServiceDescriptor = ServiceDescriptor(
        package: "package.to.be.ignored",
        service: "IgnoredService"
      )

      let statuses: [ServingStatus] = [.serving, .notServing, .serving, .serving, .notServing]

      try healthProvider.updateService(
        descriptor: testServiceDescriptor,
        status: statuses[0]
      )

      try healthProvider.updateService(
        descriptor: ignoredServiceDescriptor,
        status: .notServing
      )

      var message = Grpc_Health_V1_HealthCheckRequest()
      message.service = testServiceDescriptor.fullyQualifiedService

      try await healthClient.watch(request: ClientRequest.Single(message: message)) { response in
        var responseStreamIterator = response.messages.makeAsyncIterator()

        for i in 0 ..< statuses.count {
          let next = try await responseStreamIterator.next()!
          let expectedStatus = Grpc_Health_V1_HealthCheckResponse.ServingStatus(from: statuses[i])

          XCTAssertEqual(next.status, expectedStatus)

          if i < statuses.count - 1 {
            try healthProvider.updateService(
              descriptor: testServiceDescriptor,
              status: statuses[i + 1]
            )

            try healthProvider.updateService(
              descriptor: ignoredServiceDescriptor,
              status: .notServing
            )
          }
        }
      }
    }
  }

  func testWatchOnUnknownService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      try healthProvider.updateService(
        descriptor: ServiceDescriptor(package: "package.to.be.ignored", service: "IgnoredService"),
        status: .serving
      )

      let testServiceDescriptor = ServiceDescriptor(package: "test.package", service: "TestService")

      var message = Grpc_Health_V1_HealthCheckRequest()
      message.service = testServiceDescriptor.fullyQualifiedService

      try await healthClient.watch(request: ClientRequest.Single(message: message)) { response in
        var responseStreamIterator = response.messages.makeAsyncIterator()
        var next = try await responseStreamIterator.next()!

        XCTAssertEqual(next.status, .serviceUnknown)

        try healthProvider.updateService(
          descriptor: testServiceDescriptor,
          status: .notServing
        )

        next = try await responseStreamIterator.next()!

        XCTAssertEqual(next.status, .notServing)
      }
    }
  }

  func testMultipleWatchOnTheSameService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor(package: "test.package", service: "TestService")

      let receivedStatuses1 = AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus>
        .makeStream()
      let receivedStatuses2 = AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus>
        .makeStream()

      let statusesToBeSent: [ServingStatus] = [
        .serving,
        .notServing,
        .serving,
        .serving,
        .notServing,
      ]

      @Sendable func runWatch(
        continuation: AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus>.Continuation
      ) async throws {
        var message = Grpc_Health_V1_HealthCheckRequest()
        message.service = testServiceDescriptor.fullyQualifiedService

        try await healthClient.watch(request: ClientRequest.Single(message: message)) { response in
          var responseStreamIterator = response.messages.makeAsyncIterator()

          // Since responseStreamIterator.next() will never be nil (as the "watch" response stream
          // is always open), the iteration cannot be based on when responseStreamIterator.next()
          // is nil. Else, the iteration infinitely awaits and the test never finishes. Hence, it is
          // based on the expected number of statuses to be received.
          for _ in 0 ..< statusesToBeSent.count {
            try await continuation.yield(responseStreamIterator.next()!.status)
          }
        }
      }

      try await withThrowingDiscardingTaskGroup { group in
        group.addTask {
          try await runWatch(continuation: receivedStatuses1.continuation)
        }

        group.addTask {
          try await runWatch(continuation: receivedStatuses2.continuation)
        }

        var iterator1 = receivedStatuses1.stream.makeAsyncIterator()
        var iterator2 = receivedStatuses2.stream.makeAsyncIterator()

        for status in statusesToBeSent {
          try healthProvider.updateService(
            descriptor: testServiceDescriptor,
            status: status
          )

          let sent = Grpc_Health_V1_HealthCheckResponse.ServingStatus(from: status)
          let received1 = await iterator1.next()
          let received2 = await iterator2.next()

          XCTAssertEqual(sent, received1)
          XCTAssertEqual(sent, received2)
        }
      }
    }
  }
}
