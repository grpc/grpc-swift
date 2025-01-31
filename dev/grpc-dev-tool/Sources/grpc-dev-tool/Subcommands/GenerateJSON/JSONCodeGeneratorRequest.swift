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

import Foundation

struct JSONCodeGeneratorRequest: Codable {
  /// The service to generate.
  var service: ServiceSchema

  /// Configuration for the generation.
  var config: GeneratorConfig

  init(service: ServiceSchema, config: GeneratorConfig) {
    self.service = service
    self.config = config
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.service = try container.decode(ServiceSchema.self, forKey: .service)
    self.config = try container.decodeIfPresent(GeneratorConfig.self, forKey: .config) ?? .defaults
  }
}

struct ServiceSchema: Codable {
  var name: String
  var methods: [Method]

  struct Method: Codable {
    var name: String
    var input: String
    var output: String
    var kind: Kind

    enum Kind: String, Codable {
      case unary = "unary"
      case clientStreaming = "client_streaming"
      case serverStreaming = "server_streaming"
      case bidiStreaming = "bidi_streaming"

      var streamsInput: Bool {
        switch self {
        case .unary, .serverStreaming:
          return false
        case .clientStreaming, .bidiStreaming:
          return true
        }
      }

      var streamsOutput: Bool {
        switch self {
        case .unary, .clientStreaming:
          return false
        case .serverStreaming, .bidiStreaming:
          return true
        }
      }
    }
  }
}

struct GeneratorConfig: Codable {
  enum AccessLevel: String, Codable {
    case `internal`
    case `package`

    var capitalized: String {
      switch self {
      case .internal:
        return "Internal"
      case .package:
        return "Package"
      }
    }
  }

  var generateClient: Bool
  var generateServer: Bool
  var accessLevel: AccessLevel
  var accessLevelOnImports: Bool

  static var defaults: Self {
    GeneratorConfig(
      generateClient: true,
      generateServer: true,
      accessLevel: .internal,
      accessLevelOnImports: false
    )
  }

  init(
    generateClient: Bool,
    generateServer: Bool,
    accessLevel: AccessLevel,
    accessLevelOnImports: Bool
  ) {
    self.generateClient = generateClient
    self.generateServer = generateServer
    self.accessLevel = accessLevel
    self.accessLevelOnImports = accessLevelOnImports
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Self.defaults

    let generateClient = try container.decodeIfPresent(Bool.self, forKey: .generateClient)
    self.generateClient = generateClient ?? defaults.generateClient

    let generateServer = try container.decodeIfPresent(Bool.self, forKey: .generateServer)
    self.generateServer = generateServer ?? defaults.generateServer

    let accessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .accessLevel)
    self.accessLevel = accessLevel ?? defaults.accessLevel

    let accessLevelOnImports = try container.decodeIfPresent(
      Bool.self,
      forKey: .accessLevelOnImports
    )
    self.accessLevelOnImports = accessLevelOnImports ?? defaults.accessLevelOnImports
  }
}
