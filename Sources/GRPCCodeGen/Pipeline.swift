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

struct Pipeline {
  typealias Input = InMemoryInputFile
  typealias ParsedInput = CodeGenerationRequest
  typealias Output = SourceFile

  var parseInputStage: PipelineStage<InMemoryInputFile, CodeGenerationRequest>

  var generateCodeStage: PipelineStage<CodeGenerationRequest, Output>

  func run(_ input: Input) throws -> Output {
    try generateCodeStage.run(parseInputStage.run(input))
  }
}

func makeCodeGeneratorPipeline(
  parser: any InputParser,
  config: Configuration
) -> Pipeline {
  let generator = SourceGenerator(configuration: config)
  return .init(
    parseInputStage: .init(transition: { input in try parser.parse(input) }),
    generateCodeStage: .init(transition: { input in
      try generator.generate(serviceRepresentation: input)
    })
  )
}
