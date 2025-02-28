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

/// Creates a representation for the server and client code, as well as for the enums containing useful type aliases and properties.
/// The representation is generated based on the ``CodeGenerationRequest`` object and user specifications,
/// using types from ``StructuredSwiftRepresentation``.
package struct IDLToStructuredSwiftTranslator {
  package init() {}

  func translate(
    codeGenerationRequest: CodeGenerationRequest,
    accessLevel: CodeGenerator.Config.AccessLevel,
    accessLevelOnImports: Bool,
    client: Bool,
    server: Bool,
    grpcCoreModuleName: String
  ) throws -> StructuredSwiftRepresentation {
    try self.validateInput(codeGenerationRequest)
    let accessModifier = AccessModifier(accessLevel)

    var codeBlocks: [CodeBlock] = []
    let metadataTranslator = MetadataTranslator()
    let serverTranslator = ServerCodeTranslator()
    let clientTranslator = ClientCodeTranslator()

    let namer = Namer(grpcCore: grpcCoreModuleName)

    for service in codeGenerationRequest.services {
      codeBlocks.append(
        CodeBlock(comment: .mark("\(service.name.identifyingName)", sectionBreak: true))
      )

      let metadata = metadataTranslator.translate(
        accessModifier: accessModifier,
        service: service,
        namer: namer
      )
      codeBlocks.append(contentsOf: metadata)

      if server {
        codeBlocks.append(
          CodeBlock(comment: .mark("\(service.name.identifyingName) (server)", sectionBreak: false))
        )

        let blocks = serverTranslator.translate(
          accessModifier: accessModifier,
          service: service,
          namer: namer,
          serializer: codeGenerationRequest.makeSerializerCodeSnippet,
          deserializer: codeGenerationRequest.makeDeserializerCodeSnippet
        )
        codeBlocks.append(contentsOf: blocks)
      }

      if client {
        codeBlocks.append(
          CodeBlock(comment: .mark("\(service.name.identifyingName) (client)", sectionBreak: false))
        )
        let blocks = clientTranslator.translate(
          accessModifier: accessModifier,
          service: service,
          namer: namer,
          serializer: codeGenerationRequest.makeSerializerCodeSnippet,
          deserializer: codeGenerationRequest.makeDeserializerCodeSnippet
        )
        codeBlocks.append(contentsOf: blocks)
      }
    }

    let imports: [ImportDescription]?
    if codeGenerationRequest.services.isEmpty {
      imports = nil
      codeBlocks.append(
        CodeBlock(comment: .inline("This file contained no services."))
      )
    } else {
      imports = try self.makeImports(
        dependencies: codeGenerationRequest.dependencies,
        accessLevel: accessLevel,
        accessLevelOnImports: accessLevelOnImports,
        grpcCoreModuleName: grpcCoreModuleName
      )
    }

    let fileDescription = FileDescription(
      topComment: .preFormatted(codeGenerationRequest.leadingTrivia),
      imports: imports,
      codeBlocks: codeBlocks
    )

    let fileName = String(codeGenerationRequest.fileName.split(separator: ".")[0])
    let file = NamedFileDescription(name: fileName, contents: fileDescription)
    return StructuredSwiftRepresentation(file: file)
  }

  package func makeImports(
    dependencies: [Dependency],
    accessLevel: CodeGenerator.Config.AccessLevel,
    accessLevelOnImports: Bool,
    grpcCoreModuleName: String
  ) throws -> [ImportDescription] {
    var imports: [ImportDescription] = []
    imports.append(
      ImportDescription(
        accessLevel: accessLevelOnImports ? AccessModifier(accessLevel) : nil,
        moduleName: grpcCoreModuleName
      )
    )

    for dependency in dependencies {
      let importDescription = try self.translateImport(
        dependency: dependency,
        accessLevelOnImports: accessLevelOnImports
      )
      imports.append(importDescription)
    }

    return imports
  }
}

extension AccessModifier {
  init(_ accessLevel: CodeGenerator.Config.AccessLevel) {
    switch accessLevel.level {
    case .internal: self = .internal
    case .package: self = .package
    case .public: self = .public
    }
  }
}

extension IDLToStructuredSwiftTranslator {
  private func translateImport(
    dependency: Dependency,
    accessLevelOnImports: Bool
  ) throws -> ImportDescription {
    var importDescription = ImportDescription(
      accessLevel: accessLevelOnImports ? AccessModifier(dependency.accessLevel) : nil,
      moduleName: dependency.module
    )
    if let item = dependency.item {
      if let matchedKind = ImportDescription.Kind(rawValue: item.kind.value.rawValue) {
        importDescription.item = ImportDescription.Item(kind: matchedKind, name: item.name)
      } else {
        throw CodeGenError(
          code: .invalidKind,
          message: "Invalid kind name for import: \(item.kind.value.rawValue)"
        )
      }
    }
    if let spi = dependency.spi {
      importDescription.spi = spi
    }

    switch dependency.preconcurrency.value {
    case .required:
      importDescription.preconcurrency = .always
    case .notRequired:
      importDescription.preconcurrency = .never
    case .requiredOnOS(let OSs):
      importDescription.preconcurrency = .onOS(OSs)
    }
    return importDescription
  }

  private func validateInput(_ codeGenerationRequest: CodeGenerationRequest) throws {
    try self.checkServiceDescriptorsAreUnique(codeGenerationRequest.services)

    let servicesByGeneratedEnumName = Dictionary(
      grouping: codeGenerationRequest.services,
      by: { $0.name.typeName }
    )
    try self.checkServiceEnumNamesAreUnique(for: servicesByGeneratedEnumName)

    for service in codeGenerationRequest.services {
      try self.checkMethodNamesAreUnique(in: service)
    }
  }

  // Verify service enum names are unique.
  private func checkServiceEnumNamesAreUnique(
    for servicesByGeneratedEnumName: [String: [ServiceDescriptor]]
  ) throws {
    for (generatedEnumName, services) in servicesByGeneratedEnumName {
      if services.count > 1 {
        throw CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            There must be a unique (namespace, service_name) pair for each service. \
            \(generatedEnumName) is used as a <namespace>_<service_name> construction for multiple services.
            """
        )
      }
    }
  }

  // Verify method names are unique within a service.
  private func checkMethodNamesAreUnique(
    in service: ServiceDescriptor
  ) throws {
    // Check that the method descriptors are unique, by checking that the base names
    // of the methods of a specific service are unique.
    let baseNames = service.methods.map { $0.name.identifyingName }
    if let duplicatedBase = baseNames.getFirstDuplicate() {
      throw CodeGenError(
        code: .nonUniqueMethodName,
        message: """
          Methods of a service must have unique base names. \
          \(duplicatedBase) is used as a base name for multiple methods of the \(service.name.identifyingName) service.
          """
      )
    }

    // Check that generated upper case names for methods are unique within a service, to ensure that
    // the enums containing type aliases for each method of a service.
    let upperCaseNames = service.methods.map { $0.name.typeName }
    if let duplicatedGeneratedUpperCase = upperCaseNames.getFirstDuplicate() {
      throw CodeGenError(
        code: .nonUniqueMethodName,
        message: """
          Methods of a service must have unique generated upper case names. \
          \(duplicatedGeneratedUpperCase) is used as a generated upper case name for multiple methods of the \(service.name.identifyingName) service.
          """
      )
    }

    // Check that generated lower case names for methods are unique within a service, to ensure that
    // the function declarations and definitions from the same protocols and extensions have unique names.
    let lowerCaseNames = service.methods.map { $0.name.functionName }
    if let duplicatedLowerCase = lowerCaseNames.getFirstDuplicate() {
      throw CodeGenError(
        code: .nonUniqueMethodName,
        message: """
          Methods of a service must have unique lower case names. \
          \(duplicatedLowerCase) is used as a signature name for multiple methods of the \(service.name.identifyingName) service.
          """
      )
    }
  }

  private func checkServiceDescriptorsAreUnique(
    _ services: [ServiceDescriptor]
  ) throws {
    var descriptors: Set<String> = []
    for service in services {
      let name = service.name.identifyingName
      let (inserted, _) = descriptors.insert(name)
      if !inserted {
        throw CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            Services must have unique descriptors. \
            \(name) is the descriptor of at least two different services.
            """
        )
      }
    }
  }
}

extension [String] {
  internal func getFirstDuplicate() -> String? {
    var seen = Set<String>()
    for element in self {
      if seen.contains(element) {
        return element
      }
      seen.insert(element)
    }
    return nil
  }
}
