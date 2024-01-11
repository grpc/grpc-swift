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
  private let serverCodeTranslator = ServerCodeTranslator()

  func translate(
    codeGenerationRequest: CodeGenerationRequest,
    client: Bool,
    server: Bool
  ) throws -> StructuredSwiftRepresentation {
    try self.validateInput(codeGenerationRequest)
    let typealiasTranslator = TypealiasTranslator(client: client, server: server)
    let topComment = Comment.doc(codeGenerationRequest.leadingTrivia)
    let imports: [ImportDescription] = [
      ImportDescription(moduleName: "GRPCCore")
    ]
    var codeBlocks: [CodeBlock] = []
    codeBlocks.append(
      contentsOf: try typealiasTranslator.translate(from: codeGenerationRequest)
    )

    if server {
      codeBlocks.append(
        contentsOf: try self.serverCodeTranslator.translate(from: codeGenerationRequest)
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
  private func validateInput(_ codeGenerationRequest: CodeGenerationRequest) throws {
    let servicesByNamespace = Dictionary(
      grouping: codeGenerationRequest.services,
      by: { $0.namespace }
    )
    try self.checkServiceNamesAreUnique(for: servicesByNamespace)
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
        if namespaces.contains(service.name) {
          throw CodeGenError(
            code: .nonUniqueServiceName,
            message: """
              Services with no namespace must not have the same names as the namespaces. \
              \(service.name) is used as a name for a service with no namespace and a namespace.
              """
          )
        }
      }
    }

    // Check that service names are unique within each namespace.
    for (namespace, services) in servicesByNamespace {
      var serviceNames: Set<String> = []
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
      }
    }
  }

  // Verify method names are unique for the service.
  private func checkMethodNamesAreUnique(
    in service: CodeGenerationRequest.ServiceDescriptor
  ) throws {
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
  }
}

extension CodeGenerationRequest.ServiceDescriptor {
  var namespacedTypealiasPrefix: String {
    if self.namespace.isEmpty {
      return self.name
    } else {
      return "\(self.namespace).\(self.name)"
    }
  }

  var namespacedPrefix: String {
    if self.namespace.isEmpty {
      return self.name
    } else {
      return "\(self.namespace)_\(self.name)"
    }
  }
}
