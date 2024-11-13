/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

#if os(macOS) || os(Linux)  // swift-format doesn't like canImport(Foundation.Process)

import XCTest

@testable import GRPCCodeGen

final class ClientCodeTranslatorSnippetBasedTests: XCTestCase {
  func testClientCodeTranslatorUnaryMethod() throws {
    let method = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(base: "namespaceA", generatedUpperCase: "NamespaceA", generatedLowerCase: ""),
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceA_ClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          public func methodA<R>(
              request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          /// Documentation for MethodA
          public func methodA<Result>(
              _ message: NamespaceA_ServiceARequest,
              metadata: GRPCCore.Metadata = [:],
              options: GRPCCore.CallOptions = .defaults,
              onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result = {
                  try $0.message
              }
          ) async throws -> Result where Result: Sendable {
              let request = GRPCCore.ClientRequest<NamespaceA_ServiceARequest>(
                  message: message,
                  metadata: metadata
              )
              return try await self.methodA(
                  request: request,
                  options: options,
                  handleResponse
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct NamespaceA_ServiceA_Client: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(wrapping client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          public func methodA<R>(
              request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.client.unary(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  func testClientCodeTranslatorClientStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: true,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(base: "namespaceA", generatedUpperCase: "NamespaceA", generatedLowerCase: ""),
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceA_ClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          public func methodA<R>(
              request: GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          /// Documentation for MethodA
          public func methodA<Result>(
              metadata: GRPCCore.Metadata = [:],
              options: GRPCCore.CallOptions = .defaults,
              requestProducer: @Sendable @escaping (GRPCCore.RPCWriter<NamespaceA_ServiceARequest>) async throws -> Void,
              onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result = {
                  try $0.message
              }
          ) async throws -> Result where Result: Sendable {
              let request = GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>(
                  metadata: metadata,
                  producer: requestProducer
              )
              return try await self.methodA(
                  request: request,
                  options: options,
                  handleResponse
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct NamespaceA_ServiceA_Client: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(wrapping client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          public func methodA<R>(
              request: GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.client.clientStreaming(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  func testClientCodeTranslatorServerStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(base: "namespaceA", generatedUpperCase: "NamespaceA", generatedLowerCase: ""),
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceA_ClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions,
              _ body: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          public func methodA<R>(
              request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          /// Documentation for MethodA
          public func methodA<Result>(
              _ message: NamespaceA_ServiceARequest,
              metadata: GRPCCore.Metadata = [:],
              options: GRPCCore.CallOptions = .defaults,
              onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result
          ) async throws -> Result where Result: Sendable {
              let request = GRPCCore.ClientRequest<NamespaceA_ServiceARequest>(
                  message: message,
                  metadata: metadata
              )
              return try await self.methodA(
                  request: request,
                  options: options,
                  handleResponse
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct NamespaceA_ServiceA_Client: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(wrapping client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          public func methodA<R>(
              request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.serverStreaming(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  func testClientCodeTranslatorBidirectionalStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: true,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(base: "namespaceA", generatedUpperCase: "NamespaceA", generatedLowerCase: ""),
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceA_ClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions,
              _ body: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          public func methodA<R>(
              request: GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          /// Documentation for MethodA
          public func methodA<Result>(
              metadata: GRPCCore.Metadata = [:],
              options: GRPCCore.CallOptions = .defaults,
              requestProducer: @Sendable @escaping (GRPCCore.RPCWriter<NamespaceA_ServiceARequest>) async throws -> Void,
              onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result
          ) async throws -> Result where Result: Sendable {
              let request = GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>(
                  metadata: metadata,
                  producer: requestProducer
              )
              return try await self.methodA(
                  request: request,
                  options: options,
                  handleResponse
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct NamespaceA_ServiceA_Client: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(wrapping client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          public func methodA<R>(
              request: GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.bidirectionalStreaming(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  func testClientCodeTranslatorMultipleMethod() throws {
    let methodA = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: true,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let methodB = MethodDescriptor(
      documentation: "/// Documentation for MethodB",
      name: Name(base: "MethodB", generatedUpperCase: "MethodB", generatedLowerCase: "methodB"),
      isInputStreaming: false,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(base: "namespaceA", generatedUpperCase: "NamespaceA", generatedLowerCase: ""),
      methods: [methodA, methodB]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      package protocol NamespaceA_ServiceA_ClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
          
          /// Documentation for MethodB
          func methodB<R>(
              request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions,
              _ body: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          package func methodA<R>(
              request: GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
          
          package func methodB<R>(
              request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodB(
                  request: request,
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          /// Documentation for MethodA
          package func methodA<Result>(
              metadata: GRPCCore.Metadata = [:],
              options: GRPCCore.CallOptions = .defaults,
              requestProducer: @Sendable @escaping (GRPCCore.RPCWriter<NamespaceA_ServiceARequest>) async throws -> Void,
              onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result = {
                  try $0.message
              }
          ) async throws -> Result where Result: Sendable {
              let request = GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>(
                  metadata: metadata,
                  producer: requestProducer
              )
              return try await self.methodA(
                  request: request,
                  options: options,
                  handleResponse
              )
          }
          
          /// Documentation for MethodB
          package func methodB<Result>(
              _ message: NamespaceA_ServiceARequest,
              metadata: GRPCCore.Metadata = [:],
              options: GRPCCore.CallOptions = .defaults,
              onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result
          ) async throws -> Result where Result: Sendable {
              let request = GRPCCore.ClientRequest<NamespaceA_ServiceARequest>(
                  message: message,
                  metadata: metadata
              )
              return try await self.methodB(
                  request: request,
                  options: options,
                  handleResponse
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      package struct NamespaceA_ServiceA_Client: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          package init(wrapping client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          package func methodA<R>(
              request: GRPCCore.StreamingClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.client.clientStreaming(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
          
          /// Documentation for MethodB
          package func methodB<R>(
              request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.StreamingClientResponse<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.serverStreaming(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodB.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .package
    )
  }

  func testClientCodeTranslatorNoNamespaceService() throws {
    let method = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "ServiceARequest",
      outputType: "ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(base: "", generatedUpperCase: "", generatedLowerCase: ""),
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      internal protocol ServiceA_ClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: GRPCCore.ClientRequest<ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<ServiceAResponse>,
              options: GRPCCore.CallOptions,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension ServiceA.ClientProtocol {
          internal func methodA<R>(
              request: GRPCCore.ClientRequest<ServiceARequest>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: GRPCProtobuf.ProtobufSerializer<ServiceARequest>(),
                  deserializer: GRPCProtobuf.ProtobufDeserializer<ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension ServiceA.ClientProtocol {
          /// Documentation for MethodA
          internal func methodA<Result>(
              _ message: ServiceARequest,
              metadata: GRPCCore.Metadata = [:],
              options: GRPCCore.CallOptions = .defaults,
              onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<ServiceAResponse>) async throws -> Result = {
                  try $0.message
              }
          ) async throws -> Result where Result: Sendable {
              let request = GRPCCore.ClientRequest<ServiceARequest>(
                  message: message,
                  metadata: metadata
              )
              return try await self.methodA(
                  request: request,
                  options: options,
                  handleResponse
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      internal struct ServiceA_Client: ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          internal init(wrapping client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          internal func methodA<R>(
              request: GRPCCore.ClientRequest<ServiceARequest>,
              serializer: some GRPCCore.MessageSerializer<ServiceARequest>,
              deserializer: some GRPCCore.MessageDeserializer<ServiceAResponse>,
              options: GRPCCore.CallOptions = .defaults,
              _ body: @Sendable @escaping (GRPCCore.ClientResponse<ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.client.unary(
                  request: request,
                  descriptor: ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .internal
    )
  }

  func testClientCodeTranslatorMultipleServices() throws {
    let serviceA = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(
        base: "nammespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: ""
      ),
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: """
        /// Documentation for ServiceB
        ///
        /// Line 2
        """,
      name: Name(base: "ServiceB", generatedUpperCase: "ServiceB", generatedLowerCase: ""),
      namespace: Name(base: "", generatedUpperCase: "", generatedLowerCase: ""),
      methods: []
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceA_ClientProtocol: Sendable {}
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct NamespaceA_ServiceA_Client: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(wrapping client: GRPCCore.GRPCClient) {
              self.client = client
          }
      }
      /// Documentation for ServiceB
      ///
      /// Line 2
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol ServiceB_ClientProtocol: Sendable {}
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension ServiceB.ClientProtocol {
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension ServiceB.ClientProtocol {
      }
      /// Documentation for ServiceB
      ///
      /// Line 2
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct ServiceB_Client: ServiceB.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(wrapping client: GRPCCore.GRPCClient) {
              self.client = client
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceA, serviceB]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  private func assertClientCodeTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String,
    accessLevel: SourceGenerator.Config.AccessLevel,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let translator = ClientCodeTranslator(accessLevel: accessLevel)
    let codeBlocks = try translator.translate(from: codeGenerationRequest)
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    let contents = renderer.renderedContents()
    try XCTAssertEqualWithDiff(contents, expectedSwift, file: file, line: line)
  }
}

#endif  // os(macOS) || os(Linux)
