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
struct IDLToStructuredSwiftTranslator: Translator {
  func translate(
    codeGenerationRequest: CodeGenerationRequest,
    accessLevel: SourceGenerator.Configuration.AccessLevel,
    client: Bool,
    server: Bool
  ) throws -> StructuredSwiftRepresentation {
    try self.validateInput(codeGenerationRequest)
    let typealiasTranslator = TypealiasTranslator(
      client: client,
      server: server,
      accessLevel: accessLevel
    )

    let topComment = Comment.preFormatted(codeGenerationRequest.leadingTrivia)
    let imports = try codeGenerationRequest.dependencies.reduce(
      into: [ImportDescription(moduleName: "GRPCCore")]
    ) { partialResult, newDependency in
      try partialResult.append(translateImport(dependency: newDependency))
    }

    var codeBlocks = [CodeBlock]()
    codeBlocks.append(
      contentsOf: try typealiasTranslator.translate(from: codeGenerationRequest)
    )

    if server {
      let serverCodeTranslator = ServerCodeTranslator(accessLevel: accessLevel)
      codeBlocks.append(
        contentsOf: try serverCodeTranslator.translate(from: codeGenerationRequest)
      )
    }

    if client {
      let clientCodeTranslator = ClientCodeTranslator(accessLevel: accessLevel)
      codeBlocks.append(
        contentsOf: try clientCodeTranslator.translate(from: codeGenerationRequest)
      )
    }

    let fileDescription = FileDescription(
      topComment: topComment,
      imports: imports,
      codeBlocks: codeBlocks
    )
    let fileName = String(codeGenerationRequest.fileName.split(separator: ".")[0])
    let file = NamedFileDescription(name: fileName, contents: fileDescription)
    return StructuredSwiftRepresentation(file: file)
  }
}

extension IDLToStructuredSwiftTranslator {
  private func translateImport(
    dependency: CodeGenerationRequest.Dependency
  ) throws -> ImportDescription {
    var importDescription = ImportDescription(moduleName: dependency.module)
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

    let servicesByUpperCaseNamespace = Dictionary(
      grouping: codeGenerationRequest.services,
      by: { $0.namespace.generatedUpperCase }
    )
    try self.checkServiceNamesAreUnique(for: servicesByUpperCaseNamespace)

    for service in codeGenerationRequest.services {
      try self.checkMethodNamesAreUnique(in: service)
    }
  }

  // Verify service names are unique within each namespace and that services with no namespace
  // don't have the same names as any of the namespaces.
  private func checkServiceNamesAreUnique(
    for servicesByUpperCaseNamespace: [String: [CodeGenerationRequest.ServiceDescriptor]]
  ) throws {
    // Check that if there are services in an empty namespace, none have names which match other namespaces,
    // to ensure that there are no enums with the same name in the type aliases part of the generated code.
    if let noNamespaceServices = servicesByUpperCaseNamespace[""] {
      let upperCaseNamespaces = servicesByUpperCaseNamespace.keys
      for service in noNamespaceServices {
        if upperCaseNamespaces.contains(service.name.generatedUpperCase) {
          throw CodeGenError(
            code: .nonUniqueServiceName,
            message: """
              Services with no namespace must not have the same generated upper case names as the namespaces. \
              \(service.name.generatedUpperCase) is used as a generated upper case name for a service with no namespace and a namespace.
              """
          )
        }
      }
    }

    // Check that the generated upper case names for services are unique within each namespace, to ensure that
    // the service enums from each namespace enum have unique names.
    for (namespace, services) in servicesByUpperCaseNamespace {
      var upperCaseNames: Set<String> = []

      for service in services {
        if upperCaseNames.contains(service.name.generatedUpperCase) {
          let errorMessage: String
          if namespace.isEmpty {
            errorMessage = """
              Services in an empty namespace must have unique generated upper case names. \
              \(service.name.generatedUpperCase) is used as a generated upper case name for multiple services without namespaces.
              """
          } else {
            errorMessage = """
              Services within the same namespace must have unique generated upper case names. \
              \(service.name.generatedUpperCase) is used as a generated upper case name for multiple services in the \(service.namespace.base) namespace.
              """
          }
          throw CodeGenError(
            code: .nonUniqueServiceName,
            message: errorMessage
          )
        }
        upperCaseNames.insert(service.name.generatedUpperCase)
      }
    }
  }

  // Verify method names are unique within a service.
  private func checkMethodNamesAreUnique(
    in service: CodeGenerationRequest.ServiceDescriptor
  ) throws {
    // Check that the method descriptors are unique, by checking that the base names
    // of the methods of a specific service are unique.
    let baseNames = service.methods.map { $0.name.base }
    if let duplicatedBase = baseNames.getFirstDuplicate() {
      throw CodeGenError(
        code: .nonUniqueMethodName,
        message: """
          Methods of a service must have unique base names. \
          \(duplicatedBase) is used as a base name for multiple methods of the \(service.name.base) service.
          """
      )
    }

    // Check that generated upper case names for methods are unique within a service, to ensure that
    // the enums containing type aliases for each method of a service.
    let upperCaseNames = service.methods.map { $0.name.generatedUpperCase }
    if let duplicatedGeneratedUpperCase = upperCaseNames.getFirstDuplicate() {
      throw CodeGenError(
        code: .nonUniqueMethodName,
        message: """
          Methods of a service must have unique generated upper case names. \
          \(duplicatedGeneratedUpperCase) is used as a generated upper case name for multiple methods of the \(service.name.base) service.
          """
      )
    }

    // Check that generated lower case names for methods are unique within a service, to ensure that
    // the function declarations and definitions from the same protocols and extensions have unique names.
    let lowerCaseNames = service.methods.map { $0.name.generatedLowerCase }
    if let duplicatedLowerCase = lowerCaseNames.getFirstDuplicate() {
      throw CodeGenError(
        code: .nonUniqueMethodName,
        message: """
          Methods of a service must have unique lower case names. \
          \(duplicatedLowerCase) is used as a signature name for multiple methods of the \(service.name.base) service.
          """
      )
    }
  }

  private func checkServiceDescriptorsAreUnique(
    _ services: [CodeGenerationRequest.ServiceDescriptor]
  ) throws {
    var descriptors: Set<String> = []
    for service in services {
      let name =
        service.namespace.base.isEmpty
        ? service.name.base : "\(service.namespace.base).\(service.name.base)"
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

extension CodeGenerationRequest.ServiceDescriptor {
  var namespacedTypealiasGeneratedName: String {
    if self.namespace.generatedUpperCase.isEmpty {
      return self.name.generatedUpperCase
    } else {
      return "\(self.namespace.generatedUpperCase).\(self.name.generatedUpperCase)"
    }
  }

  var namespacedGeneratedName: String {
    if self.namespace.generatedUpperCase.isEmpty {
      return self.name.generatedUpperCase
    } else {
      return "\(self.namespace.generatedUpperCase)_\(self.name.generatedUpperCase)"
    }
  }

  var fullyQualifiedName: String {
    if self.namespace.base.isEmpty {
      return self.name.base
    } else {
      return "\(self.namespace.base).\(self.name.base)"
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
