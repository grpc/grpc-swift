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

/// Transforms ``CodeGenerationRequest`` objects into ``StructuredSwiftRepresentation`` objects.
///
/// It represents the first step of the code generation process for IDL described RPCs.
protocol Translator {
  /// Translates the provided ``CodeGenerationRequest`` object, into Swift code representation.
  /// - Parameters:
  ///   - codeGenerationRequest: The IDL described RPCs representation.
  ///   - accessLevel: The access level that will restrict the protocols, extensions and methods in the generated code.
  ///   - accessLevelOnImports: Whether access levels should be included on imports.
  ///   - client: Whether or not client code should be generated from the IDL described RPCs representation.
  ///   - server: Whether or not server code should be generated from the IDL described RPCs representation.
  /// - Returns: A structured Swift representation of the generated code.
  /// - Throws: An error if there are issues translating the codeGenerationRequest.
  func translate(
    codeGenerationRequest: CodeGenerationRequest,
    accessLevel: SourceGenerator.Config.AccessLevel,
    accessLevelOnImports: Bool,
    client: Bool,
    server: Bool
  ) throws -> StructuredSwiftRepresentation
}
