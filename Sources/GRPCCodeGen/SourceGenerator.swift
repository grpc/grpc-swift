/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

public struct SourceGenerator {
  public var configuration: Configuration
  public init(configuration: Configuration) {
    self.configuration = configuration
  }

  public func generate(
    _ serviceRepresentation: CodeGenerationRequest
  ) throws -> SourceFile {
    let translator = IDLToStructuredSwiftTranslator()
    let textRenderer = TextBasedRenderer(indentation: self.configuration.indentation)

    let structuredSwiftRepresentation = try translator.translate(
      codeGenerationRequest: serviceRepresentation,
      visibility: self.configuration.visibility,
      client: configuration.client,
      server: configuration.server
    )
    let sourceFile = try textRenderer.render(structured: structuredSwiftRepresentation)

    return sourceFile
  }
}
