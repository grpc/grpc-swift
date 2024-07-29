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
    _ body: @Sendable (Grpc_Health_V1_HealthClient, Health.Provider) async throws -> Void
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
      let testServiceDescriptor = ServiceDescriptor.testService

      healthProvider.updateStatus(.serving, ofService: testServiceDescriptor)

      var message = Grpc_Health_V1_HealthCheckRequest()
      message.service = testServiceDescriptor.fullyQualifiedService

      try await healthClient.check(request: ClientRequest.Single(message: message)) { response in
        try XCTAssertEqual(response.message.status, .serving)
      }
    }
  }

  func testCheckOnUnknownService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      var message = Grpc_Health_V1_HealthCheckRequest()
      message.service =
        ServiceDescriptor(package: "does.not", service: "Exist")
        .fullyQualifiedService

      try await healthClient.check(request: ClientRequest.Single(message: message)) { response in
        try XCTAssertThrowsError(ofType: RPCError.self, response.message) { error in
          XCTAssertEqual(error.code, .notFound)
        }
      }
    }
  }

  func testCheckOnServer() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      healthProvider.updateStatus(.notServing, ofService: ServiceDescriptor.server)

      let message = Grpc_Health_V1_HealthCheckRequest()

      try await healthClient.check(request: ClientRequest.Single(message: message)) { response in
        try XCTAssertEqual(response.message.status, .notServing)
      }
    }
  }

  func testWatchOnKnownService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor.testService

      let statusesToBeSent: [ServingStatus] = [.serving, .notServing, .serving]

      healthProvider.updateStatus(statusesToBeSent[0], ofService: testServiceDescriptor)

      var message = Grpc_Health_V1_HealthCheckRequest()
      message.service = testServiceDescriptor.fullyQualifiedService

      try await healthClient.watch(request: ClientRequest.Single(message: message)) { response in
        var responseStreamIterator = response.messages.makeAsyncIterator()

        for i in 0 ..< statusesToBeSent.count {
          let next = try await responseStreamIterator.next()
          let message = try XCTUnwrap(next)
          let expectedStatus = Grpc_Health_V1_HealthCheckResponse.ServingStatus(statusesToBeSent[i])

          XCTAssertEqual(message.status, expectedStatus)

          if i < statusesToBeSent.count - 1 {
            healthProvider.updateStatus(statusesToBeSent[i + 1], ofService: testServiceDescriptor)
          }
        }
      }
    }
  }

  func testWatchOnUnknownServiceDoesNotTerminateTheRPC() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor.testService

      var message = Grpc_Health_V1_HealthCheckRequest()
      message.service = testServiceDescriptor.fullyQualifiedService

      try await healthClient.watch(request: ClientRequest.Single(message: message)) { response in
        var responseStreamIterator = response.messages.makeAsyncIterator()
        var next = try await responseStreamIterator.next()
        var message = try XCTUnwrap(next)

        XCTAssertEqual(message.status, .serviceUnknown)

        healthProvider.updateStatus(.notServing, ofService: testServiceDescriptor)

        next = try await responseStreamIterator.next()
        message = try XCTUnwrap(next)

        // The RPC was not terminated and a status update was received successfully.
        XCTAssertEqual(message.status, .notServing)
      }
    }
  }

  func testMultipleWatchOnTheSameService() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor.testService

      let statusesToBeSent: [ServingStatus] = [.serving, .notServing, .serving]

      try await withThrowingTaskGroup(
        of: [Grpc_Health_V1_HealthCheckResponse.ServingStatus].self
      ) { group in
        var message = Grpc_Health_V1_HealthCheckRequest()
        message.service = testServiceDescriptor.fullyQualifiedService

        let immutableMessage = message

        /// The `continuation` of this stream is used to signal when the "watch" response streams are up and ready.
        let signal = AsyncStream.makeStream(of: Void.self)
        let numberOfWatches = 2

        for _ in 0 ..< numberOfWatches {
          group.addTask {
            return try await healthClient.watch(
              request: ClientRequest.Single(message: immutableMessage)
            ) { response in
              signal.continuation.yield()  // Make signal

              var statuses = [Grpc_Health_V1_HealthCheckResponse.ServingStatus]()
              var responseStreamIterator = response.messages.makeAsyncIterator()

              // Since responseStreamIterator.next() will never be nil (ideally, as the response
              // stream is always open), the iteration cannot be based on when
              // responseStreamIterator.next() is nil. Else, the iteration infinitely awaits and the
              // test never finishes. Hence, it is based on the expected number of statuses to be
              // received.
              for _ in 0 ..< statusesToBeSent.count + 1 {
                // As the service will be "watched" before being updated, the first status received
                // should be `.serviceUnknown`. Hence, the range of this iteration is increased by 1.

                let next = try await responseStreamIterator.next()
                let message = try XCTUnwrap(next)
                statuses.append(message.status)
              }

              return statuses
            }
          }
        }

        // Wait until all the "watch" streams are up and ready.
        for await _ in signal.stream.prefix(numberOfWatches) {}

        for status in statusesToBeSent {
          healthProvider.updateStatus(status, ofService: testServiceDescriptor)
        }

        for try await receivedStatuses in group {
          XCTAssertEqual(receivedStatuses[0], .serviceUnknown)

          for i in 0 ..< statusesToBeSent.count {
            let sentStatus = Grpc_Health_V1_HealthCheckResponse.ServingStatus(statusesToBeSent[i])
            XCTAssertEqual(sentStatus, receivedStatuses[i + 1])
          }
        }
      }
    }
  }

  func testWatchWithUnchangingStatusUpdates() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let testServiceDescriptor = ServiceDescriptor.testService

      let statusesToBeSent: [ServingStatus] = [
        .serving,
        .notServing,
        .notServing,
        .notServing,
        .serving,
      ]

      let expectedReceivedStatuses: [Grpc_Health_V1_HealthCheckResponse.ServingStatus] = [
        // As the service will be "watched" before being updated, the first status received should
        // be .serviceUnknown.
        .serviceUnknown,
        .serving,
        .notServing,  // The repeated `.notServing` updates should be received only once.
        .serving,
      ]

      try await withThrowingTaskGroup(
        of: [Grpc_Health_V1_HealthCheckResponse.ServingStatus].self
      ) { group in
        var message = Grpc_Health_V1_HealthCheckRequest()
        message.service = testServiceDescriptor.fullyQualifiedService

        let immutableMessage = message

        /// The `continuation` of this stream is used to signal when the "watch" response stream is up and ready.
        let signal = AsyncStream.makeStream(of: Void.self)

        group.addTask {
          return try await healthClient.watch(
            request: ClientRequest.Single(message: immutableMessage)
          ) { response in
            signal.continuation.finish()  // Make signal

            var statuses = [Grpc_Health_V1_HealthCheckResponse.ServingStatus]()
            var responseStreamIterator = response.messages.makeAsyncIterator()

            // Since responseStreamIterator.next() will never be nil (ideally, as the response
            // stream is always open), the iteration cannot be based on when
            // responseStreamIterator.next() is nil. Else, the iteration infinitely awaits and the
            // test never finishes. Hence, it is based on the expected number of statuses to be
            // received.
            for _ in 0 ..< expectedReceivedStatuses.count {
              let next = try await responseStreamIterator.next()
              let message = try XCTUnwrap(next)
              statuses.append(message.status)
            }

            return statuses
          }
        }

        // Wait until the "watch" stream is up and ready.
        for await _ in signal.stream {}

        for status in statusesToBeSent {
          healthProvider.updateStatus(status, ofService: testServiceDescriptor)
        }

        for try await receivedStatuses in group {
          XCTAssertEqual(receivedStatuses.count, expectedReceivedStatuses.count)

          for i in 0 ..< receivedStatuses.count {
            XCTAssertEqual(receivedStatuses[i], expectedReceivedStatuses[i])
          }
        }
      }
    }
  }

  func testWatchOnServer() async throws {
    try await withHealthClient { (healthClient, healthProvider) in
      let statusesToBeSent: [ServingStatus] = [.serving, .notServing, .serving]

      healthProvider.updateStatus(statusesToBeSent[0], ofService: ServiceDescriptor.server)

      let message = Grpc_Health_V1_HealthCheckRequest()

      try await healthClient.watch(request: ClientRequest.Single(message: message)) { response in
        var responseStreamIterator = response.messages.makeAsyncIterator()

        for i in 0 ..< statusesToBeSent.count {
          let next = try await responseStreamIterator.next()
          let message = try XCTUnwrap(next)
          let expectedStatus = Grpc_Health_V1_HealthCheckResponse.ServingStatus(statusesToBeSent[i])

          XCTAssertEqual(message.status, expectedStatus)

          if i < statusesToBeSent.count - 1 {
            healthProvider.updateStatus(
              statusesToBeSent[i + 1],
              ofService: ServiceDescriptor.server
            )
          }
        }
      }
    }
  }
}

extension ServiceDescriptor {
  fileprivate static let testService = ServiceDescriptor(package: "test", service: "Service")

  /// An unspecified service name refers to the server.
  fileprivate static let server = ServiceDescriptor(package: "", service: "")
}
