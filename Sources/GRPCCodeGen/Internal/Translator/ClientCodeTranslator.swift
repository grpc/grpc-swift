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

    let `extension` = ExtensionDescription(
      onType: service.name.typeName,
      declarations: [
        // protocol ClientProtocol { ... }
        .commentable(
          .preFormatted(
            Docs.suffix(
              self.clientProtocolDocs(serviceName: service.name.identifyingName),
              withDocs: service.documentation
            )
          ),
          .protocol(
            .clientProtocol(
              accessLevel: accessModifier,
              name: "ClientProtocol",
              methods: service.methods
            )
          )
        ),

        // struct Client: ClientProtocol { ... }
        .commentable(
          .preFormatted(
            Docs.suffix(
              self.clientDocs(serviceName: service.name.identifyingName),
              withDocs: service.documentation
            )
          ),
          .struct(
            .client(
              accessLevel: accessModifier,
              name: "Client",
              serviceEnum: service.name.typeName,
              clientProtocol: "ClientProtocol",
              methods: service.methods
            )
          )
        ),
      ]
    )
    blocks.append(.declaration(.extension(`extension`)))

    let extensionWithDefaults: ExtensionDescription = .clientMethodSignatureWithDefaults(
      accessLevel: accessModifier,
      name: "\(service.name.typeName).ClientProtocol",
      methods: service.methods,
      serializer: serializer,
      deserializer: deserializer
    )
    blocks.append(
      CodeBlock(
        comment: .inline("Helpers providing default arguments to 'ClientProtocol' methods."),
        item: .declaration(.extension(extensionWithDefaults))
      )
    )

    let extensionWithExplodedAPI: ExtensionDescription = .explodedClientMethods(
      accessLevel: accessModifier,
      on: "\(service.name.typeName).ClientProtocol",
      methods: service.methods
    )
    blocks.append(
      CodeBlock(
        comment: .inline("Helpers providing sugared APIs for 'ClientProtocol' methods."),
        item: .declaration(.extension(extensionWithExplodedAPI))
      )
    )

    return blocks
  }

  private func clientProtocolDocs(serviceName: String) -> String {
    return """
      /// Generated client protocol for the "\(serviceName)" service.
      ///
      /// You don't need to implement this protocol directly, use the generated
      /// implementation, ``Client``.
      """
  }

  private func clientDocs(serviceName: String) -> String {
    return """
      /// Generated client for the "\(serviceName)" service.
      ///
      /// The ``Client`` provides an implementation of ``ClientProtocol`` which wraps
      /// a `GRPCCore.GRPCCClient`. The underlying `GRPCClient` provides the long-lived
      /// means of communication with the remote peer.
      """
  }
}
