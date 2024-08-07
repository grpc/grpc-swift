// Copyright 2015 The gRPC Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// The canonical version of this proto can be found at
// https://github.com/grpc/grpc-proto/blob/master/grpc/health/v1/health.proto

// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the gRPC Swift generator plugin for the protocol buffer compiler.
// Source: health.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/grpc/grpc-swift

import GRPCCore
import GRPCProtobuf

package enum Grpc_Health_V1_Health {
    package static let descriptor = ServiceDescriptor.grpc_health_v1_Health
    package enum Method {
        package enum Check {
            package typealias Input = Grpc_Health_V1_HealthCheckRequest
            package typealias Output = Grpc_Health_V1_HealthCheckResponse
            package static let descriptor = MethodDescriptor(
                service: Grpc_Health_V1_Health.descriptor.fullyQualifiedService,
                method: "Check"
            )
        }
        package enum Watch {
            package typealias Input = Grpc_Health_V1_HealthCheckRequest
            package typealias Output = Grpc_Health_V1_HealthCheckResponse
            package static let descriptor = MethodDescriptor(
                service: Grpc_Health_V1_Health.descriptor.fullyQualifiedService,
                method: "Watch"
            )
        }
        package static let descriptors: [MethodDescriptor] = [
            Check.descriptor,
            Watch.descriptor
        ]
    }
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    package typealias StreamingServiceProtocol = Grpc_Health_V1_HealthStreamingServiceProtocol
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    package typealias ServiceProtocol = Grpc_Health_V1_HealthServiceProtocol
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    package typealias ClientProtocol = Grpc_Health_V1_HealthClientProtocol
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    package typealias Client = Grpc_Health_V1_HealthClient
}

extension ServiceDescriptor {
    package static let grpc_health_v1_Health = Self(
        package: "grpc.health.v1",
        service: "Health"
    )
}

/// Health is gRPC's mechanism for checking whether a server is able to handle
/// RPCs. Its semantics are documented in
/// https://github.com/grpc/grpc/blob/master/doc/health-checking.md.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
package protocol Grpc_Health_V1_HealthStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
    /// Check gets the health of the specified service. If the requested service
    /// is unknown, the call will fail with status NOT_FOUND. If the caller does
    /// not specify a service name, the server should respond with its overall
    /// health status.
    ///
    /// Clients should set a deadline when calling Check, and can declare the
    /// server unhealthy if they do not receive a timely response.
    ///
    /// Check implementations should be idempotent and side effect free.
    func check(request: ServerRequest.Stream<Grpc_Health_V1_HealthCheckRequest>) async throws -> ServerResponse.Stream<Grpc_Health_V1_HealthCheckResponse>

    /// Performs a watch for the serving status of the requested service.
    /// The server will immediately send back a message indicating the current
    /// serving status.  It will then subsequently send a new message whenever
    /// the service's serving status changes.
    ///
    /// If the requested service is unknown when the call is received, the
    /// server will send a message setting the serving status to
    /// SERVICE_UNKNOWN but will *not* terminate the call.  If at some
    /// future point, the serving status of the service becomes known, the
    /// server will send a new message with the service's serving status.
    ///
    /// If the call terminates with status UNIMPLEMENTED, then clients
    /// should assume this method is not supported and should not retry the
    /// call.  If the call terminates with any other status (including OK),
    /// clients should retry the call with appropriate exponential backoff.
    func watch(request: ServerRequest.Stream<Grpc_Health_V1_HealthCheckRequest>) async throws -> ServerResponse.Stream<Grpc_Health_V1_HealthCheckResponse>
}

/// Conformance to `GRPCCore.RegistrableRPCService`.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Grpc_Health_V1_Health.StreamingServiceProtocol {
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    package func registerMethods(with router: inout GRPCCore.RPCRouter) {
        router.registerHandler(
            forMethod: Grpc_Health_V1_Health.Method.Check.descriptor,
            deserializer: ProtobufDeserializer<Grpc_Health_V1_HealthCheckRequest>(),
            serializer: ProtobufSerializer<Grpc_Health_V1_HealthCheckResponse>(),
            handler: { request in
                try await self.check(request: request)
            }
        )
        router.registerHandler(
            forMethod: Grpc_Health_V1_Health.Method.Watch.descriptor,
            deserializer: ProtobufDeserializer<Grpc_Health_V1_HealthCheckRequest>(),
            serializer: ProtobufSerializer<Grpc_Health_V1_HealthCheckResponse>(),
            handler: { request in
                try await self.watch(request: request)
            }
        )
    }
}

/// Health is gRPC's mechanism for checking whether a server is able to handle
/// RPCs. Its semantics are documented in
/// https://github.com/grpc/grpc/blob/master/doc/health-checking.md.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
package protocol Grpc_Health_V1_HealthServiceProtocol: Grpc_Health_V1_Health.StreamingServiceProtocol {
    /// Check gets the health of the specified service. If the requested service
    /// is unknown, the call will fail with status NOT_FOUND. If the caller does
    /// not specify a service name, the server should respond with its overall
    /// health status.
    ///
    /// Clients should set a deadline when calling Check, and can declare the
    /// server unhealthy if they do not receive a timely response.
    ///
    /// Check implementations should be idempotent and side effect free.
    func check(request: ServerRequest.Single<Grpc_Health_V1_HealthCheckRequest>) async throws -> ServerResponse.Single<Grpc_Health_V1_HealthCheckResponse>

    /// Performs a watch for the serving status of the requested service.
    /// The server will immediately send back a message indicating the current
    /// serving status.  It will then subsequently send a new message whenever
    /// the service's serving status changes.
    ///
    /// If the requested service is unknown when the call is received, the
    /// server will send a message setting the serving status to
    /// SERVICE_UNKNOWN but will *not* terminate the call.  If at some
    /// future point, the serving status of the service becomes known, the
    /// server will send a new message with the service's serving status.
    ///
    /// If the call terminates with status UNIMPLEMENTED, then clients
    /// should assume this method is not supported and should not retry the
    /// call.  If the call terminates with any other status (including OK),
    /// clients should retry the call with appropriate exponential backoff.
    func watch(request: ServerRequest.Single<Grpc_Health_V1_HealthCheckRequest>) async throws -> ServerResponse.Stream<Grpc_Health_V1_HealthCheckResponse>
}

/// Partial conformance to `Grpc_Health_V1_HealthStreamingServiceProtocol`.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Grpc_Health_V1_Health.ServiceProtocol {
    package func check(request: ServerRequest.Stream<Grpc_Health_V1_HealthCheckRequest>) async throws -> ServerResponse.Stream<Grpc_Health_V1_HealthCheckResponse> {
        let response = try await self.check(request: ServerRequest.Single(stream: request))
        return ServerResponse.Stream(single: response)
    }

    package func watch(request: ServerRequest.Stream<Grpc_Health_V1_HealthCheckRequest>) async throws -> ServerResponse.Stream<Grpc_Health_V1_HealthCheckResponse> {
        let response = try await self.watch(request: ServerRequest.Single(stream: request))
        return response
    }
}

/// Health is gRPC's mechanism for checking whether a server is able to handle
/// RPCs. Its semantics are documented in
/// https://github.com/grpc/grpc/blob/master/doc/health-checking.md.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
package protocol Grpc_Health_V1_HealthClientProtocol: Sendable {
    /// Check gets the health of the specified service. If the requested service
    /// is unknown, the call will fail with status NOT_FOUND. If the caller does
    /// not specify a service name, the server should respond with its overall
    /// health status.
    ///
    /// Clients should set a deadline when calling Check, and can declare the
    /// server unhealthy if they do not receive a timely response.
    ///
    /// Check implementations should be idempotent and side effect free.
    func check<R>(
        request: ClientRequest.Single<Grpc_Health_V1_HealthCheckRequest>,
        serializer: some MessageSerializer<Grpc_Health_V1_HealthCheckRequest>,
        deserializer: some MessageDeserializer<Grpc_Health_V1_HealthCheckResponse>,
        options: CallOptions,
        _ body: @Sendable @escaping (ClientResponse.Single<Grpc_Health_V1_HealthCheckResponse>) async throws -> R
    ) async throws -> R where R: Sendable

    /// Performs a watch for the serving status of the requested service.
    /// The server will immediately send back a message indicating the current
    /// serving status.  It will then subsequently send a new message whenever
    /// the service's serving status changes.
    ///
    /// If the requested service is unknown when the call is received, the
    /// server will send a message setting the serving status to
    /// SERVICE_UNKNOWN but will *not* terminate the call.  If at some
    /// future point, the serving status of the service becomes known, the
    /// server will send a new message with the service's serving status.
    ///
    /// If the call terminates with status UNIMPLEMENTED, then clients
    /// should assume this method is not supported and should not retry the
    /// call.  If the call terminates with any other status (including OK),
    /// clients should retry the call with appropriate exponential backoff.
    func watch<R>(
        request: ClientRequest.Single<Grpc_Health_V1_HealthCheckRequest>,
        serializer: some MessageSerializer<Grpc_Health_V1_HealthCheckRequest>,
        deserializer: some MessageDeserializer<Grpc_Health_V1_HealthCheckResponse>,
        options: CallOptions,
        _ body: @Sendable @escaping (ClientResponse.Stream<Grpc_Health_V1_HealthCheckResponse>) async throws -> R
    ) async throws -> R where R: Sendable
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Grpc_Health_V1_Health.ClientProtocol {
    package func check<R>(
        request: ClientRequest.Single<Grpc_Health_V1_HealthCheckRequest>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Single<Grpc_Health_V1_HealthCheckResponse>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.check(
            request: request,
            serializer: ProtobufSerializer<Grpc_Health_V1_HealthCheckRequest>(),
            deserializer: ProtobufDeserializer<Grpc_Health_V1_HealthCheckResponse>(),
            options: options,
            body
        )
    }

    package func watch<R>(
        request: ClientRequest.Single<Grpc_Health_V1_HealthCheckRequest>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Stream<Grpc_Health_V1_HealthCheckResponse>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.watch(
            request: request,
            serializer: ProtobufSerializer<Grpc_Health_V1_HealthCheckRequest>(),
            deserializer: ProtobufDeserializer<Grpc_Health_V1_HealthCheckResponse>(),
            options: options,
            body
        )
    }
}

/// Health is gRPC's mechanism for checking whether a server is able to handle
/// RPCs. Its semantics are documented in
/// https://github.com/grpc/grpc/blob/master/doc/health-checking.md.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
package struct Grpc_Health_V1_HealthClient: Grpc_Health_V1_Health.ClientProtocol {
    private let client: GRPCCore.GRPCClient

    package init(client: GRPCCore.GRPCClient) {
        self.client = client
    }

    /// Check gets the health of the specified service. If the requested service
    /// is unknown, the call will fail with status NOT_FOUND. If the caller does
    /// not specify a service name, the server should respond with its overall
    /// health status.
    ///
    /// Clients should set a deadline when calling Check, and can declare the
    /// server unhealthy if they do not receive a timely response.
    ///
    /// Check implementations should be idempotent and side effect free.
    package func check<R>(
        request: ClientRequest.Single<Grpc_Health_V1_HealthCheckRequest>,
        serializer: some MessageSerializer<Grpc_Health_V1_HealthCheckRequest>,
        deserializer: some MessageDeserializer<Grpc_Health_V1_HealthCheckResponse>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Single<Grpc_Health_V1_HealthCheckResponse>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.client.unary(
            request: request,
            descriptor: Grpc_Health_V1_Health.Method.Check.descriptor,
            serializer: serializer,
            deserializer: deserializer,
            options: options,
            handler: body
        )
    }

    /// Performs a watch for the serving status of the requested service.
    /// The server will immediately send back a message indicating the current
    /// serving status.  It will then subsequently send a new message whenever
    /// the service's serving status changes.
    ///
    /// If the requested service is unknown when the call is received, the
    /// server will send a message setting the serving status to
    /// SERVICE_UNKNOWN but will *not* terminate the call.  If at some
    /// future point, the serving status of the service becomes known, the
    /// server will send a new message with the service's serving status.
    ///
    /// If the call terminates with status UNIMPLEMENTED, then clients
    /// should assume this method is not supported and should not retry the
    /// call.  If the call terminates with any other status (including OK),
    /// clients should retry the call with appropriate exponential backoff.
    package func watch<R>(
        request: ClientRequest.Single<Grpc_Health_V1_HealthCheckRequest>,
        serializer: some MessageSerializer<Grpc_Health_V1_HealthCheckRequest>,
        deserializer: some MessageDeserializer<Grpc_Health_V1_HealthCheckResponse>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Stream<Grpc_Health_V1_HealthCheckResponse>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.client.serverStreaming(
            request: request,
            descriptor: Grpc_Health_V1_Health.Method.Watch.descriptor,
            serializer: serializer,
            deserializer: deserializer,
            options: options,
            handler: body
        )
    }
}