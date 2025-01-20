/*
 * Copyright 2025, gRPC Authors All rights reserved.
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

/// Creates a `ServiceDescriptor` from a JSON `ServiceSchema`.
extension ServiceDescriptor {
  init(_ service: ServiceSchema) {
    self.init(
      documentation: "",
      name: .init(
        base: service.name,
        generatedUpperCase: service.name,
        generatedLowerCase: service.name
      ),
      // Namespaces aren't supported.
      namespace: .init(
        base: "",
        generatedUpperCase: "",
        generatedLowerCase: ""
      ),
      methods: service.methods.map {
        MethodDescriptor($0)
      }
    )
  }
}

extension MethodDescriptor {
  /// Creates a `MethodDescriptor` from a JSON `ServiceSchema.Method`.
  init(_ method: ServiceSchema.Method) {
    self.init(
      documentation: "",
      name: .init(
        base: method.name,
        generatedUpperCase: method.name,
        generatedLowerCase: method.name
      ),
      isInputStreaming: method.kind.streamsInput,
      isOutputStreaming: method.kind.streamsOutput,
      inputType: method.input,
      outputType: method.output
    )
  }
}

extension SourceGenerator.Config.AccessLevel {
  init(_ level: GeneratorConfig.AccessLevel) {
    switch level {
    case .internal:
      self = .internal
    case .package:
      self = .package
    }
  }
}

extension SourceGenerator.Config {
  init(_ config: GeneratorConfig) {
    self.init(
      accessLevel: SourceGenerator.Config.AccessLevel(config.accessLevel),
      accessLevelOnImports: config.accessLevelOnImports,
      client: config.generateClient,
      server: config.generateServer,
      indentation: 2
    )
  }
}
