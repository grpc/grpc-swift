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
  private let typealiasTranslator = TypealiasTranslator()
  private let serverCodeTranslator = ServerCodeTranslator()

  func translate(
    codeGenerationRequest: CodeGenerationRequest,
    client: Bool,
    server: Bool
  ) throws -> StructuredSwiftRepresentation {
    let topComment = Comment.doc(codeGenerationRequest.leadingTrivia)
    let imports =
      try [ImportDescription(moduleName: "GRPCCore")]
      + codeGenerationRequest.dependencies.map { try self.translateImport(dependency: $0) }
    var codeBlocks: [CodeBlock] = []
    codeBlocks.append(
      contentsOf: try self.typealiasTranslator.translate(from: codeGenerationRequest)
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
  private func translateImport(
    dependency: CodeGenerationRequest.Dependency
  ) throws -> ImportDescription {
    var importDescription = ImportDescription(moduleName: dependency.module)
    if let item = dependency.item {
      if let matchedKind = ImportDescription.Kind.allCases.first(where: {
        "\($0)" == item.kind.value.description
      }) {
        importDescription.item = ImportDescription.Item(kind: matchedKind, name: item.name)
      } else {
        throw CodeGenError(
          code: .invalidKind,
          message: "Invalid kind name for import: \(item.kind.value.description)"
        )
      }
    }
    if let spi = dependency.spi {
      importDescription.spi = spi
    }

    let preconcurrency = dependency.preconcurrency.value
    switch preconcurrency {
    case .always:
      importDescription.preconcurrency = .always
    case .never:
      importDescription.preconcurrency = .never
    case .onOS(let OSs):
      importDescription.preconcurrency = .onOS(OSs)
    }
    return importDescription
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
