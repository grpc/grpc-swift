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

import XCTest

@testable import GRPCCodeGen

final class IDLToStructuredSwiftTranslatorSnippetBasedTests: XCTestCase {
  func testImports() throws {
    var dependencies = [CodeGenerationRequest.Dependency]()
    dependencies.append(CodeGenerationRequest.Dependency(module: "Foo"))
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .typealias, name: "Bar"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .struct, name: "Baz"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .class, name: "Bac"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .enum, name: "Bap"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .protocol, name: "Bat"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .let, name: "Baq"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .var, name: "Bag"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .func, name: "Bak"), module: "Foo")
    )

    let expectedSwift =
      """
      /// Some really exciting license header 2023.
      import GRPCCore
      import Foo
      import typealias Foo.Bar
      import struct Foo.Baz
      import class Foo.Bac
      import enum Foo.Bap
      import protocol Foo.Bat
      import let Foo.Baq
      import var Foo.Bag
      import func Foo.Bak
      """
    try self.assertIDLToStructuredSwiftTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(dependencies: dependencies),
      expectedSwift: expectedSwift
    )
  }

  func testPreconcurrencyImports() throws {
    var dependencies = [CodeGenerationRequest.Dependency]()
    dependencies.append(CodeGenerationRequest.Dependency(module: "Foo", preconcurrency: .required))
    dependencies.append(
      CodeGenerationRequest.Dependency(
        item: .init(kind: .enum, name: "Bar"),
        module: "Foo",
        preconcurrency: .required
      )
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(
        module: "Baz",
        preconcurrency: .requiredOnOS(["Deq", "Der"])
      )
    )
    let expectedSwift =
      """
      /// Some really exciting license header 2023.
      import GRPCCore
      @preconcurrency import Foo
      @preconcurrency import enum Foo.Bar
      #if os(Deq) || os(Der)
      @preconcurrency import Baz
      #else
      import Baz
      #endif
      """
    try self.assertIDLToStructuredSwiftTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(dependencies: dependencies),
      expectedSwift: expectedSwift
    )
  }

  func testSPIImports() throws {
    var dependencies = [CodeGenerationRequest.Dependency]()
    dependencies.append(CodeGenerationRequest.Dependency(module: "Foo", spi: "Secret"))
    dependencies.append(
      CodeGenerationRequest.Dependency(
        item: .init(kind: .enum, name: "Bar"),
        module: "Foo",
        spi: "Secret"
      )
    )

    let expectedSwift =
      """
      /// Some really exciting license header 2023.
      import GRPCCore
      @_spi(Secret) import Foo
      @_spi(Secret) import enum Foo.Bar
      """
    try self.assertIDLToStructuredSwiftTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(dependencies: dependencies),
      expectedSwift: expectedSwift
    )
  }

  private func assertIDLToStructuredSwiftTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String
  ) throws {
    let translator = IDLToStructuredSwiftTranslator()
    let structuredSwift = try translator.translate(
      codeGenerationRequest: codeGenerationRequest,
      client: false,
      server: false
    )
    let renderer = TextBasedRenderer.default
    let sourceFile = try renderer.render(structured: structuredSwift)
    let contents = sourceFile.contents
    try XCTAssertEqualWithDiff(contents, expectedSwift)
  }
}
