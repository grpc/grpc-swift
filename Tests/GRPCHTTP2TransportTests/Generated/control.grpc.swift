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
    internal enum Method {
        internal enum Unary {
            internal typealias Input = ControlInput
            internal typealias Output = ControlOutput
            internal static let descriptor = MethodDescriptor(
                service: "Control",
                method: "Unary"
            )
        }
        internal enum ServerStream {
            internal typealias Input = ControlInput
            internal typealias Output = ControlOutput
            internal static let descriptor = MethodDescriptor(
                service: "Control",
                method: "ServerStream"
            )
        }
        internal enum ClientStream {
            internal typealias Input = ControlInput
            internal typealias Output = ControlOutput
            internal static let descriptor = MethodDescriptor(
                service: "Control",
                method: "ClientStream"
            )
        }
        internal enum BidiStream {
            internal typealias Input = ControlInput
            internal typealias Output = ControlOutput
            internal static let descriptor = MethodDescriptor(
                service: "Control",
                method: "BidiStream"
            )
        }
        internal static let descriptors: [MethodDescriptor] = [
            Unary.descriptor,
            ServerStream.descriptor,
            ClientStream.descriptor,
            BidiStream.descriptor
        ]
    }
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    internal typealias StreamingServiceProtocol = ControlStreamingServiceProtocol
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    internal typealias ServiceProtocol = ControlServiceProtocol
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    internal typealias ClientProtocol = ControlClientProtocol
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    internal typealias Client = ControlClient
}

/// A controllable service for testing.
///
/// The control service has one RPC of each kind, the input to each RPC controls
/// the output.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
internal protocol ControlStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
    func unary(request: ServerRequest.Stream<Control.Method.Unary.Input>) async throws -> ServerResponse.Stream<Control.Method.Unary.Output>

    func serverStream(request: ServerRequest.Stream<Control.Method.ServerStream.Input>) async throws -> ServerResponse.Stream<Control.Method.ServerStream.Output>

    func clientStream(request: ServerRequest.Stream<Control.Method.ClientStream.Input>) async throws -> ServerResponse.Stream<Control.Method.ClientStream.Output>

    func bidiStream(request: ServerRequest.Stream<Control.Method.BidiStream.Input>) async throws -> ServerResponse.Stream<Control.Method.BidiStream.Output>
}

/// Conformance to `GRPCCore.RegistrableRPCService`.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Control.StreamingServiceProtocol {
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    internal func registerMethods(with router: inout GRPCCore.RPCRouter) {
        router.registerHandler(
            forMethod: Control.Method.Unary.descriptor,
            deserializer: ProtobufDeserializer<Control.Method.Unary.Input>(),
            serializer: ProtobufSerializer<Control.Method.Unary.Output>(),
            handler: { request in
                try await self.unary(request: request)
            }
        )
        router.registerHandler(
            forMethod: Control.Method.ServerStream.descriptor,
            deserializer: ProtobufDeserializer<Control.Method.ServerStream.Input>(),
            serializer: ProtobufSerializer<Control.Method.ServerStream.Output>(),
            handler: { request in
                try await self.serverStream(request: request)
            }
        )
        router.registerHandler(
            forMethod: Control.Method.ClientStream.descriptor,
            deserializer: ProtobufDeserializer<Control.Method.ClientStream.Input>(),
            serializer: ProtobufSerializer<Control.Method.ClientStream.Output>(),
            handler: { request in
                try await self.clientStream(request: request)
            }
        )
        router.registerHandler(
            forMethod: Control.Method.BidiStream.descriptor,
            deserializer: ProtobufDeserializer<Control.Method.BidiStream.Input>(),
            serializer: ProtobufSerializer<Control.Method.BidiStream.Output>(),
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
internal protocol ControlServiceProtocol: Control.StreamingServiceProtocol {
    func unary(request: ServerRequest.Single<Control.Method.Unary.Input>) async throws -> ServerResponse.Single<Control.Method.Unary.Output>

    func serverStream(request: ServerRequest.Single<Control.Method.ServerStream.Input>) async throws -> ServerResponse.Stream<Control.Method.ServerStream.Output>

    func clientStream(request: ServerRequest.Stream<Control.Method.ClientStream.Input>) async throws -> ServerResponse.Single<Control.Method.ClientStream.Output>

    func bidiStream(request: ServerRequest.Stream<Control.Method.BidiStream.Input>) async throws -> ServerResponse.Stream<Control.Method.BidiStream.Output>
}

/// Partial conformance to `ControlStreamingServiceProtocol`.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Control.ServiceProtocol {
    internal func unary(request: ServerRequest.Stream<Control.Method.Unary.Input>) async throws -> ServerResponse.Stream<Control.Method.Unary.Output> {
        let response = try await self.unary(request: ServerRequest.Single(stream: request))
        return ServerResponse.Stream(single: response)
    }

    internal func serverStream(request: ServerRequest.Stream<Control.Method.ServerStream.Input>) async throws -> ServerResponse.Stream<Control.Method.ServerStream.Output> {
        let response = try await self.serverStream(request: ServerRequest.Single(stream: request))
        return response
    }

    internal func clientStream(request: ServerRequest.Stream<Control.Method.ClientStream.Input>) async throws -> ServerResponse.Stream<Control.Method.ClientStream.Output> {
        let response = try await self.clientStream(request: request)
        return ServerResponse.Stream(single: response)
    }
}

/// A controllable service for testing.
///
/// The control service has one RPC of each kind, the input to each RPC controls
/// the output.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
internal protocol ControlClientProtocol: Sendable {
    func unary<R>(
        request: ClientRequest.Single<Control.Method.Unary.Input>,
        serializer: some MessageSerializer<Control.Method.Unary.Input>,
        deserializer: some MessageDeserializer<Control.Method.Unary.Output>,
        options: CallOptions,
        _ body: @Sendable @escaping (ClientResponse.Single<Control.Method.Unary.Output>) async throws -> R
    ) async throws -> R where R: Sendable

    func serverStream<R>(
        request: ClientRequest.Single<Control.Method.ServerStream.Input>,
        serializer: some MessageSerializer<Control.Method.ServerStream.Input>,
        deserializer: some MessageDeserializer<Control.Method.ServerStream.Output>,
        options: CallOptions,
        _ body: @Sendable @escaping (ClientResponse.Stream<Control.Method.ServerStream.Output>) async throws -> R
    ) async throws -> R where R: Sendable

    func clientStream<R>(
        request: ClientRequest.Stream<Control.Method.ClientStream.Input>,
        serializer: some MessageSerializer<Control.Method.ClientStream.Input>,
        deserializer: some MessageDeserializer<Control.Method.ClientStream.Output>,
        options: CallOptions,
        _ body: @Sendable @escaping (ClientResponse.Single<Control.Method.ClientStream.Output>) async throws -> R
    ) async throws -> R where R: Sendable

    func bidiStream<R>(
        request: ClientRequest.Stream<Control.Method.BidiStream.Input>,
        serializer: some MessageSerializer<Control.Method.BidiStream.Input>,
        deserializer: some MessageDeserializer<Control.Method.BidiStream.Output>,
        options: CallOptions,
        _ body: @Sendable @escaping (ClientResponse.Stream<Control.Method.BidiStream.Output>) async throws -> R
    ) async throws -> R where R: Sendable
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Control.ClientProtocol {
    internal func unary<R>(
        request: ClientRequest.Single<Control.Method.Unary.Input>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Single<Control.Method.Unary.Output>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.unary(
            request: request,
            serializer: ProtobufSerializer<Control.Method.Unary.Input>(),
            deserializer: ProtobufDeserializer<Control.Method.Unary.Output>(),
            options: options,
            body
        )
    }

    internal func serverStream<R>(
        request: ClientRequest.Single<Control.Method.ServerStream.Input>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Stream<Control.Method.ServerStream.Output>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.serverStream(
            request: request,
            serializer: ProtobufSerializer<Control.Method.ServerStream.Input>(),
            deserializer: ProtobufDeserializer<Control.Method.ServerStream.Output>(),
            options: options,
            body
        )
    }

    internal func clientStream<R>(
        request: ClientRequest.Stream<Control.Method.ClientStream.Input>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Single<Control.Method.ClientStream.Output>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.clientStream(
            request: request,
            serializer: ProtobufSerializer<Control.Method.ClientStream.Input>(),
            deserializer: ProtobufDeserializer<Control.Method.ClientStream.Output>(),
            options: options,
            body
        )
    }

    internal func bidiStream<R>(
        request: ClientRequest.Stream<Control.Method.BidiStream.Input>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Stream<Control.Method.BidiStream.Output>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.bidiStream(
            request: request,
            serializer: ProtobufSerializer<Control.Method.BidiStream.Input>(),
            deserializer: ProtobufDeserializer<Control.Method.BidiStream.Output>(),
            options: options,
            body
        )
    }
}

/// A controllable service for testing.
///
/// The control service has one RPC of each kind, the input to each RPC controls
/// the output.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
internal struct ControlClient: Control.ClientProtocol {
    private let client: GRPCCore.GRPCClient

    internal init(client: GRPCCore.GRPCClient) {
        self.client = client
    }

    internal func unary<R>(
        request: ClientRequest.Single<Control.Method.Unary.Input>,
        serializer: some MessageSerializer<Control.Method.Unary.Input>,
        deserializer: some MessageDeserializer<Control.Method.Unary.Output>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Single<Control.Method.Unary.Output>) async throws -> R
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
        request: ClientRequest.Single<Control.Method.ServerStream.Input>,
        serializer: some MessageSerializer<Control.Method.ServerStream.Input>,
        deserializer: some MessageDeserializer<Control.Method.ServerStream.Output>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Stream<Control.Method.ServerStream.Output>) async throws -> R
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
        request: ClientRequest.Stream<Control.Method.ClientStream.Input>,
        serializer: some MessageSerializer<Control.Method.ClientStream.Input>,
        deserializer: some MessageDeserializer<Control.Method.ClientStream.Output>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Single<Control.Method.ClientStream.Output>) async throws -> R
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
        request: ClientRequest.Stream<Control.Method.BidiStream.Input>,
        serializer: some MessageSerializer<Control.Method.BidiStream.Input>,
        deserializer: some MessageDeserializer<Control.Method.BidiStream.Output>,
        options: CallOptions = .defaults,
        _ body: @Sendable @escaping (ClientResponse.Stream<Control.Method.BidiStream.Output>) async throws -> R
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