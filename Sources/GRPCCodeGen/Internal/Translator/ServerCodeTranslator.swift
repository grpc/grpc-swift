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

/// Creates a representation for the server code that will be generated based on the ``CodeGenerationRequest`` object
/// specifications, using types from ``StructuredSwiftRepresentation``.
///
/// For example, in the case of a service called "Bar", in the "foo" namespace which has
/// one method "baz" with input type "Input" and output type "Output", the ``ServerCodeTranslator`` will create
/// a representation for the following generated code:
///
/// ```swift
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// public protocol Foo_BarStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
///   func baz(
///     request: GRPCCore.StreamingServerRequest<Foo_Bar_Input>
///   ) async throws -> GRPCCore.StreamingServerResponse<Foo_Bar_Output>
/// }
/// // Conformance to `GRPCCore.RegistrableRPCService`.
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// extension Foo_Bar.StreamingServiceProtocol {
///   public func registerMethods(with router: inout GRPCCore.RPCRouter) {
///     router.registerHandler(
///       forMethod: Foo_Bar.Method.baz.descriptor,
///       deserializer: GRPCProtobuf.ProtobufDeserializer<Foo_Bar_Input>(),
///       serializer: GRPCProtobuf.ProtobufSerializer<Foo_Bar_Output>(),
///       handler: { request in try await self.baz(request: request) }
///     )
///   }
/// }
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// public protocol Foo_BarServiceProtocol: Foo_Bar.StreamingServiceProtocol {
///   func baz(
///     request: GRPCCore.ServerRequest<Foo_Bar_Input>
///   ) async throws -> GRPCCore.ServerResponse<Foo_Bar_Output>
/// }
/// // Partial conformance to `Foo_BarStreamingServiceProtocol`.
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// extension Foo_Bar.ServiceProtocol {
///   public func baz(
///     request: GRPCCore.StreamingServerRequest<Foo_Bar_Input>
///   ) async throws -> GRPCCore.StreamingServerResponse<Foo_Bar_Output> {
///     let response = try await self.baz(request: GRPCCore.ServerRequest(stream: request))
///     return GRPCCore.StreamingServerResponse(single: response)
///   }
/// }
///```
struct ServerCodeTranslator {
  init() {}

  func translate(
    accessModifier: AccessModifier,
    service: ServiceDescriptor,
    serializer: (String) -> String,
    deserializer: (String) -> String
  ) -> [CodeBlock] {
    var blocks = [CodeBlock]()

    let serviceProtocolName = self.protocolName(service: service, streaming: false)
    let serviceTypealiasName = self.protocolName(
      service: service,
      streaming: false,
      joinedUsing: "."
    )
    let streamingServiceProtocolName = self.protocolName(service: service, streaming: true)
    let streamingServiceTypealiasName = self.protocolName(
      service: service,
      streaming: true,
      joinedUsing: "."
    )

    // protocol <Service>_StreamingServiceProtocol { ... }
    let streamingServiceProtocol: ProtocolDescription = .streamingService(
      accessLevel: accessModifier,
      name: streamingServiceProtocolName,
      methods: service.methods
    )
    blocks.append(
      CodeBlock(
        comment: .preFormatted(service.documentation),
        item: .declaration(.protocol(streamingServiceProtocol))
      )
    )

    // extension <Service>_StreamingServiceProtocol> { ... }
    let registerExtension: ExtensionDescription = .registrableRPCServiceDefaultImplementation(
      accessLevel: accessModifier,
      on: streamingServiceTypealiasName,
      serviceNamespace: service.namespacedGeneratedName,
      methods: service.methods,
      serializer: serializer,
      deserializer: deserializer
    )
    blocks.append(
      CodeBlock(
        comment: .doc("Conformance to `GRPCCore.RegistrableRPCService`."),
        item: .declaration(.extension(registerExtension))
      )
    )

    // protocol <Service>_ServiceProtocol { ... }
    let serviceProtocol: ProtocolDescription = .service(
      accessLevel: accessModifier,
      name: serviceProtocolName,
      streamingProtocol: streamingServiceTypealiasName,
      methods: service.methods
    )
    blocks.append(
      CodeBlock(
        comment: .preFormatted(service.documentation),
        item: .declaration(.protocol(serviceProtocol))
      )
    )

    // extension <Service>_ServiceProtocol { ... }
    let streamingServiceDefaultImplExtension: ExtensionDescription =
      .streamingServiceProtocolDefaultImplementation(
        accessModifier: accessModifier,
        on: serviceTypealiasName,
        methods: service.methods
      )
    blocks.append(
      CodeBlock(
        comment: .doc("Partial conformance to `\(streamingServiceProtocolName)`."),
        item: .declaration(.extension(streamingServiceDefaultImplExtension))
      )
    )

    return blocks
  }

  private func protocolName(
    service: ServiceDescriptor,
    streaming: Bool,
    joinedUsing join: String = "_"
  ) -> String {
    if streaming {
      return "\(service.namespacedGeneratedName)\(join)StreamingServiceProtocol"
    }
    return "\(service.namespacedGeneratedName)\(join)ServiceProtocol"
  }
}
