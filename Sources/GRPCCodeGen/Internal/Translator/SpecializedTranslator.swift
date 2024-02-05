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

/// Represents one responsibility of the ``Translator``: either the type aliases translation,
/// the server code translation or the client code translation.
protocol SpecializedTranslator {

  /// The ``SourceGenerator.Configuration.AccessLevel`` object used to represent the visibility level used in the generated code.
  var accessLevel: SourceGenerator.Configuration.AccessLevel { get }

  /// Generates an array of ``CodeBlock`` elements that will be part of the ``StructuredSwiftRepresentation`` object
  /// created by the ``Translator``.
  ///
  /// - Parameters:
  ///   - codeGenerationRequest: The ``CodeGenerationRequest`` object used to represent a Source IDL description of RPCs.
  /// - Returns: An array of ``CodeBlock`` elements.
  ///
  /// - SeeAlso: ``CodeGenerationRequest``, ``Translator``,  ``CodeBlock``.
  func translate(from codeGenerationRequest: CodeGenerationRequest) throws -> [CodeBlock]
}

extension SpecializedTranslator {
  /// The access modifier that corresponds with the access level from ``SourceGenerator.Configuration``.
  internal var accessModifier: AccessModifier {
    get {
      switch accessLevel.level {
      case .internal:
        return AccessModifier.internal
      case .package:
        return AccessModifier.package
      case .public:
        return AccessModifier.public
      }
    }
  }

  internal var availabilityGuard: AvailabilityDescription {
    AvailabilityDescription(osVersions: [
      .init(os: .macOS, version: "13.0"),
      .init(os: .iOS, version: "16.0"),
      .init(os: .watchOS, version: "9.0"),
      .init(os: .tvOS, version: "16.0"),
    ])
  }
}
