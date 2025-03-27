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
    availability: AvailabilityDescription,
    namer: Namer = Namer(),
    serializer: (String) -> String,
    deserializer: (String) -> String
  ) -> [CodeBlock] {
    var blocks = [CodeBlock]()

    let `extension` = ExtensionDescription(
      onType: service.name.typeName,
      declarations: [
        // protocol StreamingServiceProtocol { ... }
        .commentable(
          .preFormatted(
            Docs.suffix(
              self.streamingServiceDocs(serviceName: service.name.identifyingName),
              withDocs: service.documentation
            )
          ),
          .protocol(
            .streamingService(
              accessLevel: accessModifier,
              name: "StreamingServiceProtocol",
              methods: service.methods,
              namer: namer
            )
          )
        ),

        // protocol ServiceProtocol { ... }
        .commentable(
          .preFormatted(
            Docs.suffix(
              self.serviceDocs(serviceName: service.name.identifyingName),
              withDocs: service.documentation
            )
          ),
          .protocol(
            .service(
              accessLevel: accessModifier,
              name: "ServiceProtocol",
              streamingProtocol: "\(service.name.typeName).StreamingServiceProtocol",
              methods: service.methods,
              namer: namer
            )
          )
        ),

        // protocol SimpleServiceProtocol { ... }
        .commentable(
          .preFormatted(
            Docs.suffix(
              self.simpleServiceDocs(serviceName: service.name.identifyingName),
              withDocs: service.documentation
            )
          ),
          .protocol(
            .simpleServiceProtocol(
              accessModifier: accessModifier,
              name: "SimpleServiceProtocol",
              serviceProtocol: "\(service.name.typeName).ServiceProtocol",
              methods: service.methods,
              namer: namer
            )
          )
        ),
      ]
    )
    blocks.append(.declaration(.guarded(availability, .extension(`extension`))))

    // extension <Service>.StreamingServiceProtocol> { ... }
    let registerExtension: ExtensionDescription = .registrableRPCServiceDefaultImplementation(
      accessLevel: accessModifier,
      on: "\(service.name.typeName).StreamingServiceProtocol",
      serviceNamespace: service.name.typeName,
      methods: service.methods,
      namer: namer,
      serializer: serializer,
      deserializer: deserializer
    )
    blocks.append(
      CodeBlock(
        comment: .inline("Default implementation of 'registerMethods(with:)'."),
        item: .declaration(.guarded(availability, .extension(registerExtension)))
      )
    )

    // extension <Service>_ServiceProtocol { ... }
    let streamingServiceDefaultImplExtension: ExtensionDescription =
      .streamingServiceProtocolDefaultImplementation(
        accessModifier: accessModifier,
        on: "\(service.name.typeName).ServiceProtocol",
        methods: service.methods,
        namer: namer
      )
    blocks.append(
      CodeBlock(
        comment: .inline(
          "Default implementation of streaming methods from 'StreamingServiceProtocol'."
        ),
        item: .declaration(.guarded(availability, .extension(streamingServiceDefaultImplExtension)))
      )
    )

    // extension <Service>_SimpleServiceProtocol { ... }
    let serviceDefaultImplExtension: ExtensionDescription = .serviceProtocolDefaultImplementation(
      accessModifier: accessModifier,
      on: "\(service.name.typeName).SimpleServiceProtocol",
      methods: service.methods,
      namer: namer
    )
    blocks.append(
      CodeBlock(
        comment: .inline("Default implementation of methods from 'ServiceProtocol'."),
        item: .declaration(.guarded(availability, .extension(serviceDefaultImplExtension)))
      )
    )

    return blocks
  }

  private func streamingServiceDocs(serviceName: String) -> String {
    return """
      /// Streaming variant of the service protocol for the "\(serviceName)" service.
      ///
      /// This protocol is the lowest-level of the service protocols generated for this service
      /// giving you the most flexibility over the implementation of your service. This comes at
      /// the cost of more verbose and less strict APIs. Each RPC requires you to implement it in
      /// terms of a request stream and response stream. Where only a single request or response
      /// message is expected, you are responsible for enforcing this invariant is maintained.
      ///
      /// Where possible, prefer using the stricter, less-verbose ``ServiceProtocol``
      /// or ``SimpleServiceProtocol`` instead.
      """
  }

  private func serviceDocs(serviceName: String) -> String {
    return """
      /// Service protocol for the "\(serviceName)" service.
      ///
      /// This protocol is higher level than ``StreamingServiceProtocol`` but lower level than
      /// the ``SimpleServiceProtocol``, it provides access to request and response metadata and
      /// trailing response metadata. If you don't need these then consider using
      /// the ``SimpleServiceProtocol``. If you need fine grained control over your RPCs then
      /// use ``StreamingServiceProtocol``.
      """
  }

  private func simpleServiceDocs(serviceName: String) -> String {
    return """
      /// Simple service protocol for the "\(serviceName)" service.
      ///
      /// This is the highest level protocol for the service. The API is the easiest to use but
      /// doesn't provide access to request or response metadata. If you need access to these
      /// then use ``ServiceProtocol`` instead.
      """
  }
}
