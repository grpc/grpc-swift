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

import GRPCCodeGen
import SwiftProtobufPluginLibrary

public struct ProtobufCodeGenerator {
  internal var configuration: SourceGenerator.Configuration

  public init(configuration: SourceGenerator.Configuration) {
    self.configuration = configuration
  }

  public func generateCode(from fileDescriptor: FileDescriptor) throws -> String {
    let parser = ProtobufCodeGenParser()
    let sourceGenerator = SourceGenerator(configuration: self.configuration)

    let codeGenerationRequest = try parser.parse(input: fileDescriptor)
    let sourceFile = try sourceGenerator.generate(codeGenerationRequest)
    return sourceFile.contents
  }
}
