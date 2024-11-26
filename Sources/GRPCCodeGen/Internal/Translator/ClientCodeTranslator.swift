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

/// Creates a representation for the client code that will be generated based on the ``CodeGenerationRequest`` object
/// specifications, using types from ``StructuredSwiftRepresentation``.
///
/// For example, in the case of a service called "Bar", in the "foo" namespace which has
/// one method "baz" with input type "Input" and output type "Output", the ``ClientCodeTranslator`` will create
/// a representation for the following generated code:
///
/// ```swift
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// public protocol Foo_BarClientProtocol: Sendable {
///   func baz<R>(
///     request: GRPCCore.ClientRequest<Foo_Bar_Input>,
///     serializer: some GRPCCore.MessageSerializer<Foo_Bar_Input>,
///     deserializer: some GRPCCore.MessageDeserializer<Foo_Bar_Output>,
///     options: GRPCCore.CallOptions = .defaults,
///     _ body: @Sendable @escaping (GRPCCore.ClientResponse<Foo_Bar_Output>) async throws -> R
///   ) async throws -> R where R: Sendable
/// }
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// extension Foo_Bar.ClientProtocol {
///   public func baz<R>(
///     request: GRPCCore.ClientRequest<Foo_Bar_Input>,
///     options: GRPCCore.CallOptions = .defaults,
///     _ body: @Sendable @escaping (GRPCCore.ClientResponse<Foo_Bar_Output>) async throws -> R = {
///       try $0.message
///     }
///   ) async throws -> R where R: Sendable {
///     try await self.baz(
///       request: request,
///       serializer: GRPCProtobuf.ProtobufSerializer<Foo_Bar_Input>(),
///       deserializer: GRPCProtobuf.ProtobufDeserializer<Foo_Bar_Output>(),
///       options: options,
///       body
///     )
/// }
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// public struct Foo_BarClient: Foo_Bar.ClientProtocol {
///   private let client: GRPCCore.GRPCClient
///   public init(wrapping client: GRPCCore.GRPCClient) {
///     self.client = client
///   }
///   public func methodA<R>(
///     request: GRPCCore.StreamingClientRequest<Foo_Bar_Input>,
///     serializer: some GRPCCore.MessageSerializer<Foo_Bar_Input>,
///     deserializer: some GRPCCore.MessageDeserializer<Foo_Bar_Output>,
///     options: GRPCCore.CallOptions = .defaults,
///     _ body: @Sendable @escaping (GRPCCore.ClientResponse<Foo_Bar_Output>) async throws -> R = {
///       try $0.message
///     }
///   ) async throws -> R where R: Sendable {
///     try await self.client.unary(
///       request: request,
///       descriptor: NamespaceA.ServiceA.Method.MethodA.descriptor,
///       serializer: serializer,
///       deserializer: deserializer,
///       options: options,
///       handler: body
///     )
///   }
/// }
///```
struct ClientCodeTranslator {
  init() {}

  func translate(
    accessModifier: AccessModifier,
    service: ServiceDescriptor,
    serializer: (String) -> String,
    deserializer: (String) -> String
  ) -> [CodeBlock] {
    var blocks = [CodeBlock]()

    let protocolName = "\(service.namespacedGeneratedName)_ClientProtocol"
    let protocolTypealias = "\(service.namespacedGeneratedName).ClientProtocol"
    let structName = "\(service.namespacedGeneratedName)_Client"

    let clientProtocol: ProtocolDescription = .clientProtocol(
      accessLevel: accessModifier,
      name: protocolName,
      methods: service.methods
    )
    blocks.append(
      CodeBlock(
        comment: .preFormatted(service.documentation),
        item: .declaration(.protocol(clientProtocol))
      )
    )

    let extensionWithDefaults: ExtensionDescription = .clientMethodSignatureWithDefaults(
      accessLevel: accessModifier,
      name: protocolTypealias,
      methods: service.methods,
      serializer: serializer,
      deserializer: deserializer
    )
    blocks.append(
      CodeBlock(item: .declaration(.extension(extensionWithDefaults)))
    )

    let extensionWithExplodedAPI: ExtensionDescription = .explodedClientMethods(
      accessLevel: accessModifier,
      on: protocolTypealias,
      methods: service.methods
    )
    blocks.append(
      CodeBlock(item: .declaration(.extension(extensionWithExplodedAPI)))
    )

    let clientStruct: StructDescription = .client(
      accessLevel: accessModifier,
      name: structName,
      serviceEnum: service.namespacedGeneratedName,
      clientProtocol: protocolTypealias,
      methods: service.methods
    )
    blocks.append(
      CodeBlock(
        comment: .preFormatted(service.documentation),
        item: .declaration(.struct(clientStruct))
      )
    )

    return blocks
  }
}
