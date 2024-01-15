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

struct IDLToStructuredSwiftTranslator: Translator {
  func translate(
    codeGenerationRequest: CodeGenerationRequest,
    client: Bool,
    server: Bool
  ) throws -> StructuredSwiftRepresentation {
    try self.validateInput(codeGenerationRequest)
    let typealiasTranslator = TypealiasTranslator(client: client, server: server)
    let topComment = Comment.doc(codeGenerationRequest.leadingTrivia)
    let imports = try codeGenerationRequest.dependencies.reduce(
      into: [ImportDescription(moduleName: "GRPCCore")]
    ) { partialResult, newDependency in
      try partialResult.append(translateImport(dependency: newDependency))
    }

    var codeBlocks: [CodeBlock] = []
    codeBlocks.append(
      contentsOf: try typealiasTranslator.translate(from: codeGenerationRequest)
    )

    if server {
      let serverCodeTranslator = ServerCodeTranslator()
      codeBlocks.append(
        contentsOf: try serverCodeTranslator.translate(from: codeGenerationRequest)
      )
    }

    if client {
      let clientCodeTranslator = ClientCodeTranslator()
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
    let servicesByGeneratedNamespace = Dictionary(
      grouping: codeGenerationRequest.services,
      by: { $0.generatedNamespace }
    )
    let servicesByNamespace = Dictionary(
      grouping: codeGenerationRequest.services,
      by: { $0.namespace }
    )
    try self.checkServiceNamesAreUnique(for: servicesByGeneratedNamespace)
    try self.checkServicesNamespacesAndGeneratedNamespacesCoincide(
      servicesByNamespace: servicesByNamespace
    )
    try checkEmptyNamespaceAndGeneratedNamespace(for: codeGenerationRequest.services)
    for service in codeGenerationRequest.services {
      try self.checkMethodNamesAreUnique(in: service)
    }
  }

  // Verify service names are unique within each namespace and that services with no namespace
  // don't have the same names as any of the namespaces.
  private func checkServiceNamesAreUnique(
    for servicesByNamespace: [String: [CodeGenerationRequest.ServiceDescriptor]]
  ) throws {
    // Check that if there are services in an empty namespace, none have names which match other namespaces
    if let noNamespaceServices = servicesByNamespace[""] {
      let namespaces = servicesByNamespace.keys
      for service in noNamespaceServices {
        if namespaces.contains(service.generatedName) {
          throw CodeGenError(
            code: .nonUniqueServiceName,
            message: """
              Services with no namespace must not have the same generated names as the namespaces. \
              \(service.generatedName) is used as a generated name for a service with no namespace and a namespace.
              """
          )
        }
      }
    }

    // Check that service names and service generated names are unique within each namespace.
    for (namespace, services) in servicesByNamespace {
      var serviceNames: Set<String> = []
      var generatedNames: Set<String> = []

      for service in services {
        if serviceNames.contains(service.name) {
          let errorMessage: String
          if namespace.isEmpty {
            errorMessage = """
              Services in an empty namespace must have unique names. \
              \(service.name) is used as a name for multiple services without namespaces.
              """
          } else {
            errorMessage = """
              Services within the same namespace must have unique names. \
              \(service.name) is used as a name for multiple services in the \(service.namespace) namespace.
              """
          }
          throw CodeGenError(
            code: .nonUniqueServiceName,
            message: errorMessage
          )
        }
        serviceNames.insert(service.name)

        if generatedNames.contains(service.generatedName) {
          let errorMessage: String
          if namespace.isEmpty {
            errorMessage = """
              Services in an empty namespace must have unique generated names. \
              \(service.generatedName) is used as a name for multiple services without namespaces.
              """
          } else {
            errorMessage = """
              Services within the same namespace must have unique generated names. \
              \(service.generatedName) is used as a generated name for multiple services in the \(service.namespace) namespace.
              """
          }
          throw CodeGenError(
            code: .nonUniqueServiceName,
            message: errorMessage
          )
        }
        generatedNames.insert(service.generatedName)
      }
    }
  }

  // Verify method names are unique for the service.
  private func checkMethodNamesAreUnique(
    in service: CodeGenerationRequest.ServiceDescriptor
  ) throws {
    // Check the method names.
    let methodNames = service.methods.map { $0.name }
    var seenNames = Set<String>()

    for methodName in methodNames {
      if seenNames.contains(methodName) {
        throw CodeGenError(
          code: .nonUniqueMethodName,
          message: """
            Methods of a service must have unique names. \
            \(methodName) is used as a name for multiple methods of the \(service.name) service.
            """
        )
      }
      seenNames.insert(methodName)
    }

    // Check the method generated names.
    let generatedNames = service.methods.map { $0.generatedName }
    var seenGeneratedNames = Set<String>()

    for generatedName in generatedNames {
      if seenGeneratedNames.contains(generatedName) {
        throw CodeGenError(
          code: .nonUniqueMethodName,
          message: """
            Methods of a service must have unique generated names. \
            \(generatedName) is used as a generated name for multiple methods of the \(service.name) service.
            """
        )
      }
      seenGeneratedNames.insert(generatedName)
    }

    // Check the function signature names.
    let signatureNames = service.methods.map { $0.signatureName }
    var seenSignatureNames = Set<String>()

    for signatureName in signatureNames {
      if seenSignatureNames.contains(signatureName) {
        throw CodeGenError(
          code: .nonUniqueMethodName,
          message: """
            Methods of a service must have unique signature names. \
            \(signatureName) is used as a signature name for multiple methods of the \(service.name) service.
            """
        )
      }
      seenSignatureNames.insert(signatureName)
    }
  }

  private func checkEmptyNamespaceAndGeneratedNamespace(
    for services: [CodeGenerationRequest.ServiceDescriptor]
  ) throws {
    for service in services {
      if service.namespace.isEmpty {
        if !service.generatedNamespace.isEmpty {
          throw CodeGenError(
            code: .invalidGeneratedNamespace,
            message: """
              Services with an empty namespace must have an empty generated namespace. \
              \(service.name) has an empty namespace, but a non-empty generated namespace.
              """
          )
        }
      } else {
        if service.generatedNamespace.isEmpty {
          throw CodeGenError(
            code: .invalidGeneratedNamespace,
            message: """
              Services with a non-empty namespace must have a non-empty generated namespace. \
              \(service.name) has a non-empty namespace, but an empty generated namespace.
              """
          )
        }
      }
    }
  }

  private func checkServicesNamespacesAndGeneratedNamespacesCoincide(
    servicesByNamespace: [String: [CodeGenerationRequest.ServiceDescriptor]]
  ) throws {
    for (_, services) in servicesByNamespace {
      let generatedNamespace = services[0].generatedNamespace
      for service in services {
        if service.generatedNamespace != generatedNamespace {
          throw CodeGenError(
            code: .invalidGeneratedNamespace,
            message: """
              All services within a namespace must have the same generated namespace. \
              \(service.name) has not the same generated namespace as other services \
              within the \(service.namespace) namespace.
              """
          )
        }
      }
    }
  }
}

extension CodeGenerationRequest.ServiceDescriptor {
  var namespacedTypealiasGeneratedName: String {
    if self.generatedNamespace.isEmpty {
      return self.generatedName
    } else {
      return "\(self.generatedNamespace).\(self.generatedName)"
    }
  }

  var namespacedGeneratedName: String {
    if self.generatedNamespace.isEmpty {
      return self.generatedName
    } else {
      return "\(self.generatedNamespace)_\(self.generatedName)"
    }
  }

  var fullyQualifiedName: String {
    if self.namespace.isEmpty {
      return self.name
    } else {
      return "\(self.namespace).\(self.name)"
    }
  }
}
