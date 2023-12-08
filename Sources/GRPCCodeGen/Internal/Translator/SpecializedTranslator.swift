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
