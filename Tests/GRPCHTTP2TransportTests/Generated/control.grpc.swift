//
// Copyright 2024, gRPC Authors All rights reserved.
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

// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the gRPC Swift generator plugin for the protocol buffer compiler.
// Source: control.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/grpc/grpc-swift

import GRPCCore
import GRPCProtobuf

internal enum Control {
    internal static let descriptor = GRPCCore.ServiceDescriptor.Control
    internal enum Method {
        internal enum Unary {
            internal typealias Input = ControlInput
            internal typealias Output = ControlOutput
            internal static let descriptor = GRPCCore.MethodDescriptor(
                service: Control.descriptor.fullyQualifiedService,
                method: "Unary"
            )
        }
        internal enum ServerStream {
            internal typealias Input = ControlInput
            internal typealias Output = ControlOutput
            internal static let descriptor = GRPCCore.MethodDescriptor(
                service: Control.descriptor.fullyQualifiedService,
                method: "ServerStream"
            )
        }
        internal enum ClientStream {
            internal typealias Input = ControlInput
            internal typealias Output = ControlOutput
            internal static let descriptor = GRPCCore.MethodDescriptor(
                service: Control.descriptor.fullyQualifiedService,
                method: "ClientStream"
            )
        }
        internal enum BidiStream {
            internal typealias Input = ControlInput
            internal typealias Output = ControlOutput
            internal static let descriptor = GRPCCore.MethodDescriptor(
                service: Control.descriptor.fullyQualifiedService,
                method: "BidiStream"
            )
        }
        internal static let descriptors: [GRPCCore.MethodDescriptor] = [
            Unary.descriptor,
            ServerStream.descriptor,
            ClientStream.descriptor,
            BidiStream.descriptor
        ]
    }
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    internal typealias StreamingServiceProtocol = ControlStreamingServiceProtocol
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    internal typealias ServiceProtocol = ControlServiceProtocol
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    internal typealias ClientProtocol = ControlClientProtocol
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    internal typealias Client = ControlClient
}

extension GRPCCore.ServiceDescriptor {
    internal static let Control = Self(
        package: "",
        service: "Control"
    )
}

/// A controllable service for testing.
///
/// The control service has one RPC of each kind, the input to each RPC controls
/// the output.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
internal protocol ControlStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
    func unary(request: GRPCCore.ServerRequest.Stream<ControlInput>) async throws -> GRPCCore.ServerResponse.Stream<ControlOutput>

    func serverStream(request: GRPCCore.ServerRequest.Stream<ControlInput>) async throws -> GRPCCore.ServerResponse.Stream<ControlOutput>

    func clientStream(request: GRPCCore.ServerRequest.Stream<ControlInput>) async throws -> GRPCCore.ServerResponse.Stream<ControlOutput>

    func bidiStream(request: GRPCCore.ServerRequest.Stream<ControlInput>) async throws -> GRPCCore.ServerResponse.Stream<ControlOutput>
}

/// Conformance to `GRPCCore.RegistrableRPCService`.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Control.StreamingServiceProtocol {
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    internal func registerMethods(with router: inout GRPCCore.RPCRouter) {
        router.registerHandler(
            forMethod: Control.Method.Unary.descriptor,
            deserializer: GRPCProtobuf.ProtobufDeserializer<ControlInput>(),
            serializer: GRPCProtobuf.ProtobufSerializer<ControlOutput>(),
            handler: { request in
                try await self.unary(request: request)
            }
        )
        router.registerHandler(
            forMethod: Control.Method.ServerStream.descriptor,
            deserializer: GRPCProtobuf.ProtobufDeserializer<ControlInput>(),
            serializer: GRPCProtobuf.ProtobufSerializer<ControlOutput>(),
            handler: { request in
                try await self.serverStream(request: request)
            }
        )
        router.registerHandler(
            forMethod: Control.Method.ClientStream.descriptor,
            deserializer: GRPCProtobuf.ProtobufDeserializer<ControlInput>(),
            serializer: GRPCProtobuf.ProtobufSerializer<ControlOutput>(),
            handler: { request in
                try await self.clientStream(request: request)
            }
        )
        router.registerHandler(
            forMethod: Control.Method.BidiStream.descriptor,
            deserializer: GRPCProtobuf.ProtobufDeserializer<ControlInput>(),
            serializer: GRPCProtobuf.ProtobufSerializer<ControlOutput>(),
            handler: { request in
                try await self.bidiStream(request: request)
            }
        )
    }
}

/// A controllable service for testing.
///
/// The control service has one RPC of each kind, the input to each RPC controls
/// the output.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
internal protocol ControlServiceProtocol: Control.StreamingServiceProtocol {
    func unary(request: GRPCCore.ServerRequest.Single<ControlInput>) async throws -> GRPCCore.ServerResponse.Single<ControlOutput>

    func serverStream(request: GRPCCore.ServerRequest.Single<ControlInput>) async throws -> GRPCCore.ServerResponse.Stream<ControlOutput>

    func clientStream(request: GRPCCore.ServerRequest.Stream<ControlInput>) async throws -> GRPCCore.ServerResponse.Single<ControlOutput>

    func bidiStream(request: GRPCCore.ServerRequest.Stream<ControlInput>) async throws -> GRPCCore.ServerResponse.Stream<ControlOutput>
}

/// Partial conformance to `ControlStreamingServiceProtocol`.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Control.ServiceProtocol {
    internal func unary(request: GRPCCore.ServerRequest.Stream<ControlInput>) async throws -> GRPCCore.ServerResponse.Stream<ControlOutput> {
        let response = try await self.unary(request: GRPCCore.ServerRequest.Single(stream: request))
        return GRPCCore.ServerResponse.Stream(single: response)
    }

    internal func serverStream(request: GRPCCore.ServerRequest.Stream<ControlInput>) async throws -> GRPCCore.ServerResponse.Stream<ControlOutput> {
        let response = try await self.serverStream(request: GRPCCore.ServerRequest.Single(stream: request))
        return response
    }

    internal func clientStream(request: GRPCCore.ServerRequest.Stream<ControlInput>) async throws -> GRPCCore.ServerResponse.Stream<ControlOutput> {
        let response = try await self.clientStream(request: request)
        return GRPCCore.ServerResponse.Stream(single: response)
    }
}

/// A controllable service for testing.
///
/// The control service has one RPC of each kind, the input to each RPC controls
/// the output.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
internal protocol ControlClientProtocol: Sendable {
    func unary<R>(
        request: GRPCCore.ClientRequest.Single<ControlInput>,
        serializer: some GRPCCore.MessageSerializer<ControlInput>,
        deserializer: some GRPCCore.MessageDeserializer<ControlOutput>,
        options: GRPCCore.CallOptions,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable

    func serverStream<R>(
        request: GRPCCore.ClientRequest.Single<ControlInput>,
        serializer: some GRPCCore.MessageSerializer<ControlInput>,
        deserializer: some GRPCCore.MessageDeserializer<ControlOutput>,
        options: GRPCCore.CallOptions,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable

    func clientStream<R>(
        request: GRPCCore.ClientRequest.Stream<ControlInput>,
        serializer: some GRPCCore.MessageSerializer<ControlInput>,
        deserializer: some GRPCCore.MessageDeserializer<ControlOutput>,
        options: GRPCCore.CallOptions,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable

    func bidiStream<R>(
        request: GRPCCore.ClientRequest.Stream<ControlInput>,
        serializer: some GRPCCore.MessageSerializer<ControlInput>,
        deserializer: some GRPCCore.MessageDeserializer<ControlOutput>,
        options: GRPCCore.CallOptions,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Control.ClientProtocol {
    internal func unary<R>(
        request: GRPCCore.ClientRequest.Single<ControlInput>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.unary(
            request: request,
            serializer: GRPCProtobuf.ProtobufSerializer<ControlInput>(),
            deserializer: GRPCProtobuf.ProtobufDeserializer<ControlOutput>(),
            options: options,
            body
        )
    }

    internal func serverStream<R>(
        request: GRPCCore.ClientRequest.Single<ControlInput>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.serverStream(
            request: request,
            serializer: GRPCProtobuf.ProtobufSerializer<ControlInput>(),
            deserializer: GRPCProtobuf.ProtobufDeserializer<ControlOutput>(),
            options: options,
            body
        )
    }

    internal func clientStream<R>(
        request: GRPCCore.ClientRequest.Stream<ControlInput>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.clientStream(
            request: request,
            serializer: GRPCProtobuf.ProtobufSerializer<ControlInput>(),
            deserializer: GRPCProtobuf.ProtobufDeserializer<ControlOutput>(),
            options: options,
            body
        )
    }

    internal func bidiStream<R>(
        request: GRPCCore.ClientRequest.Stream<ControlInput>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.bidiStream(
            request: request,
            serializer: GRPCProtobuf.ProtobufSerializer<ControlInput>(),
            deserializer: GRPCProtobuf.ProtobufDeserializer<ControlOutput>(),
            options: options,
            body
        )
    }
}

/// A controllable service for testing.
///
/// The control service has one RPC of each kind, the input to each RPC controls
/// the output.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
internal struct ControlClient: Control.ClientProtocol {
    private let client: GRPCCore.GRPCClient

    internal init(wrapping client: GRPCCore.GRPCClient) {
        self.client = client
    }

    internal func unary<R>(
        request: GRPCCore.ClientRequest.Single<ControlInput>,
        serializer: some GRPCCore.MessageSerializer<ControlInput>,
        deserializer: some GRPCCore.MessageDeserializer<ControlOutput>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.client.unary(
            request: request,
            descriptor: Control.Method.Unary.descriptor,
            serializer: serializer,
            deserializer: deserializer,
            options: options,
            handler: body
        )
    }

    internal func serverStream<R>(
        request: GRPCCore.ClientRequest.Single<ControlInput>,
        serializer: some GRPCCore.MessageSerializer<ControlInput>,
        deserializer: some GRPCCore.MessageDeserializer<ControlOutput>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.client.serverStreaming(
            request: request,
            descriptor: Control.Method.ServerStream.descriptor,
            serializer: serializer,
            deserializer: deserializer,
            options: options,
            handler: body
        )
    }

    internal func clientStream<R>(
        request: GRPCCore.ClientRequest.Stream<ControlInput>,
        serializer: some GRPCCore.MessageSerializer<ControlInput>,
        deserializer: some GRPCCore.MessageDeserializer<ControlOutput>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.client.clientStreaming(
            request: request,
            descriptor: Control.Method.ClientStream.descriptor,
            serializer: serializer,
            deserializer: deserializer,
            options: options,
            handler: body
        )
    }

    internal func bidiStream<R>(
        request: GRPCCore.ClientRequest.Stream<ControlInput>,
        serializer: some GRPCCore.MessageSerializer<ControlInput>,
        deserializer: some GRPCCore.MessageDeserializer<ControlOutput>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<ControlOutput>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.client.bidirectionalStreaming(
            request: request,
            descriptor: Control.Method.BidiStream.descriptor,
            serializer: serializer,
            deserializer: deserializer,
            options: options,
            handler: body
        )
    }
}