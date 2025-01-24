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

import Testing

@testable import GRPCCodeGen

@Suite
struct ClientCodeTranslatorSnippetBasedTests {
  @Test
  func translate() {
    let method = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: MethodName(identifyingName: "MethodA", typeName: "MethodA", functionName: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )

    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: ServiceName(
        identifyingName: "namespaceA.ServiceA",
        typeName: "NamespaceA_ServiceA",
        propertyName: ""
      ),
      methods: [method]
    )

    let expectedSwift = """
      extension NamespaceA_ServiceA {
          /// Generated client protocol for the "namespaceA.ServiceA" service.
          ///
          /// You don't need to implement this protocol directly, use the generated
          /// implementation, ``Client``.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Documentation for ServiceA
          public protocol ClientProtocol: Sendable {
              /// Call the "MethodA" method.
              ///
              /// > Source IDL Documentation:
              /// >
              /// > Documentation for MethodA
              ///
              /// - Parameters:
              ///   - request: A request containing a single `NamespaceA_ServiceARequest` message.
              ///   - serializer: A serializer for `NamespaceA_ServiceARequest` messages.
              ///   - deserializer: A deserializer for `NamespaceA_ServiceAResponse` messages.
              ///   - options: Options to apply to this RPC.
              ///   - handleResponse: A closure which handles the response, the result of which is
              ///       returned to the caller. Returning from the closure will cancel the RPC if it
              ///       hasn't already finished.
              /// - Returns: The result of `handleResponse`.
              func methodA<Result>(
                  request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
                  serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
                  deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
                  options: GRPCCore.CallOptions,
                  onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result
              ) async throws -> Result where Result: Sendable
          }

          /// Generated client for the "namespaceA.ServiceA" service.
          ///
          /// The ``Client`` provides an implementation of ``ClientProtocol`` which wraps
          /// a `GRPCCore.GRPCCClient`. The underlying `GRPCClient` provides the long-lived
          /// means of communication with the remote peer.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Documentation for ServiceA
          public struct Client<Transport>: ClientProtocol where Transport: GRPCCore.ClientTransport {
              private let client: GRPCCore.GRPCClient<Transport>

              /// Creates a new client wrapping the provided `GRPCCore.GRPCClient`.
              ///
              /// - Parameters:
              ///   - client: A `GRPCCore.GRPCClient` providing a communication channel to the service.
              public init(wrapping client: GRPCCore.GRPCClient<Transport>) {
                  self.client = client
              }

              /// Call the "MethodA" method.
              ///
              /// > Source IDL Documentation:
              /// >
              /// > Documentation for MethodA
              ///
              /// - Parameters:
              ///   - request: A request containing a single `NamespaceA_ServiceARequest` message.
              ///   - serializer: A serializer for `NamespaceA_ServiceARequest` messages.
              ///   - deserializer: A deserializer for `NamespaceA_ServiceAResponse` messages.
              ///   - options: Options to apply to this RPC.
              ///   - handleResponse: A closure which handles the response, the result of which is
              ///       returned to the caller. Returning from the closure will cancel the RPC if it
              ///       hasn't already finished.
              /// - Returns: The result of `handleResponse`.
              public func methodA<Result>(
                  request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
                  serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
                  deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
                  options: GRPCCore.CallOptions = .defaults,
                  onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result = { response in
                      try response.message
                  }
              ) async throws -> Result where Result: Sendable {
                  try await self.client.unary(
                      request: request,
                      descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                      serializer: serializer,
                      deserializer: deserializer,
                      options: options,
                      onResponse: handleResponse
                  )
              }
          }
      }
      // Helpers providing default arguments to 'ClientProtocol' methods.
      extension NamespaceA_ServiceA.ClientProtocol {
          /// Call the "MethodA" method.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Documentation for MethodA
          ///
          /// - Parameters:
          ///   - request: A request containing a single `NamespaceA_ServiceARequest` message.
          ///   - options: Options to apply to this RPC.
          ///   - handleResponse: A closure which handles the response, the result of which is
          ///       returned to the caller. Returning from the closure will cancel the RPC if it
          ///       hasn't already finished.
          /// - Returns: The result of `handleResponse`.
          public func methodA<Result>(
              request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
              options: GRPCCore.CallOptions = .defaults,
              onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result = { response in
                  try response.message
              }
          ) async throws -> Result where Result: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  onResponse: handleResponse
              )
          }
      }
      // Helpers providing sugared APIs for 'ClientProtocol' methods.
      extension NamespaceA_ServiceA.ClientProtocol {
          /// Call the "MethodA" method.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Documentation for MethodA
          ///
          /// - Parameters:
          ///   - message: request message to send.
          ///   - metadata: Additional metadata to send, defaults to empty.
          ///   - options: Options to apply to this RPC, defaults to `.defaults`.
          ///   - handleResponse: A closure which handles the response, the result of which is
          ///       returned to the caller. Returning from the closure will cancel the RPC if it
          ///       hasn't already finished.
          /// - Returns: The result of `handleResponse`.
          public func methodA<Result>(
              _ message: NamespaceA_ServiceARequest,
              metadata: GRPCCore.Metadata = [:],
              options: GRPCCore.CallOptions = .defaults,
              onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result = { response in
                  try response.message
              }
          ) async throws -> Result where Result: Sendable {
              let request = GRPCCore.ClientRequest<NamespaceA_ServiceARequest>(
                  message: message,
                  metadata: metadata
              )
              return try await self.methodA(
                  request: request,
                  options: options,
                  onResponse: handleResponse
              )
          }
      }
      """

    let rendered = self.render(accessLevel: .public, service: service)
    #expect(rendered == expectedSwift)
  }

  private func render(
    accessLevel: AccessModifier,
    service: ServiceDescriptor
  ) -> String {
    let translator = ClientCodeTranslator()
    let codeBlocks = translator.translate(accessModifier: accessLevel, service: service) {
      "GRPCProtobuf.ProtobufSerializer<\($0)>()"
    } deserializer: {
      "GRPCProtobuf.ProtobufDeserializer<\($0)>()"
    }
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    return renderer.renderedContents()
  }
}
