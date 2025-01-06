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

import Testing

@testable import GRPCCodeGen

// Used as a namespace for organising other structured swift tests.
@Suite("Structured Swift")
struct StructuredSwiftTests {}

func render(_ declaration: Declaration) -> String {
  let renderer = TextBasedRenderer(indentation: 2)
  renderer.renderDeclaration(declaration)
  return renderer.renderedContents()
}

func render(_ expression: Expression) -> String {
  let renderer = TextBasedRenderer(indentation: 2)
  renderer.renderExpression(expression)
  return renderer.renderedContents()
}

func render(_ blocks: [CodeBlock]) -> String {
  let renderer = TextBasedRenderer(indentation: 2)
  renderer.renderCodeBlocks(blocks)
  return renderer.renderedContents()
}

func render(_ imports: [ImportDescription]) -> String {
  let renderer = TextBasedRenderer(indentation: 2)
  renderer.renderImports(imports)
  return renderer.renderedContents()
}

enum RPCKind: Hashable, Sendable, CaseIterable {
  case unary
  case clientStreaming
  case serverStreaming
  case bidirectionalStreaming

  var streamsInput: Bool {
    switch self {
    case .clientStreaming, .bidirectionalStreaming:
      return true
    case .unary, .serverStreaming:
      return false
    }
  }

  var streamsOutput: Bool {
    switch self {
    case .serverStreaming, .bidirectionalStreaming:
      return true
    case .unary, .clientStreaming:
      return false
    }
  }
}
