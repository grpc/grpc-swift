// Copyright (c) 2015, Google Inc.
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
// Source: echo.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/grpc/grpc-swift

internal import GRPCCore
internal import GRPCProtobuf

internal enum Echo_Echo {
    internal static let descriptor = GRPCCore.ServiceDescriptor.echo_Echo
    internal enum Method {
        internal enum Get {
            internal typealias Input = Echo_EchoRequest
            internal typealias Output = Echo_EchoResponse
            internal static let descriptor = GRPCCore.MethodDescriptor(
                service: Echo_Echo.descriptor.fullyQualifiedService,
                method: "Get"
            )
        }
        internal enum Expand {
            internal typealias Input = Echo_EchoRequest
            internal typealias Output = Echo_EchoResponse
            internal static let descriptor = GRPCCore.MethodDescriptor(
                service: Echo_Echo.descriptor.fullyQualifiedService,
                method: "Expand"
            )
        }
        internal enum Collect {
            internal typealias Input = Echo_EchoRequest
            internal typealias Output = Echo_EchoResponse
            internal static let descriptor = GRPCCore.MethodDescriptor(
                service: Echo_Echo.descriptor.fullyQualifiedService,
                method: "Collect"
            )
        }
        internal enum Update {
            internal typealias Input = Echo_EchoRequest
            internal typealias Output = Echo_EchoResponse
            internal static let descriptor = GRPCCore.MethodDescriptor(
                service: Echo_Echo.descriptor.fullyQualifiedService,
                method: "Update"
            )
        }
        internal static let descriptors: [GRPCCore.MethodDescriptor] = [
            Get.descriptor,
            Expand.descriptor,
            Collect.descriptor,
            Update.descriptor
        ]
    }
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    internal typealias StreamingServiceProtocol = Echo_EchoStreamingServiceProtocol
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    internal typealias ServiceProtocol = Echo_EchoServiceProtocol
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    internal typealias ClientProtocol = Echo_EchoClientProtocol
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    internal typealias Client = Echo_EchoClient
}

extension GRPCCore.ServiceDescriptor {
    internal static let echo_Echo = Self(
        package: "echo",
        service: "Echo"
    )
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
internal protocol Echo_EchoStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
    /// Immediately returns an echo of a request.
    func get(request: GRPCCore.ServerRequest.Stream<Echo_EchoRequest>) async throws -> GRPCCore.ServerResponse.Stream<Echo_EchoResponse>
    
    /// Splits a request into words and returns each word in a stream of messages.
    func expand(request: GRPCCore.ServerRequest.Stream<Echo_EchoRequest>) async throws -> GRPCCore.ServerResponse.Stream<Echo_EchoResponse>
    
    /// Collects a stream of messages and returns them concatenated when the caller closes.
    func collect(request: GRPCCore.ServerRequest.Stream<Echo_EchoRequest>) async throws -> GRPCCore.ServerResponse.Stream<Echo_EchoResponse>
    
    /// Streams back messages as they are received in an input stream.
    func update(request: GRPCCore.ServerRequest.Stream<Echo_EchoRequest>) async throws -> GRPCCore.ServerResponse.Stream<Echo_EchoResponse>
}

/// Conformance to `GRPCCore.RegistrableRPCService`.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Echo_Echo.StreamingServiceProtocol {
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    internal func registerMethods(with router: inout GRPCCore.RPCRouter) {
        router.registerHandler(
            forMethod: Echo_Echo.Method.Get.descriptor,
            deserializer: GRPCProtobuf.ProtobufDeserializer<Echo_EchoRequest>(),
            serializer: GRPCProtobuf.ProtobufSerializer<Echo_EchoResponse>(),
            handler: { request in
                try await self.get(request: request)
            }
        )
        router.registerHandler(
            forMethod: Echo_Echo.Method.Expand.descriptor,
            deserializer: GRPCProtobuf.ProtobufDeserializer<Echo_EchoRequest>(),
            serializer: GRPCProtobuf.ProtobufSerializer<Echo_EchoResponse>(),
            handler: { request in
                try await self.expand(request: request)
            }
        )
        router.registerHandler(
            forMethod: Echo_Echo.Method.Collect.descriptor,
            deserializer: GRPCProtobuf.ProtobufDeserializer<Echo_EchoRequest>(),
            serializer: GRPCProtobuf.ProtobufSerializer<Echo_EchoResponse>(),
            handler: { request in
                try await self.collect(request: request)
            }
        )
        router.registerHandler(
            forMethod: Echo_Echo.Method.Update.descriptor,
            deserializer: GRPCProtobuf.ProtobufDeserializer<Echo_EchoRequest>(),
            serializer: GRPCProtobuf.ProtobufSerializer<Echo_EchoResponse>(),
            handler: { request in
                try await self.update(request: request)
            }
        )
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
internal protocol Echo_EchoServiceProtocol: Echo_Echo.StreamingServiceProtocol {
    /// Immediately returns an echo of a request.
    func get(request: GRPCCore.ServerRequest.Single<Echo_EchoRequest>) async throws -> GRPCCore.ServerResponse.Single<Echo_EchoResponse>
    
    /// Splits a request into words and returns each word in a stream of messages.
    func expand(request: GRPCCore.ServerRequest.Single<Echo_EchoRequest>) async throws -> GRPCCore.ServerResponse.Stream<Echo_EchoResponse>
    
    /// Collects a stream of messages and returns them concatenated when the caller closes.
    func collect(request: GRPCCore.ServerRequest.Stream<Echo_EchoRequest>) async throws -> GRPCCore.ServerResponse.Single<Echo_EchoResponse>
    
    /// Streams back messages as they are received in an input stream.
    func update(request: GRPCCore.ServerRequest.Stream<Echo_EchoRequest>) async throws -> GRPCCore.ServerResponse.Stream<Echo_EchoResponse>
}

/// Partial conformance to `Echo_EchoStreamingServiceProtocol`.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Echo_Echo.ServiceProtocol {
    internal func get(request: GRPCCore.ServerRequest.Stream<Echo_EchoRequest>) async throws -> GRPCCore.ServerResponse.Stream<Echo_EchoResponse> {
        let response = try await self.get(request: GRPCCore.ServerRequest.Single(stream: request))
        return GRPCCore.ServerResponse.Stream(single: response)
    }
    
    internal func expand(request: GRPCCore.ServerRequest.Stream<Echo_EchoRequest>) async throws -> GRPCCore.ServerResponse.Stream<Echo_EchoResponse> {
        let response = try await self.expand(request: GRPCCore.ServerRequest.Single(stream: request))
        return response
    }
    
    internal func collect(request: GRPCCore.ServerRequest.Stream<Echo_EchoRequest>) async throws -> GRPCCore.ServerResponse.Stream<Echo_EchoResponse> {
        let response = try await self.collect(request: request)
        return GRPCCore.ServerResponse.Stream(single: response)
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
internal protocol Echo_EchoClientProtocol: Sendable {
    /// Immediately returns an echo of a request.
    func get<R>(
        request: GRPCCore.ClientRequest.Single<Echo_EchoRequest>,
        serializer: some GRPCCore.MessageSerializer<Echo_EchoRequest>,
        deserializer: some GRPCCore.MessageDeserializer<Echo_EchoResponse>,
        options: GRPCCore.CallOptions,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<Echo_EchoResponse>) async throws -> R
    ) async throws -> R where R: Sendable
    
    /// Splits a request into words and returns each word in a stream of messages.
    func expand<R>(
        request: GRPCCore.ClientRequest.Single<Echo_EchoRequest>,
        serializer: some GRPCCore.MessageSerializer<Echo_EchoRequest>,
        deserializer: some GRPCCore.MessageDeserializer<Echo_EchoResponse>,
        options: GRPCCore.CallOptions,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<Echo_EchoResponse>) async throws -> R
    ) async throws -> R where R: Sendable
    
    /// Collects a stream of messages and returns them concatenated when the caller closes.
    func collect<R>(
        request: GRPCCore.ClientRequest.Stream<Echo_EchoRequest>,
        serializer: some GRPCCore.MessageSerializer<Echo_EchoRequest>,
        deserializer: some GRPCCore.MessageDeserializer<Echo_EchoResponse>,
        options: GRPCCore.CallOptions,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<Echo_EchoResponse>) async throws -> R
    ) async throws -> R where R: Sendable
    
    /// Streams back messages as they are received in an input stream.
    func update<R>(
        request: GRPCCore.ClientRequest.Stream<Echo_EchoRequest>,
        serializer: some GRPCCore.MessageSerializer<Echo_EchoRequest>,
        deserializer: some GRPCCore.MessageDeserializer<Echo_EchoResponse>,
        options: GRPCCore.CallOptions,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<Echo_EchoResponse>) async throws -> R
    ) async throws -> R where R: Sendable
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Echo_Echo.ClientProtocol {
    internal func get<R>(
        request: GRPCCore.ClientRequest.Single<Echo_EchoRequest>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<Echo_EchoResponse>) async throws -> R = {
            try $0.message
        }
    ) async throws -> R where R: Sendable {
        try await self.get(
            request: request,
            serializer: GRPCProtobuf.ProtobufSerializer<Echo_EchoRequest>(),
            deserializer: GRPCProtobuf.ProtobufDeserializer<Echo_EchoResponse>(),
            options: options,
            body
        )
    }
    
    internal func expand<R>(
        request: GRPCCore.ClientRequest.Single<Echo_EchoRequest>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<Echo_EchoResponse>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.expand(
            request: request,
            serializer: GRPCProtobuf.ProtobufSerializer<Echo_EchoRequest>(),
            deserializer: GRPCProtobuf.ProtobufDeserializer<Echo_EchoResponse>(),
            options: options,
            body
        )
    }
    
    internal func collect<R>(
        request: GRPCCore.ClientRequest.Stream<Echo_EchoRequest>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<Echo_EchoResponse>) async throws -> R = {
            try $0.message
        }
    ) async throws -> R where R: Sendable {
        try await self.collect(
            request: request,
            serializer: GRPCProtobuf.ProtobufSerializer<Echo_EchoRequest>(),
            deserializer: GRPCProtobuf.ProtobufDeserializer<Echo_EchoResponse>(),
            options: options,
            body
        )
    }
    
    internal func update<R>(
        request: GRPCCore.ClientRequest.Stream<Echo_EchoRequest>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<Echo_EchoResponse>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.update(
            request: request,
            serializer: GRPCProtobuf.ProtobufSerializer<Echo_EchoRequest>(),
            deserializer: GRPCProtobuf.ProtobufDeserializer<Echo_EchoResponse>(),
            options: options,
            body
        )
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Echo_Echo.ClientProtocol {
    /// Immediately returns an echo of a request.
    internal func get<Result>(
        _ message: Echo_EchoRequest,
        metadata: GRPCCore.Metadata = [:],
        options: GRPCCore.CallOptions = .defaults,
        onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse.Single<Echo_EchoResponse>) async throws -> Result = {
            try $0.message
        }
    ) async throws -> Result where Result: Sendable {
        let request = GRPCCore.ClientRequest.Single<Echo_EchoRequest>(
            message: message,
            metadata: metadata
        )
        return try await self.get(
            request: request,
            options: options,
            handleResponse
        )
    }
    
    /// Splits a request into words and returns each word in a stream of messages.
    internal func expand<Result>(
        _ message: Echo_EchoRequest,
        metadata: GRPCCore.Metadata = [:],
        options: GRPCCore.CallOptions = .defaults,
        onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse.Stream<Echo_EchoResponse>) async throws -> Result
    ) async throws -> Result where Result: Sendable {
        let request = GRPCCore.ClientRequest.Single<Echo_EchoRequest>(
            message: message,
            metadata: metadata
        )
        return try await self.expand(
            request: request,
            options: options,
            handleResponse
        )
    }
    
    /// Collects a stream of messages and returns them concatenated when the caller closes.
    internal func collect<Result>(
        metadata: GRPCCore.Metadata = [:],
        options: GRPCCore.CallOptions = .defaults,
        requestProducer: @Sendable @escaping (GRPCCore.RPCWriter<Echo_EchoRequest>) async throws -> Void,
        onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse.Single<Echo_EchoResponse>) async throws -> Result = {
            try $0.message
        }
    ) async throws -> Result where Result: Sendable {
        let request = GRPCCore.ClientRequest.Stream<Echo_EchoRequest>(
            metadata: metadata,
            producer: requestProducer
        )
        return try await self.collect(
            request: request,
            options: options,
            handleResponse
        )
    }
    
    /// Streams back messages as they are received in an input stream.
    internal func update<Result>(
        metadata: GRPCCore.Metadata = [:],
        options: GRPCCore.CallOptions = .defaults,
        requestProducer: @Sendable @escaping (GRPCCore.RPCWriter<Echo_EchoRequest>) async throws -> Void,
        onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse.Stream<Echo_EchoResponse>) async throws -> Result
    ) async throws -> Result where Result: Sendable {
        let request = GRPCCore.ClientRequest.Stream<Echo_EchoRequest>(
            metadata: metadata,
            producer: requestProducer
        )
        return try await self.update(
            request: request,
            options: options,
            handleResponse
        )
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
internal struct Echo_EchoClient: Echo_Echo.ClientProtocol {
    private let client: GRPCCore.GRPCClient
    
    internal init(wrapping client: GRPCCore.GRPCClient) {
        self.client = client
    }
    
    /// Immediately returns an echo of a request.
    internal func get<R>(
        request: GRPCCore.ClientRequest.Single<Echo_EchoRequest>,
        serializer: some GRPCCore.MessageSerializer<Echo_EchoRequest>,
        deserializer: some GRPCCore.MessageDeserializer<Echo_EchoResponse>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<Echo_EchoResponse>) async throws -> R = {
            try $0.message
        }
    ) async throws -> R where R: Sendable {
        try await self.client.unary(
            request: request,
            descriptor: Echo_Echo.Method.Get.descriptor,
            serializer: serializer,
            deserializer: deserializer,
            options: options,
            handler: body
        )
    }
    
    /// Splits a request into words and returns each word in a stream of messages.
    internal func expand<R>(
        request: GRPCCore.ClientRequest.Single<Echo_EchoRequest>,
        serializer: some GRPCCore.MessageSerializer<Echo_EchoRequest>,
        deserializer: some GRPCCore.MessageDeserializer<Echo_EchoResponse>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<Echo_EchoResponse>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.client.serverStreaming(
            request: request,
            descriptor: Echo_Echo.Method.Expand.descriptor,
            serializer: serializer,
            deserializer: deserializer,
            options: options,
            handler: body
        )
    }
    
    /// Collects a stream of messages and returns them concatenated when the caller closes.
    internal func collect<R>(
        request: GRPCCore.ClientRequest.Stream<Echo_EchoRequest>,
        serializer: some GRPCCore.MessageSerializer<Echo_EchoRequest>,
        deserializer: some GRPCCore.MessageDeserializer<Echo_EchoResponse>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<Echo_EchoResponse>) async throws -> R = {
            try $0.message
        }
    ) async throws -> R where R: Sendable {
        try await self.client.clientStreaming(
            request: request,
            descriptor: Echo_Echo.Method.Collect.descriptor,
            serializer: serializer,
            deserializer: deserializer,
            options: options,
            handler: body
        )
    }
    
    /// Streams back messages as they are received in an input stream.
    internal func update<R>(
        request: GRPCCore.ClientRequest.Stream<Echo_EchoRequest>,
        serializer: some GRPCCore.MessageSerializer<Echo_EchoRequest>,
        deserializer: some GRPCCore.MessageDeserializer<Echo_EchoResponse>,
        options: GRPCCore.CallOptions = .defaults,
        _ body: @Sendable @escaping (GRPCCore.ClientResponse.Stream<Echo_EchoResponse>) async throws -> R
    ) async throws -> R where R: Sendable {
        try await self.client.bidirectionalStreaming(
            request: request,
            descriptor: Echo_Echo.Method.Update.descriptor,
            serializer: serializer,
            deserializer: deserializer,
            options: options,
            handler: body
        )
    }
}